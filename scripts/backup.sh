#!/bin/bash
# Backup-Skript für die Heizungsüberwachung
# Sichert Konfiguration, Datenbank und Logs

set -e

# Konfiguration
BACKUP_DIR="/home/pi/backups/heizung-monitor"
PROJECT_DIR="/home/pi/heizung-monitor"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="heizung-backup_$DATE"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNUNG] $1${NC}"
}

error() {
    echo -e "${RED}[FEHLER] $1${NC}"
}

# Backup-Verzeichnis erstellen
mkdir -p "$BACKUP_DIR/$BACKUP_NAME"

log "🗄️ Starte Backup der Heizungsüberwachung..."

# 1. Konfigurationsdateien sichern
log "📁 Sichere Konfigurationsdateien..."
if [ -d "$PROJECT_DIR/config" ]; then
    cp -r "$PROJECT_DIR/config" "$BACKUP_DIR/$BACKUP_NAME/"
    log "✅ Konfiguration gesichert"
else
    warn "Kein config-Verzeichnis gefunden"
fi

# 2. Umgebungsvariablen sichern
if [ -f "$PROJECT_DIR/.env" ]; then
    cp "$PROJECT_DIR/.env" "$BACKUP_DIR/$BACKUP_NAME/"
    log "✅ Umgebungsvariablen gesichert"
fi

# 3. Docker Compose Konfiguration sichern
if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    cp "$PROJECT_DIR/docker-compose.yml" "$BACKUP_DIR/$BACKUP_NAME/"
    log "✅ Docker Compose Konfiguration gesichert"
fi

# 4. InfluxDB Daten exportieren
log "📊 Exportiere InfluxDB-Daten..."
if docker ps | grep -q heizung-influxdb; then
    # InfluxDB-Backup erstellen
    docker exec heizung-influxdb influx backup /tmp/backup_$DATE -t heizung-monitoring-token-2024
    
    # Backup aus Container kopieren
    docker cp heizung-influxdb:/tmp/backup_$DATE "$BACKUP_DIR/$BACKUP_NAME/influxdb_backup"
    
    # Temporäres Backup im Container löschen
    docker exec heizung-influxdb rm -rf /tmp/backup_$DATE
    
    log "✅ InfluxDB-Daten exportiert"
else
    warn "InfluxDB Container nicht aktiv - überspringe Datenbank-Backup"
fi

# 5. Grafana-Dashboards exportieren
log "📈 Exportiere Grafana-Dashboards..."
if docker ps | grep -q heizung-grafana; then
    mkdir -p "$BACKUP_DIR/$BACKUP_NAME/grafana"
    
    # Grafana-Daten kopieren
    docker cp heizung-grafana:/var/lib/grafana "$BACKUP_DIR/$BACKUP_NAME/grafana/" 2>/dev/null || warn "Grafana-Daten nicht kopierbar"
    
    log "✅ Grafana-Dashboards exportiert"
else
    warn "Grafana Container nicht aktiv - überspringe Dashboard-Backup"
fi

# 6. System-Logs sichern
log "📄 Sichere System-Logs..."
if [ -f "/var/log/heizung-monitor.log" ]; then
    cp "/var/log/heizung-monitor.log" "$BACKUP_DIR/$BACKUP_NAME/"
    log "✅ System-Logs gesichert"
fi

# Systemd-Service-Logs
if command -v journalctl >/dev/null; then
    journalctl -u heizung-monitor --since="7 days ago" > "$BACKUP_DIR/$BACKUP_NAME/service-logs.txt" 2>/dev/null || warn "Service-Logs nicht verfügbar"
fi

# 7. Backup komprimieren
log "🗜️ Komprimiere Backup..."
cd "$BACKUP_DIR"
tar -czf "$BACKUP_NAME.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_NAME"

# 8. Alte Backups löschen (behalte nur die letzten 7)
log "🧹 Räume alte Backups auf..."
find "$BACKUP_DIR" -name "heizung-backup_*.tar.gz" -type f -mtime +7 -delete

BACKUP_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_NAME.tar.gz" | cut -f1)
log "✅ Backup abgeschlossen!"
log "📦 Backup-Datei: $BACKUP_DIR/$BACKUP_NAME.tar.gz ($BACKUP_SIZE)"

# 9. Backup-Info ausgeben
echo ""
echo "📋 BACKUP-ZUSAMMENFASSUNG:"
echo "========================="
echo "Backup-Datei: $BACKUP_DIR/$BACKUP_NAME.tar.gz"
echo "Größe: $BACKUP_SIZE"
echo "Inhalt:"
tar -tzf "$BACKUP_DIR/$BACKUP_NAME.tar.gz" | head -20

# Anzahl verfügbarer Backups
BACKUP_COUNT=$(find "$BACKUP_DIR" -name "heizung-backup_*.tar.gz" | wc -l)
echo ""
echo "Verfügbare Backups: $BACKUP_COUNT"
echo "Backup-Verzeichnis: $BACKUP_DIR"
