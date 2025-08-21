#!/bin/bash

# Heizungsüberwachung Update für Raspberry Pi 5
# Löst Git-Konflikte automatisch und aktualisiert das System

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging-Funktionen
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNUNG] $1${NC}"
}

error() {
    echo -e "${RED}[FEHLER] $1${NC}"
}

# GitHub Repository
GITHUB_REPO="https://github.com/OliverRebock/HeizungsPI2.git"
PROJECT_DIR="/home/pi/heizung-monitor"

echo "🔄 Heizungsüberwachung - System Update"
echo "====================================="

# Prüfen ob root
if [[ $EUID -ne 0 ]]; then
    error "Bitte als root ausführen: sudo $0"
    exit 1
fi

# 1. Projekt-Verzeichnis prüfen
if [ ! -d "$PROJECT_DIR" ]; then
    error "Projekt-Verzeichnis nicht gefunden: $PROJECT_DIR"
    error "Führe zuerst die Vollinstallation aus!"
    exit 1
fi

cd "$PROJECT_DIR"

# 2. Services stoppen (falls vorhanden)
log "Stoppe laufende Services..."
systemctl stop heizung-monitor 2>/dev/null || true
systemctl stop heizung-dashboard 2>/dev/null || true

# 3. Git-Repository status prüfen und bereinigen
log "Bereinige Git-Repository..."

# Lokale Änderungen sichern
if [ -f ".env" ] && [ ! -f ".env.backup" ]; then
    log "Sichere .env Konfiguration..."
    cp .env .env.backup
fi

if [ -f "config/heating_circuits.yaml" ] && [ ! -f "config/heating_circuits.yaml.backup" ]; then
    log "Sichere Heizkreis-Konfiguration..."
    cp config/heating_circuits.yaml config/heating_circuits.yaml.backup
fi

# Git-Repository zurücksetzen und aktualisieren
log "Aktualisiere Repository..."
git fetch origin
git reset --hard HEAD  # Verwirft lokale Änderungen
git clean -fd           # Entfernt unverfolgte Dateien
git pull origin main

# 4. Gesicherte Konfigurationen wiederherstellen
if [ -f ".env.backup" ]; then
    log "Stelle .env Konfiguration wieder her..."
    cp .env.backup .env
fi

if [ -f "config/heating_circuits.yaml.backup" ]; then
    log "Stelle Heizkreis-Konfiguration wieder her..."
    cp config/heating_circuits.yaml.backup config/heating_circuits.yaml
fi

# 5. Script ausführbar machen
log "Aktualisiere Script-Berechtigungen..."
chmod +x install_rpi5.sh
chmod +x service_manager.sh
chmod +x docker-manage.sh
[ -f "scripts/backup.sh" ] && chmod +x scripts/backup.sh

# 6. Python Virtual Environment aktualisieren
log "Aktualisiere Python-Abhängigkeiten..."
if [ -d "venv" ]; then
    source venv/bin/activate
    pip install --upgrade pip
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    fi
else
    warn "Virtual Environment nicht gefunden - führe Vollinstallation aus!"
fi

# 7. Docker Container aktualisieren (falls vorhanden)
if command -v docker &> /dev/null; then
    log "Aktualisiere Docker Container..."
    
    # Docker Compose Funktion
    docker_compose() {
        if command -v docker-compose &> /dev/null; then
            docker-compose "$@"
        elif docker compose version &> /dev/null 2>&1; then
            docker compose "$@"
        else
            warn "Docker Compose nicht verfügbar"
            return 1
        fi
    }
    
    if [ -f "docker-compose.yml" ]; then
        docker_compose pull
        docker_compose up -d
        log "Docker Container aktualisiert"
    fi
fi

# 8. Services neu starten
log "Starte Services neu..."
systemctl daemon-reload

if systemctl is-enabled heizung-monitor &>/dev/null; then
    systemctl start heizung-monitor
    log "heizung-monitor Service gestartet"
fi

if systemctl is-enabled heizung-dashboard &>/dev/null; then
    systemctl start heizung-dashboard
    log "heizung-dashboard Service gestartet"
fi

# 9. Status prüfen
echo ""
echo "============================================"
log "Update abgeschlossen!"
echo "============================================"
echo ""

echo -e "${BLUE}📋 System-Status:${NC}"

# Service-Status
if systemctl is-active --quiet heizung-monitor; then
    echo -e "${GREEN}✅ Monitoring Service: Läuft${NC}"
else
    echo -e "${RED}❌ Monitoring Service: Gestoppt${NC}"
fi

if systemctl is-active --quiet heizung-dashboard; then
    echo -e "${GREEN}✅ Web Dashboard: Läuft${NC}"
    echo -e "${BLUE}🌐 Dashboard: http://$(hostname -I | awk '{print $1}'):5000${NC}"
else
    echo -e "${RED}❌ Web Dashboard: Gestoppt${NC}"
fi

# Docker Status
if [ -f "docker-compose.yml" ] && command -v docker &> /dev/null; then
    echo ""
    echo -e "${BLUE}🐳 Docker Container:${NC}"
    docker_compose ps
    echo ""
    echo -e "${BLUE}📊 InfluxDB: http://$(hostname -I | awk '{print $1}'):8086${NC}"
    echo -e "${BLUE}📈 Grafana: http://$(hostname -I | awk '{print $1}'):3000${NC}"
fi

echo ""
echo -e "${BLUE}🛠️  Verwaltung:${NC}"
echo "  ./service_manager.sh status    # Status aller Services"
echo "  ./service_manager.sh logs      # Live-Logs anzeigen"
echo "  ./service_manager.sh restart   # Services neu starten"
echo ""

echo -e "${GREEN}🎉 Update erfolgreich abgeschlossen!${NC}"

# Bereinigung
log "Räume temporäre Backup-Dateien auf..."
rm -f .env.backup config/heating_circuits.yaml.backup
