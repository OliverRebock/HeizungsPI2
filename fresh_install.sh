#!/bin/bash

# Heizungsüberwachung - Komplette Neuinstallation
# Für den Fall, dass Git-Probleme nicht lösbar sind

echo "🔄 Heizungsüberwachung - Komplette Neuinstallation"
echo "================================================="

# Prüfen ob als root ausgeführt
if [[ $EUID -ne 0 ]]; then
    echo "❌ Dieses Script muss als root ausgeführt werden!"
    echo "Verwendung: sudo $0"
    exit 1
fi

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNUNG] $1${NC}"
}

GITHUB_REPO="https://github.com/OliverRebock/HeizungsPI2.git"
PROJECT_DIR="/home/pi/heizung-monitor"
BACKUP_DIR="/home/pi/heizung-backup-$(date +%Y%m%d-%H%M%S)"

# 1. Existierende Installation sichern
if [ -d "$PROJECT_DIR" ]; then
    log "Sichere existierende Installation..."
    
    # Services stoppen
    systemctl stop heizung-monitor 2>/dev/null || true
    systemctl stop heizung-dashboard 2>/dev/null || true
    
    # Backup erstellen
    mkdir -p "$BACKUP_DIR"
    
    # Wichtige Konfigurationsdateien sichern
    [ -f "$PROJECT_DIR/.env" ] && cp "$PROJECT_DIR/.env" "$BACKUP_DIR/"
    [ -f "$PROJECT_DIR/config/heating_circuits.yaml" ] && cp "$PROJECT_DIR/config/heating_circuits.yaml" "$BACKUP_DIR/"
    
    log "Backup erstellt in: $BACKUP_DIR"
    
    # Altes Verzeichnis entfernen
    rm -rf "$PROJECT_DIR"
    log "Alte Installation entfernt"
fi

# 2. Repository neu klonen
log "Klon Repository neu..."
sudo -u pi git clone "$GITHUB_REPO" "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Berechtigungen setzen
chown -R pi:pi "$PROJECT_DIR"

# Git-Sicherheitswarnung beheben
sudo -u pi git config --global --add safe.directory "$PROJECT_DIR"

# 3. Konfiguration wiederherstellen
if [ -d "$BACKUP_DIR" ]; then
    log "Stelle Konfiguration wieder her..."
    
    if [ -f "$BACKUP_DIR/.env" ]; then
        cp "$BACKUP_DIR/.env" "$PROJECT_DIR/"
        chown pi:pi "$PROJECT_DIR/.env"
        log "✅ .env wiederhergestellt"
    fi
    
    if [ -f "$BACKUP_DIR/heating_circuits.yaml" ]; then
        mkdir -p "$PROJECT_DIR/config"
        cp "$BACKUP_DIR/heating_circuits.yaml" "$PROJECT_DIR/config/"
        chown pi:pi "$PROJECT_DIR/config/heating_circuits.yaml"
        log "✅ heating_circuits.yaml wiederhergestellt"
    fi
fi

# 4. Scripts ausführbar machen
log "Setze Script-Berechtigungen..."
find "$PROJECT_DIR" -name "*.sh" -type f -exec chmod +x {} \;

echo ""
echo "✅ Neuinstallation vorbereitet!"
echo ""
echo -e "${BLUE}📋 Nächste Schritte:${NC}"
echo "1. Installation starten: sudo ./install_rpi5.sh"
echo "2. Backup-Verzeichnis: $BACKUP_DIR"
echo ""
echo -e "${YELLOW}💡 Tipp: Das Backup kann nach erfolgreicher Installation gelöscht werden${NC}"
echo ""
