#!/bin/bash
#!/bin/bash

# Heizungsüberwachung Installation für Raspberry Pi 5
# Automatische Installation aller Komponenten

set -e

# Docker Compose Funktion - unterstützt beide Varianten
docker_compose() {
    if command -v docker-compose &> /dev/null; then
        docker-compose "$@"
    elif docker compose version &> /dev/null; then
        docker compose "$@"
    else
        error "Weder 'docker-compose' noch 'docker compose' verfügbar!"
        exit 1
    fi
}
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

# 4. Docker und Docker Compose installieren
log "Schritt 4: Docker und Docker Compose installieren..."

# Docker installieren
if ! command -v docker &> /dev/null; then
    log "Installiere Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker pi
    log "Docker installiert"
else
    log "Docker bereits installiert"
fi

# Docker Compose installieren
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
    log "Installiere Docker Compose..."
    apt install -y docker-compose-plugin
    log "Docker Compose Plugin installiert"
else
    log "Docker Compose bereits verfügbar"
fi

# Docker Service starten
systemctl enable docker
systemctl start docker

# 5. InfluxDB und Grafana als Docker Container starten
log "Schritt 5: InfluxDB und Grafana Container starten..."

cd "$PROJECT_DIR"

# Docker Compose starten
docker_compose up -d

# Warten bis Container gestartet sind
log "Warte auf Container-Start..."
sleep 30

# Container-Status prüfen
if docker_compose ps | grep -q "Up"; then
    log "✅ InfluxDB und Grafana Container erfolgreich gestartet"
    log "📊 InfluxDB: http://$(hostname -I | awk '{print $1}'):8086"
    log "📈 Grafana: http://$(hostname -I | awk '{print $1}'):3000"
    log "🔑 Standard-Login: admin/heizung123!"
else
    error "❌ Container-Start fehlgeschlagen"
fi

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
        pyyaml==6.0.1 \
        flask==3.0.0 \
        requests==2.31.0
    log "Grundlegende Python-Pakete installiert"
fi

# 8a. Web Dashboard Service konfigurieren
log "Schritt 8a: Web Dashboard Service einrichten..."

sudo tee /etc/systemd/system/heizung-dashboard.service > /dev/null <<EOF
[Unit]
Description=Heizungsüberwachung Web Dashboard
After=network.target heizung-monitor.service
Wants=heizung-monitor.service

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=$PROJECT_DIR
Environment=PATH=$PROJECT_DIR/venv/bin
Environment=FLASK_APP=web_dashboard.py
Environment=FLASK_ENV=production
ExecStart=$PROJECT_DIR/venv/bin/python web_dashboard.py
Restart=always
RestartSec=5

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=heizung-dashboard

[Install]
WantedBy=multi-user.target
EOF

log "Web Dashboard Service erstellt"

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

# 11a. Backup System einrichten
log "Schritt 11a: Backup System konfigurieren..."

# Backup-Verzeichnis erstellen
sudo mkdir -p /home/pi/backups
sudo chown pi:pi /home/pi/backups
sudo chmod 755 /home/pi/backups

# Backup-Script ausführbar machen
if [ -f "scripts/backup.sh" ]; then
    chmod +x scripts/backup.sh
    log "Backup-Script berechtigt"
    
    # Cron-Job für automatische Backups einrichten (täglich um 2:00 Uhr)
    (crontab -l 2>/dev/null; echo "0 2 * * * cd $PROJECT_DIR && ./scripts/backup.sh") | crontab -
    log "Automatische Backups konfiguriert (täglich 2:00 Uhr)"
else
    warn "Backup-Script nicht gefunden: scripts/backup.sh"
fi

# 11b. Alert System Setup
log "Schritt 11b: Alert System konfigurieren..."

# Alert-Logs Verzeichnis
sudo mkdir -p /var/log/heizung-alerts
sudo chown pi:pi /var/log/heizung-alerts
sudo chmod 755 /var/log/heizung-alerts

log "Alert System vorbereitet"

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

# Service-Manager Script ausführbar machen
if [ -f "service_manager.sh" ]; then
    chmod +x service_manager.sh
    log "Service-Manager Script berechtigt"
else
    warn "Service-Manager Script nicht gefunden"
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
echo "   sudo systemctl enable heizung-dashboard"
echo "   sudo systemctl start heizung-dashboard"
echo ""
echo "   Oder verwende den Service-Manager:"
echo "   ./service_manager.sh enable"
echo "   ./service_manager.sh start"
echo ""
echo "7. Web Dashboard:"
echo "   http://$(hostname -I | awk '{print $1}'):5000"
echo ""
echo "8. Grafana öffnen:"
echo "   http://$(hostname -I | awk '{print $1}'):3000"
echo "   Login: admin/admin"
echo ""
echo "9. Service-Management:"
echo "   ./service_manager.sh status    # Status anzeigen"
echo "   ./service_manager.sh logs      # Live-Logs"
echo "   ./service_manager.sh test      # System testen"
echo "   ./service_manager.sh backup    # Backup ausführen"
echo ""
echo "10. Logs überwachen:"
echo "   sudo journalctl -u heizung-monitor -f"
echo "   sudo journalctl -u heizung-dashboard -f"
echo ""

echo -e "${GREEN}🎉 Installation erfolgreich!${NC}"
echo -e "${YELLOW}⚠️  Neustart erforderlich für 1-Wire Interface!${NC}"
