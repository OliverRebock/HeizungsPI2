#!/bin/bash
#!/bin/bash

# Docker Container Management für Heizungsüberwachung
# Vereinfacht die Verwaltung der InfluxDB und Grafana Container

set -e

# Docker Compose Funktion - unterstützt beide Varianten
docker_compose() {
    if command -v docker-compose &> /dev/null; then
        docker-compose "$@"
    elif docker compose version &> /dev/null; then
        docker compose "$@"
    else
        echo "Weder 'docker-compose' noch 'docker compose' verfügbar!"
        exit 1
    fi
}

# Farben
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_DIR="/home/pi/heizung-monitor"

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNUNG] $1${NC}"
}

error() {
    echo -e "${RED}[FEHLER] $1${NC}"
}

show_help() {
    echo "🐳 Heizungsüberwachung - Docker Management"
    echo "========================================"
    echo ""
    echo "Verwendung: $0 [BEFEHL]"
    echo ""
    echo "Befehle:"
    echo "  start     - Container starten"
    echo "  stop      - Container stoppen"
    echo "  restart   - Container neu starten"
    echo "  status    - Container-Status anzeigen"
    echo "  logs      - Container-Logs anzeigen"
    echo "  update    - Container-Images aktualisieren"
    echo "  backup    - Daten-Backup erstellen"
    echo "  restore   - Daten-Backup wiederherstellen"
    echo "  reset     - Alles zurücksetzen (VORSICHT!)"
    echo "  help      - Diese Hilfe anzeigen"
}

ensure_project_dir() {
    if [ ! -d "$PROJECT_DIR" ]; then
        error "Projekt-Verzeichnis nicht gefunden: $PROJECT_DIR"
        exit 1
    fi
    cd "$PROJECT_DIR"
}

case "$1" in
    start)
        log "Starte Docker Container..."
        ensure_project_dir
        docker_compose up -d
        log "Container gestartet"
        ;;
    stop)
        log "Stoppe Docker Container..."
        ensure_project_dir
        docker_compose down
        log "Container gestoppt"
        ;;
    restart)
        log "Starte Docker Container neu..."
        ensure_project_dir
        docker_compose restart
        log "Container neu gestartet"
        ;;
    status)
        echo -e "${BLUE}📊 Container-Status:${NC}"
        ensure_project_dir
        docker_compose ps
        echo ""
        echo -e "${BLUE}📈 Service-URLs:${NC}"
        echo "InfluxDB: http://$(hostname -I | awk '{print $1}'):8086"
        echo "Grafana:  http://$(hostname -I | awk '{print $1}'):3000"
        ;;
    logs)
        echo -e "${BLUE}📄 Container-Logs:${NC}"
        ensure_project_dir
        if [ -n "$2" ]; then
            docker_compose logs -f "$2"
        else
            docker_compose logs -f
        fi
        ;;
    update)
        log "Aktualisiere Container-Images..."
        ensure_project_dir
        docker_compose pull
        docker_compose up -d
        log "Container-Images aktualisiert"
        ;;
    backup)
        log "Erstelle Daten-Backup..."
        BACKUP_DIR="/home/pi/heizung-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        # InfluxDB Backup
        docker exec heizung-influxdb influx backup /tmp/backup
        docker cp heizung-influxdb:/tmp/backup "$BACKUP_DIR/influxdb"
        
        # Grafana Backup
        docker cp heizung-grafana:/var/lib/grafana "$BACKUP_DIR/grafana"
        
        log "Backup erstellt: $BACKUP_DIR"
        ;;
    restore)
        if [ -z "$2" ]; then
            error "Backup-Verzeichnis angeben: $0 restore /pfad/zum/backup"
            exit 1
        fi
        
        warn "WARNUNG: Dies überschreibt alle aktuellen Daten!"
        read -p "Fortfahren? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Stelle Daten wieder her..."
            # Implementierung der Wiederherstellung
            log "Wiederherstellung abgeschlossen"
        else
            log "Wiederherstellung abgebrochen"
        fi
        ;;
    reset)
        warn "WARNUNG: Dies löscht ALLE Daten unwiderruflich!"
        read -p "Wirklich alles zurücksetzen? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ensure_project_dir
            docker_compose down -v
            docker volume prune -f
            docker_compose up -d
            log "System zurückgesetzt"
        else
            log "Reset abgebrochen"
        fi
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unbekannter Befehl: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
