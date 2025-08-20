#!/bin/bash
# Installations-Skript für Heizungsüberwachung auf Raspberry Pi 5
# Kann direkt von GitHub ausgeführt werden: curl -fsSL https://raw.githubusercontent.com/OliverRebock/HeizungsPI2/main/install_rpi5.sh | sudo bash

set -e  # Beende bei Fehlern

echo "🏠 Heizungsüberwachung - Installation für Raspberry Pi 5"
echo "=================================================="

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# GitHub Repository
GITHUB_REPO="https://github.com/OliverRebock/HeizungsPI2.git"
PROJECT_DIR="/home/pi/heizung-monitor"

# Logging-Funktion
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNUNG] $1${NC}"
}

error() {
    echo -e "${RED}[FEHLER] $1${NC}"
}

# 0. Projekt von GitHub klonen (falls noch nicht vorhanden)
if [ ! -d "$PROJECT_DIR" ]; then
    log "Schritt 0: Projekt von GitHub klonen..."
    cd /home/pi
    git clone "$GITHUB_REPO" heizung-monitor
    chown -R pi:pi "$PROJECT_DIR"
    log "Projekt erfolgreich von GitHub geklont"
else
    log "Projekt-Verzeichnis existiert bereits - aktualisiere..."
    cd "$PROJECT_DIR"
    git pull origin main || warn "Git pull fehlgeschlagen - verwende lokale Version"
fi

cd "$PROJECT_DIR"

# 1. System aktualisieren
log "Schritt 1: System aktualisieren..."
apt update && apt upgrade -y

# 2. Benötigte Pakete installieren
log "Schritt 2: Grundlegende Pakete installieren..."
apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    git \
    curl \
    wget \
    vim \
    htop \
    build-essential \
    cmake \
    pkg-config

# 3. 1-Wire Interface aktivieren
log "Schritt 3: 1-Wire Interface konfigurieren..."

# 1-Wire in /boot/config.txt aktivieren
if ! grep -q "dtoverlay=w1-gpio" /boot/firmware/config.txt; then
    echo "dtoverlay=w1-gpio,gpiopin=4" | tee -a /boot/firmware/config.txt
    log "1-Wire Interface in config.txt aktiviert (GPIO 4)"
else
    log "1-Wire Interface bereits in config.txt konfiguriert"
fi

# Module zu /etc/modules hinzufügen
if ! grep -q "w1-gpio" /etc/modules; then
    echo "w1-gpio" | tee -a /etc/modules
    echo "w1-therm" | tee -a /etc/modules
    log "1-Wire Module zu /etc/modules hinzugefügt"
else
    log "1-Wire Module bereits in /etc/modules vorhanden"
fi

# 4. InfluxDB 2.x installieren
log "Schritt 4: InfluxDB 2.x installieren..."

# Alte Repository-Einträge entfernen (falls vorhanden)
sudo rm -f /etc/apt/sources.list.d/influxdb.list
sudo rm -f /usr/share/keyrings/influxdb-archive-keyring.gpg

# Neuen GPG-Schlüssel korrekt importieren
wget -q https://repos.influxdata.com/influxdata-archive_compat.key
echo '393e8779c89ac8d958f81f942f9ad7fb82a25e133faddaf92e15b16e6ac9ce4c' influxdata-archive_compat.key | sha256sum -c && cat influxdata-archive_compat.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg > /dev/null

# Repository hinzufügen
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdb.list

sudo apt update
sudo apt install -y influxdb2

# InfluxDB Service aktivieren und starten
sudo systemctl enable influxdb
sudo systemctl start influxdb

log "InfluxDB installiert - Setup über http://$(hostname -I | awk '{print $1}'):8086"

# 5. Grafana installieren
log "Schritt 5: Grafana installieren..."

# Grafana Repository hinzufügen
curl -s https://packages.grafana.com/gpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/grafana.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt update
sudo apt install -y grafana

# Grafana Service aktivieren und starten
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

log "Grafana installiert - Web-Interface: http://$(hostname -I | awk '{print $1}'):3000"

# 6. Projekt-Verzeichnis erstellen
log "Schritt 6: Projekt-Verzeichnis vorbereiten..."

# 6. Projekt bereits geklont - Verzeichnis prüfen
log "Schritt 6: Projekt-Verzeichnis prüfen..."

if [ ! -d "$PROJECT_DIR" ]; then
    error "Projekt-Verzeichnis nicht gefunden. Klone manuell von GitHub."
    exit 1
fi

cd "$PROJECT_DIR"

# 7. Python Virtual Environment erstellen
log "Schritt 7: Python Virtual Environment einrichten..."

if [ ! -d "venv" ]; then
    python3 -m venv venv
    log "Virtual Environment erstellt"
fi

source venv/bin/activate

# 8. Python-Abhängigkeiten installieren (requirements.txt sollte existieren)
if [ -f "requirements.txt" ]; then
    log "Schritt 8: Python-Abhängigkeiten aus requirements.txt installieren..."
    pip install --upgrade pip
    pip install -r requirements.txt
    log "Python-Pakete aus requirements.txt installiert"
else
    log "Schritt 8: Grundlegende Python-Pakete installieren (Fallback)..."
    pip install --upgrade pip
    pip install \
        w1thermsensor==2.3.0 \
        adafruit-circuitpython-dht==4.0.9 \
        adafruit-blinka==8.22.2 \
        influxdb-client==1.43.0 \
        RPi.GPIO==0.7.1 \
        schedule==1.2.2 \
        python-dotenv==1.0.1 \
        pyyaml==6.0.1
    log "Grundlegende Python-Pakete installiert"
fi

# 9. Systemd Service erstellen
log "Schritt 9: Systemd Service konfigurieren..."

sudo tee /etc/systemd/system/heizung-monitor.service > /dev/null <<EOF
[Unit]
Description=Heizungsüberwachung mit Raspberry Pi
After=network.target influxdb.service
Wants=influxdb.service

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=$PROJECT_DIR
Environment=PATH=$PROJECT_DIR/venv/bin
ExecStart=$PROJECT_DIR/venv/bin/python main.py
Restart=always
RestartSec=10

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=heizung-monitor

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
log "Systemd Service erstellt"

# 10. Log-Verzeichnis und Berechtigungen
log "Schritt 10: Log-Verzeichnis einrichten..."

sudo mkdir -p /var/log/heizung-monitor
sudo chown pi:pi /var/log/heizung-monitor
sudo chmod 755 /var/log/heizung-monitor

# 11. GPIO-Berechtigungen für pi-User
log "Schritt 11: GPIO-Berechtigungen konfigurieren..."
sudo usermod -a -G gpio pi

# 12. Konfigurationsdateien prüfen
log "Schritt 12: Konfiguration prüfen..."

if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        warn "Bitte .env Datei anpassen!"
        warn "Editiere: nano .env"
    else
        warn ".env.example nicht gefunden - manuell erstellen!"
    fi
fi

if [ ! -f "config/heating_circuits.yaml" ]; then
    warn "Heizkreis-Konfiguration nicht gefunden!"
    warn "Prüfe: config/heating_circuits.yaml"
fi

# 13. 1-Wire Sensoren testen (nach Neustart)
echo ""
echo "============================================"
log "Installation abgeschlossen!"
echo "============================================"
echo ""

echo -e "${BLUE}📋 Nächste Schritte:${NC}"
echo ""
echo "1. System neu starten:"
echo "   sudo reboot"
echo ""
echo "2. Nach dem Neustart - 1-Wire Sensoren prüfen:"
echo "   ls /sys/bus/w1/devices/28-*"
echo ""
echo "3. InfluxDB Setup (Web-Interface):"
echo "   http://$(hostname -I | awk '{print $1}'):8086"
echo "   - Organisation: heizung-monitoring"
echo "   - Bucket: heizung-daten"
echo "   - Token notieren und in .env eintragen"
echo ""
echo "4. Konfiguration anpassen:"
echo "   cd $PROJECT_DIR"
echo "   nano .env"
echo "   nano config/heating_circuits.yaml"
echo ""
echo "5. Sensoren testen:"
echo "   cd $PROJECT_DIR"
echo "   source venv/bin/activate"
echo "   python test_sensors.py"
echo ""
echo "6. Service starten:"
echo "   sudo systemctl enable heizung-monitor"
echo "   sudo systemctl start heizung-monitor"
echo ""
echo "7. Grafana öffnen:"
echo "   http://$(hostname -I | awk '{print $1}'):3000"
echo "   Login: admin/admin"
echo ""
echo "8. Logs überwachen:"
echo "   sudo journalctl -u heizung-monitor -f"
echo ""

echo -e "${GREEN}🎉 Installation erfolgreich!${NC}"
echo -e "${YELLOW}⚠️  Neustart erforderlich für 1-Wire Interface!${NC}"
