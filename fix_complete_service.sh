#!/bin/bash

# Heizungsüberwachung - Vollständiger Service Fix
# Behebt alle Service-Probleme inklusive fehlender .env Datei

echo "🔧 Vollständiger Service Fix"
echo "============================"
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

# Wechsle ins Projektverzeichnis
cd /home/pi/heizung-monitor || {
    print_error "Projektverzeichnis /home/pi/heizung-monitor nicht gefunden!"
    exit 1
}

print_status "Arbeitsverzeichnis: $(pwd)"

# Service stoppen
print_status "Stoppe heizung-monitor Service..."
sudo systemctl stop heizung-monitor
sleep 2

# Schritt 1: .env Datei erstellen/reparieren
print_status "Prüfe und erstelle .env Datei..."

if [ ! -f ".env" ]; then
    print_warning ".env Datei fehlt - erstelle Standard-Konfiguration"
    
    # .env aus .env.example kopieren oder erstellen
    if [ -f ".env.example" ]; then
        print_status "Kopiere .env.example zu .env"
        cp .env.example .env
    else
        print_status "Erstelle neue .env Datei"
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
LOG_FILE=heizung-monitor.log

# Monitoring
MONITORING_INTERVAL=30
EOF
    fi
    print_success ".env Datei erstellt"
else
    print_success ".env Datei bereits vorhanden"
fi

# Berechtigungen für .env setzen
chown pi:pi .env
chmod 644 .env

# Schritt 2: Konfigurationsdateien prüfen
print_status "Prüfe Konfigurationsdateien..."

# heating_circuits.yaml prüfen
if [ ! -f "config/heating_circuits.yaml" ]; then
    print_warning "Heizkreis-Konfiguration fehlt"
    mkdir -p config
    
    if [ -f "config/heating_circuits_example.yaml" ]; then
        cp config/heating_circuits_example.yaml config/heating_circuits.yaml
        print_success "Heizkreis-Konfiguration aus Beispiel erstellt"
    else
        print_warning "Erstelle minimale Heizkreis-Konfiguration"
        cat > config/heating_circuits.yaml << EOF
# Heizkreis-Konfiguration
heating_circuits:
  - name: "Obergeschoss"
    flow_sensor_id: "28-000000000001"
    return_sensor_id: "28-000000000002"
    location: "upstairs"
    
  - name: "Erdgeschoss" 
    flow_sensor_id: "28-000000000003"
    return_sensor_id: "28-000000000004"
    location: "ground_floor"
    
  - name: "Keller"
    flow_sensor_id: "28-000000000005"
    return_sensor_id: "28-000000000006"
    location: "basement"

heat_pump:
  flow_sensor_id: "28-000000000007"
  return_sensor_id: "28-000000000008"
  name: "Wärmepumpe"
EOF
    fi
else
    print_success "Heizkreis-Konfiguration gefunden"
fi

# Schritt 3: Python Virtual Environment prüfen/erstellen
print_status "Prüfe Python Virtual Environment..."

if [ ! -d "venv" ]; then
    print_warning "Virtual Environment nicht gefunden - erstelle neues"
    python3 -m venv venv
    print_success "Virtual Environment erstellt"
fi

# Virtual Environment aktivieren und Dependencies installieren
print_status "Aktiviere Virtual Environment und installiere Dependencies..."
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip

# Installiere Dependencies
if [ -f "requirements.txt" ]; then
    print_status "Installiere requirements.txt..."
    pip install -r requirements.txt
else
    print_warning "requirements.txt nicht gefunden - installiere Basis-Pakete"
    pip install influxdb-client pyyaml python-dotenv
    
    # Optional: DHT22 Pakete (falls verfügbar)
    pip install adafruit-circuitpython-dht adafruit-blinka || print_warning "DHT22 Pakete optional - nicht installiert"
fi

# Schritt 4: Berechtigungen korrigieren
print_status "Korrigiere Dateiberechtigungen..."
sudo chown -R pi:pi /home/pi/heizung-monitor
chmod +x *.sh
chmod 755 venv/bin/python

# Schritt 5: Systemd Service-Datei korrigieren
print_status "Erstelle korrekte systemd Service-Datei..."

SERVICE_FILE="/etc/systemd/system/heizung-monitor.service"

# Service-Datei mit korrekten Pfaden erstellen
sudo tee "$SERVICE_FILE" > /dev/null << EOF
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
ExecStart=/home/pi/heizung-monitor/venv/bin/python /home/pi/heizung-monitor/main.py
Restart=always
RestartSec=30
StartLimitInterval=0

# Logging Configuration
StandardOutput=journal
StandardError=journal
SyslogIdentifier=heizung-monitor

# Umgebungsvariablen aus .env Datei (optional)
EnvironmentFile=-/home/pi/heizung-monitor/.env

# Berechtigungen
UMask=0002

[Install]
WantedBy=multi-user.target
EOF

print_success "Service-Datei erstellt"

# Schritt 6: Systemd neu laden
print_status "Lade systemd-Konfiguration neu..."
sudo systemctl daemon-reload

# Schritt 7: Service aktivieren
print_status "Aktiviere heizung-monitor Service..."
sudo systemctl enable heizung-monitor

# Schritt 8: Python-Syntax testen
print_status "Teste Python-Syntax..."
source venv/bin/activate

if python3 -c "import sys; sys.path.append('.'); import main" 2>/dev/null; then
    print_success "Python-Code Syntax OK"
else
    print_warning "Python-Syntax Warnung - teste trotzdem"
fi

# Schritt 9: Service starten
print_status "Starte heizung-monitor Service..."
sudo systemctl start heizung-monitor

# Kurz warten und Status prüfen
sleep 5

if sudo systemctl is-active --quiet heizung-monitor; then
    print_success "Service erfolgreich gestartet!"
    
    echo ""
    echo "=== SERVICE STATUS ==="
    sudo systemctl status heizung-monitor --no-pager -l
    
    echo ""
    echo "=== LIVE LOGS (letzte 15 Zeilen) ==="
    sudo journalctl -u heizung-monitor --no-pager -n 15
    
else
    print_error "Service konnte nicht gestartet werden!"
    
    echo ""
    echo "=== AKTUELLE FEHLER-LOGS ==="
    sudo journalctl -u heizung-monitor --no-pager -n 20
    
    # Zusätzliche Diagnose
    echo ""
    echo "=== DATEI-EXISTENZ PRÜFUNG ==="
    print_status "Arbeitsverzeichnis: $(pwd)"
    print_status ".env Datei: $(test -f .env && echo 'Existiert' || echo 'FEHLT')"
    print_status "main.py: $(test -f main.py && echo 'Existiert' || echo 'FEHLT')"
    print_status "venv/bin/python: $(test -f venv/bin/python && echo 'Existiert' || echo 'FEHLT')"
    print_status "config Verzeichnis: $(test -d config && echo 'Existiert' || echo 'FEHLT')"
    
    # .env Inhalt zeigen
    if [ -f ".env" ]; then
        echo ""
        echo "=== .env INHALT ==="
        cat .env
    fi
fi

echo ""
echo "=== KONFIGURATION ==="
print_status "Projektverzeichnis: /home/pi/heizung-monitor"
print_status ".env Datei: $(test -f .env && echo '✅ Vorhanden' || echo '❌ Fehlt')"
print_status "Heizkreis-Config: $(test -f config/heating_circuits.yaml && echo '✅ Vorhanden' || echo '❌ Fehlt')"
print_status "Virtual Environment: $(test -d venv && echo '✅ Vorhanden' || echo '❌ Fehlt')"

echo ""
echo "=== NÄCHSTE SCHRITTE ==="
print_status "Service überwachen: sudo journalctl -u heizung-monitor -f"
print_status "Service neu starten: sudo systemctl restart heizung-monitor"
print_status "Service-Status: sudo systemctl status heizung-monitor"
print_status "Sensoren testen: cd /home/pi/heizung-monitor && source venv/bin/activate && python test_sensors.py"

echo ""
print_success "Vollständiger Service Fix abgeschlossen!"
