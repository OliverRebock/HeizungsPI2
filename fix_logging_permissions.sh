#!/bin/bash

# Heizungsüberwachung - Logging Permissions Fix
# Behebt Berechtigungsprobleme mit Log-Dateien

echo "🔧 Logging Permissions Fix"
echo "=========================="
echo ""

# Farben für bessere Lesbarkeit
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Service stoppen
print_status "Stoppe heizung-monitor Service..."
sudo systemctl stop heizung-monitor
sleep 2

# Log-Verzeichnis und Datei erstellen
print_status "Erstelle Log-Verzeichnis und setze Berechtigungen..."

LOG_DIR="/var/log"
LOG_FILE="/var/log/heizung-monitor.log"

# Log-Datei erstellen falls nicht vorhanden
if [ ! -f "$LOG_FILE" ]; then
    print_status "Erstelle Log-Datei: $LOG_FILE"
    sudo touch "$LOG_FILE"
else
    print_status "Log-Datei bereits vorhanden: $LOG_FILE"
fi

# Berechtigungen setzen
print_status "Setze Berechtigungen für Log-Datei..."
sudo chown pi:pi "$LOG_FILE"
sudo chmod 664 "$LOG_FILE"

# Prüfe Berechtigungen
print_status "Prüfe Log-Datei Berechtigungen..."
if sudo -u pi test -w "$LOG_FILE"; then
    print_success "Log-Datei ist schreibbar für Benutzer 'pi'"
else
    print_warning "Log-Datei ist nicht schreibbar - verwende lokales Log"
    
    # Fallback: Lokales Log-File
    cd /home/pi/heizung-monitor
    LOCAL_LOG="heizung-monitor.log"
    
    print_status "Erstelle lokales Log-File: $LOCAL_LOG"
    touch "$LOCAL_LOG"
    chown pi:pi "$LOCAL_LOG"
    chmod 664 "$LOCAL_LOG"
    
    # .env Datei anpassen
    if [ -f ".env" ]; then
        print_status "Aktualisiere .env für lokales Logging..."
        
        # LOG_FILE in .env setzen/ersetzen
        if grep -q "LOG_FILE=" .env; then
            sed -i "s|LOG_FILE=.*|LOG_FILE=/home/pi/heizung-monitor/heizung-monitor.log|" .env
        else
            echo "LOG_FILE=/home/pi/heizung-monitor/heizung-monitor.log" >> .env
        fi
        
        print_success "Log-Pfad in .env aktualisiert"
    else
        print_warning ".env Datei nicht gefunden - erstelle Standard-Konfiguration"
        cat > .env << EOF
# InfluxDB Konfiguration
INFLUXDB_URL=http://localhost:8086
INFLUXDB_TOKEN=heizung-monitoring-token-2024
INFLUXDB_ORG=heizung-monitoring
INFLUXDB_BUCKET=heizung-daten

# Sensor Konfiguration
SENSOR_INTERVAL=30
DHT22_PIN=18
W1_THERMAL_PATH=/sys/bus/w1/devices

# Logging
LOG_LEVEL=INFO
LOG_FILE=/home/pi/heizung-monitor/heizung-monitor.log
EOF
        print_success ".env Datei erstellt mit lokalem Logging"
    fi
fi

# Systemd Service-Datei aktualisieren für bessere Logging-Behandlung
print_status "Aktualisiere systemd Service-Datei..."

SERVICE_FILE="/etc/systemd/system/heizung-monitor.service"

sudo tee "$SERVICE_FILE" > /dev/null << 'EOF'
[Unit]
Description=Heizungsüberwachung mit Raspberry Pi 5
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi/heizung-monitor
Environment=PATH=/home/pi/heizung-monitor/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStartPre=/bin/sleep 10
ExecStart=/home/pi/heizung-monitor/venv/bin/python main.py
Restart=always
RestartSec=30
StartLimitInterval=0

# Logging Configuration
StandardOutput=journal
StandardError=journal
SyslogIdentifier=heizung-monitor

# Umgebungsvariablen
EnvironmentFile=/home/pi/heizung-monitor/.env

# Berechtigungen
UMask=0002

[Install]
WantedBy=multi-user.target
EOF

print_success "Service-Datei aktualisiert"

# Systemd neu laden
print_status "Lade systemd-Konfiguration neu..."
sudo systemctl daemon-reload

# Service aktivieren
print_status "Aktiviere heizung-monitor Service..."
sudo systemctl enable heizung-monitor

# Test: Service starten
print_status "Starte heizung-monitor Service (Test)..."
sudo systemctl start heizung-monitor

# Kurz warten und Status prüfen
sleep 3

if sudo systemctl is-active --quiet heizung-monitor; then
    print_success "Service erfolgreich gestartet!"
    
    echo ""
    echo "=== SERVICE STATUS ==="
    sudo systemctl status heizung-monitor --no-pager -l
    
    echo ""
    echo "=== LIVE LOGS (letzte 10 Zeilen) ==="
    sudo journalctl -u heizung-monitor --no-pager -n 10
    
else
    print_error "Service konnte nicht gestartet werden!"
    
    echo ""
    echo "=== AKTUELLE FEHLER-LOGS ==="
    sudo journalctl -u heizung-monitor --no-pager -n 15
    
    echo ""
    print_status "Versuche lokales Log zu lesen..."
    if [ -f "/home/pi/heizung-monitor/heizung-monitor.log" ]; then
        echo ""
        echo "=== LOKALE LOG-DATEI ==="
        tail -10 /home/pi/heizung-monitor/heizung-monitor.log
    fi
fi

echo ""
echo "=== LOG-KONFIGURATION ==="
print_status "System-Log: sudo journalctl -u heizung-monitor -f"

if [ -f "/var/log/heizung-monitor.log" ] && sudo -u pi test -w "/var/log/heizung-monitor.log"; then
    print_status "System-Log-Datei: /var/log/heizung-monitor.log"
elif [ -f "/home/pi/heizung-monitor/heizung-monitor.log" ]; then
    print_status "Lokale Log-Datei: /home/pi/heizung-monitor/heizung-monitor.log"
fi

echo ""
echo "=== NÄCHSTE SCHRITTE ==="
print_status "Service überwachen: sudo journalctl -u heizung-monitor -f"
print_status "Service stoppen: sudo systemctl stop heizung-monitor"
print_status "Service starten: sudo systemctl start heizung-monitor"
print_status "Service-Status: sudo systemctl status heizung-monitor"

echo ""
print_success "Logging Permissions Fix abgeschlossen!"
