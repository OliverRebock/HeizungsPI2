#!/bin/bash

# InfluxDB Daten-Problem Quick-Fix
# Behebt: Keine Daten werden in InfluxDB geschrieben

echo "💾 InfluxDB Daten Quick-Fix"
echo "=========================="

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNUNG] $1${NC}"
}

error() {
    echo -e "${RED}[FEHLER] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

PROJECT_DIR="/home/pi/heizung-monitor"

# Zum Projektverzeichnis wechseln
if [ ! -d "$PROJECT_DIR" ]; then
    error "Projektverzeichnis nicht gefunden: $PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"

echo ""
log "🔍 Schritt 1: System-Diagnose..."

# 1. Docker Container prüfen
info "Docker Container Status:"
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    error "Docker Compose nicht verfügbar!"
    exit 1
fi

CONTAINER_STATUS=$($COMPOSE_CMD ps 2>/dev/null)
if echo "$CONTAINER_STATUS" | grep -q "influxdb"; then
    if echo "$CONTAINER_STATUS" | grep "influxdb" | grep -q "Up"; then
        log "✅ InfluxDB Container läuft"
    else
        warn "⚠️ InfluxDB Container ist gestoppt - starte neu..."
        $COMPOSE_CMD up -d influxdb
        sleep 5
    fi
else
    warn "⚠️ InfluxDB Container nicht gefunden - starte alle Container..."
    $COMPOSE_CMD up -d
    sleep 10
fi

# 2. Service Status prüfen
echo ""
info "Heizung-Monitor Service:"
if systemctl is-active --quiet heizung-monitor; then
    log "✅ Service läuft"
    
    # Service-Logs auf Fehler prüfen
    RECENT_ERRORS=$(journalctl -u heizung-monitor --since "10 minutes ago" | grep -i "error\|failed\|exception" | tail -3)
    if [ -n "$RECENT_ERRORS" ]; then
        warn "⚠️ Fehler in Service-Logs gefunden:"
        echo "$RECENT_ERRORS"
    else
        log "✅ Keine Fehler in Service-Logs"
    fi
else
    warn "⚠️ Service läuft nicht - starte Service..."
    sudo systemctl start heizung-monitor
    sleep 3
    
    if systemctl is-active --quiet heizung-monitor; then
        log "✅ Service erfolgreich gestartet"
    else
        error "❌ Service konnte nicht gestartet werden"
        journalctl -u heizung-monitor -n 5 --no-pager
    fi
fi

# 3. InfluxDB Verbindung testen
echo ""
log "🔗 Schritt 2: InfluxDB Verbindung testen..."

if [ -f ".env" ]; then
    source .env
    INFLUXDB_URL=${INFLUXDB_URL:-http://localhost:8086}
    INFLUXDB_TOKEN=${INFLUXDB_TOKEN:-heizung-monitoring-token-2024}
    INFLUXDB_ORG=${INFLUXDB_ORG:-heizung-monitoring}
    INFLUXDB_BUCKET=${INFLUXDB_BUCKET:-heizung-daten}
    
    info "Teste InfluxDB Erreichbarkeit..."
    if curl -s "$INFLUXDB_URL/health" | grep -q '"status":"pass"'; then
        log "✅ InfluxDB ist erreichbar"
        
        # Bucket prüfen
        info "Prüfe InfluxDB Bucket..."
        BUCKETS=$(curl -s -H "Authorization: Token $INFLUXDB_TOKEN" \
            "$INFLUXDB_URL/api/v2/buckets?org=$INFLUXDB_ORG" | \
            grep -o '"name":"[^"]*"' | cut -d'"' -f4)
        
        if echo "$BUCKETS" | grep -q "$INFLUXDB_BUCKET"; then
            log "✅ Bucket '$INFLUXDB_BUCKET' existiert"
        else
            warn "⚠️ Bucket '$INFLUXDB_BUCKET' fehlt!"
            echo "   Verfügbare Buckets: $BUCKETS"
            
            # Bucket erstellen
            info "Erstelle Bucket '$INFLUXDB_BUCKET'..."
            curl -s -X POST "$INFLUXDB_URL/api/v2/buckets" \
                -H "Authorization: Token $INFLUXDB_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"name\":\"$INFLUXDB_BUCKET\",\"orgID\":\"$INFLUXDB_ORG\",\"retentionRules\":[]}"
        fi
        
    else
        error "❌ InfluxDB nicht erreichbar!"
        echo "   URL: $INFLUXDB_URL"
        echo "   Prüfe Container: docker-compose logs influxdb"
    fi
else
    error "❌ .env Datei fehlt!"
    if [ -f ".env.example" ]; then
        log "Kopiere .env.example zu .env..."
        cp .env.example .env
        log "✅ .env Datei erstellt"
    fi
fi

# 4. Sensoren prüfen
echo ""
log "🌡️ Schritt 3: Sensoren prüfen..."

# 1-Wire Sensoren
SENSOR_COUNT=$(ls /sys/bus/w1/devices/28-* 2>/dev/null | wc -l)
if [ "$SENSOR_COUNT" -gt 0 ]; then
    log "✅ $SENSOR_COUNT DS18B20 Sensoren gefunden"
    
    # Ersten Sensor testen
    FIRST_SENSOR=$(ls /sys/bus/w1/devices/28-* 2>/dev/null | head -1)
    if [ -n "$FIRST_SENSOR" ]; then
        TEMP_DATA=$(cat "$FIRST_SENSOR/w1_slave" 2>/dev/null | grep "t=" | tail -1)
        if [ -n "$TEMP_DATA" ]; then
            log "✅ Sensor-Daten lesbar"
        else
            warn "⚠️ Sensor-Daten nicht lesbar"
        fi
    fi
else
    warn "⚠️ Keine DS18B20 Sensoren gefunden"
    echo "   Führe aus: chmod +x fix_1wire_sensors.sh && ./fix_1wire_sensors.sh"
fi

# Virtual Environment prüfen
if [ -d "venv" ]; then
    log "✅ Virtual Environment vorhanden"
    source venv/bin/activate
    
    # Python-Pakete prüfen
    info "Prüfe Python-Pakete..."
    MISSING_PACKAGES=""
    
    for package in "w1thermsensor" "influxdb_client" "adafruit_dht"; do
        if python -c "import $package" 2>/dev/null; then
            echo "   ✅ $package: OK"
        else
            echo "   ❌ $package: FEHLT"
            MISSING_PACKAGES="$MISSING_PACKAGES $package"
        fi
    done
    
    if [ -n "$MISSING_PACKAGES" ]; then
        warn "⚠️ Fehlende Python-Pakete installieren..."
        pip install -r requirements.txt
    fi
else
    warn "⚠️ Virtual Environment fehlt - erstelle..."
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
fi

# 5. Test-Schreibvorgang
echo ""
log "💾 Schritt 4: Test-Daten schreiben..."

if [ -f "venv/bin/python" ] && [ -f ".env" ]; then
    source .env
    source venv/bin/activate
    
    # Python Test-Script erstellen
    cat > test_influx_write.py << 'EOF'
#!/usr/bin/env python3
import os
import sys
from datetime import datetime
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS

# Konfiguration aus Umgebungsvariablen
url = os.getenv("INFLUXDB_URL", "http://localhost:8086")
token = os.getenv("INFLUXDB_TOKEN", "heizung-monitoring-token-2024")
org = os.getenv("INFLUXDB_ORG", "heizung-monitoring")
bucket = os.getenv("INFLUXDB_BUCKET", "heizung-daten")

print(f"🔗 Verbinde zu InfluxDB: {url}")
print(f"📊 Organisation: {org}")
print(f"🗂️  Bucket: {bucket}")

try:
    # Client erstellen
    client = InfluxDBClient(url=url, token=token, org=org)
    write_api = client.write_api(write_options=SYNCHRONOUS)
    
    # Test-Datenpunkt erstellen
    point = Point("test_measurement") \
        .tag("source", "quick_fix_test") \
        .field("value", 42.0) \
        .time(datetime.utcnow())
    
    # Daten schreiben
    write_api.write(bucket=bucket, org=org, record=point)
    print("✅ Test-Daten erfolgreich geschrieben!")
    
    # Daten lesen
    query_api = client.query_api()
    query = f'''
    from(bucket: "{bucket}")
    |> range(start: -1m)
    |> filter(fn: (r) => r._measurement == "test_measurement")
    |> filter(fn: (r) => r.source == "quick_fix_test")
    '''
    
    result = query_api.query(org=org, query=query)
    
    if result:
        print("✅ Test-Daten erfolgreich gelesen!")
        print("💾 InfluxDB Datenschreibung funktioniert!")
    else:
        print("⚠️ Test-Daten wurden geschrieben, aber nicht gefunden")
        
    client.close()
    
except Exception as e:
    print(f"❌ InfluxDB Test fehlgeschlagen: {e}")
    sys.exit(1)
EOF

    python test_influx_write.py
    WRITE_SUCCESS=$?
    
    # Cleanup
    rm -f test_influx_write.py
    
    if [ $WRITE_SUCCESS -eq 0 ]; then
        log "✅ InfluxDB Schreibtest erfolgreich!"
    else
        error "❌ InfluxDB Schreibtest fehlgeschlagen!"
    fi
else
    warn "⚠️ Test übersprungen - Python Environment oder .env fehlt"
fi

# 6. Service neu starten
echo ""
log "🔄 Schritt 5: Service-Neustart..."

sudo systemctl restart heizung-monitor
sleep 5

if systemctl is-active --quiet heizung-monitor; then
    log "✅ Service erfolgreich neu gestartet"
    
    # Kurz auf Logs warten
    sleep 3
    info "Aktuelle Service-Logs:"
    journalctl -u heizung-monitor -n 5 --no-pager -q
else
    error "❌ Service-Neustart fehlgeschlagen"
    journalctl -u heizung-monitor -n 5 --no-pager
fi

# 7. Empfehlungen
echo ""
log "🎯 Quick-Fix abgeschlossen!"
echo ""
echo "📊 Monitoring URLs:"
echo "   InfluxDB: http://$(hostname -I | awk '{print $1}'):8086"
echo "   Grafana:  http://$(hostname -I | awk '{print $1}'):3000"
echo ""
echo "🔧 Weitere Befehle zum Monitoring:"
echo "   Service-Logs: sudo journalctl -u heizung-monitor -f"
echo "   Container-Logs: docker-compose logs -f"
echo "   Sensoren testen: source venv/bin/activate && python test_sensors.py"
echo ""
echo "💡 Falls weiterhin keine Daten:"
echo "   1. Warte 2-3 Minuten nach Service-Start"
echo "   2. Prüfe Sensor-Verkabelung (1-Wire + DHT22)"
echo "   3. Führe vollständige Diagnose aus: ./diagnose_influxdb.sh"
