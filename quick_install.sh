#!/bin/bash
# Schnelle GitHub-basierte Installation für Heizungsüberwachung
# Verwendung: curl -fsSL https://raw.githubusercontent.com/OliverRebock/HeizungsPI2/main/quick_install.sh | sudo bash

set -e

echo "🚀 Heizungsüberwachung - Schnellinstallation von GitHub"
echo "======================================================"

# Farben
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Variablen
GITHUB_REPO="https://github.com/OliverRebock/HeizungsPI2.git"
PROJECT_DIR="/home/pi/heizung-monitor"

log "Starte GitHub-basierte Installation..."

# Git prüfen/installieren
if ! command -v git &> /dev/null; then
    log "Git wird installiert..."
    apt update
    apt install -y git
fi

# Projekt klonen
log "Klon Projekt von GitHub..."
cd /home/pi

if [ -d "$PROJECT_DIR" ]; then
    log "Projekt-Verzeichnis existiert - aktualisiere..."
    cd "$PROJECT_DIR"
    git pull origin main
else
    log "Klon neues Projekt..."
    git clone "$GITHUB_REPO" heizung-monitor
fi

# Berechtigungen setzen
chown -R pi:pi "$PROJECT_DIR"

# Installations-Skript ausführen
log "Führe Haupt-Installationsskript aus..."
cd "$PROJECT_DIR"
chmod +x install_rpi5.sh
bash install_rpi5.sh

log "✅ Installation abgeschlossen!"
echo ""
echo -e "${BLUE}Nächste Schritte:${NC}"
echo "1. sudo reboot"
echo "2. Nach dem Neustart: Sensoren testen"
echo "3. InfluxDB konfigurieren: http://$(hostname -I | awk '{print $1}'):8086"
echo "4. Grafana öffnen: http://$(hostname -I | awk '{print $1}'):3000"
