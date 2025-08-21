#!/bin/bash

# Service Manager für Heizungsüberwachung
# Vereinfacht die Verwaltung aller Services

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SERVICES=("heizung-monitor" "heizung-dashboard")

# Docker Compose Funktion - unterstützt beide Varianten
docker_compose() {
    if command -v docker-compose &> /dev/null; then
        docker-compose "$@"
    elif docker compose version &> /dev/null; then
        docker compose "$@"
    else
        echo "Weder 'docker-compose' noch 'docker compose' verfügbar!"
        return 1
    fi
}

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Hilfe anzeigen
show_help() {
    echo "Heizungsüberwachung Service Manager"
    echo ""
    echo "Verwendung: $0 [BEFEHL]"
    echo ""
    echo "Befehle:"
    echo "  start     - Alle Services starten"
    echo "  stop      - Alle Services stoppen"
    echo "  restart   - Alle Services neu starten"
    echo "  status    - Status aller Services anzeigen"
    echo "  enable    - Services für Autostart aktivieren"
    echo "  disable   - Services für Autostart deaktivieren"
    echo "  logs      - Live-Logs aller Services anzeigen"
    echo "  backup    - Manuelles Backup ausführen"
    echo "  test      - Sensoren und System testen"
    echo "  diagnose  - Vollständige System-Diagnose"
    echo "  help      - Diese Hilfe anzeigen"
    echo ""
}

# Service-Status anzeigen
show_status() {
    echo "=== Service Status ==="
    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            echo -e "${GREEN}✅ $service: Läuft${NC}"
        else
            echo -e "${RED}❌ $service: Gestoppt${NC}"
        fi
        
        if systemctl is-enabled --quiet "$service"; then
            echo -e "   ${BLUE}🔄 Autostart: Aktiviert${NC}"
        else
            echo -e "   ${YELLOW}⏹️  Autostart: Deaktiviert${NC}"
        fi
        echo ""
    done
    
    # Docker Container Status
    echo "=== Docker Container Status ==="
    cd "$(dirname "$0")"
    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null 2>&1; then
        docker_compose ps
    else
        echo "Docker Compose nicht verfügbar"
    fi
}

# Services starten
start_services() {
    log "Starte alle Services..."
    for service in "${SERVICES[@]}"; do
        log "Starte $service..."
        sudo systemctl start "$service"
    done
    log "Alle Services gestartet"
}

# Services stoppen
stop_services() {
    log "Stoppe alle Services..."
    for service in "${SERVICES[@]}"; do
        log "Stoppe $service..."
        sudo systemctl stop "$service"
    done
    log "Alle Services gestoppt"
}

# Services neu starten
restart_services() {
    log "Starte alle Services neu..."
    for service in "${SERVICES[@]}"; do
        log "Starte $service neu..."
        sudo systemctl restart "$service"
    done
    log "Alle Services neu gestartet"
}

# Services für Autostart aktivieren
enable_services() {
    log "Aktiviere Autostart für alle Services..."
    for service in "${SERVICES[@]}"; do
        log "Aktiviere $service..."
        sudo systemctl enable "$service"
    done
    log "Autostart für alle Services aktiviert"
}

# Services für Autostart deaktivieren
disable_services() {
    log "Deaktiviere Autostart für alle Services..."
    for service in "${SERVICES[@]}"; do
        log "Deaktiviere $service..."
        sudo systemctl disable "$service"
    done
    log "Autostart für alle Services deaktiviert"
}

# Live-Logs anzeigen
show_logs() {
    log "Zeige Live-Logs aller Services..."
    log "Drücke Ctrl+C zum Beenden"
    sleep 2
    
    # Alle Service-Logs parallel anzeigen
    sudo journalctl -u heizung-monitor -u heizung-dashboard -f --output=short
}

# Backup ausführen
run_backup() {
    log "Führe manuelles Backup aus..."
    cd "$(dirname "$0")"
    
    if [ -f "scripts/backup.sh" ]; then
        ./scripts/backup.sh
        log "Backup abgeschlossen"
    else
        error "Backup-Script nicht gefunden!"
        exit 1
    fi
}

# System testen
test_system() {
    log "Führe Systemtest aus..."
    cd "$(dirname "$0")"
    
    # Virtual Environment aktivieren
    if [ -d "venv" ]; then
        source venv/bin/activate
    else
        error "Virtual Environment nicht gefunden!"
        exit 1
    fi
    
    # Sensoren testen
    if [ -f "test_sensors.py" ]; then
        python test_sensors.py
    else
        error "Test-Script nicht gefunden!"
        exit 1
    fi
    
    log "Systemtest abgeschlossen"
}

# Vollständige Diagnose
run_diagnose() {
    log "Führe vollständige System-Diagnose aus..."
    cd "$(dirname "$0")"
    
    if [ -f "diagnose_influxdb.sh" ]; then
        chmod +x diagnose_influxdb.sh
        ./diagnose_influxdb.sh
    else
        error "Diagnose-Script nicht gefunden!"
        exit 1
    fi
}

# Hauptlogik
case "${1:-help}" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    status)
        show_status
        ;;
    enable)
        enable_services
        ;;
    disable)
        disable_services
        ;;
    logs)
        show_logs
        ;;
    backup)
        run_backup
        ;;
    test)
        test_system
        ;;
    diagnose)
        run_diagnose
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        error "Unbekannter Befehl: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
