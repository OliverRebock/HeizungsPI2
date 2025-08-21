#!/bin/bash

# InfluxDB Diagnose-Tool für Heizungsüberwachung
# Überprüft alle Komponenten der Datenverbindung

echo "🔍 InfluxDB Diagnose-Tool"
echo "========================"

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

error() {
    echo -e "${RED}[FEHLER] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

PROJECT_DIR="/home/pi/heizung-monitor"

# Prüfen ob im richtigen Verzeichnis
if [ ! -d "$PROJECT_DIR" ]; then
    error "Projekt-Verzeichnis nicht gefunden: $PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"

echo ""
echo "📋 System-Diagnose"
echo "=================="

# 1. Docker Container Status
echo ""
info "1. Docker Container Status:"
if command -v docker &> /dev/null; then
    if docker ps | grep -q "influxdb\|grafana"; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "influxdb|grafana|NAMES"
    else
        error "Keine InfluxDB/Grafana Container gefunden!"
        echo "Container starten mit: docker-compose up -d"
    fi
else
    error "Docker nicht installiert!"
fi

# 2. InfluxDB Erreichbarkeit
echo ""
info "2. InfluxDB Verbindung:"
if curl -s http://localhost:8086/health &>/dev/null; then
    echo -e "${GREEN}✅ InfluxDB erreichbar (Port 8086)${NC}"
    
    # InfluxDB Version
    VERSION=$(curl -s http://localhost:8086/health | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    echo "   Version: $VERSION"
else
    error "❌ InfluxDB nicht erreichbar!"
    echo "   Prüfe: docker-compose logs influxdb"
fi

# 3. 1-Wire Sensoren
echo ""
info "3. 1-Wire Sensoren:"
if [ -d "/sys/bus/w1/devices" ]; then
    SENSORS=$(ls /sys/bus/w1/devices/28-* 2>/dev/null | wc -l)
    if [ "$SENSORS" -gt 0 ]; then
        echo -e "${GREEN}✅ $SENSORS DS18B20 Sensoren erkannt${NC}"
        ls /sys/bus/w1/devices/28-* | while read sensor; do
            SENSOR_ID=$(basename "$sensor")
            TEMP=$(cat "$sensor/w1_slave" 2>/dev/null | grep "t=" | cut -d"=" -f2)
            if [ -n "$TEMP" ] && [ "$TEMP" != "85000" ]; then
                TEMP_C=$(echo "scale=1; $TEMP/1000" | bc -l 2>/dev/null || echo "N/A")
                echo "   $SENSOR_ID: ${TEMP_C}°C"
            else
                warn "   $SENSOR_ID: Keine gültigen Daten"
            fi
        done
    else
        error "❌ Keine DS18B20 Sensoren gefunden!"
        echo "   Prüfe 1-Wire Konfiguration und Verkabelung"
    fi
else
    error "❌ 1-Wire Interface nicht aktiviert!"
    echo "   Aktiviere mit: sudo bash install_rpi5.sh"
fi

# 4. DHT22 Sensor (falls vorhanden)
echo ""
info "4. DHT22 Sensor:"
if [ -f "src/sensors/dht22_sensor.py" ]; then
    if python3 -c "
import sys
sys.path.append('src')
try:
    from sensors.dht22_sensor import DHT22Sensor
    sensor = DHT22Sensor(18)
    data = sensor.read_data()
    if data['temperature'] is not None:
        print(f'✅ DHT22: {data[\"temperature\"]:.1f}°C, {data[\"humidity\"]:.1f}%')
    else:
        print('⚠️  DHT22: Keine Daten (normal bei ersten Versuchen)')
except Exception as e:
    print(f'❌ DHT22 Fehler: {e}')
" 2>/dev/null; then
        true
    else
        warn "DHT22 Sensor-Test fehlgeschlagen"
    fi
else
    warn "DHT22 Sensor-Code nicht gefunden"
fi

# 5. Service Status
echo ""
info "5. Systemd Services:"
for service in "heizung-monitor" "heizung-dashboard"; do
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✅ $service: Läuft${NC}"
    else
        error "❌ $service: Gestoppt"
        echo "   Starten mit: sudo systemctl start $service"
    fi
done

# 6. Konfigurationsdateien
echo ""
info "6. Konfiguration:"
if [ -f ".env" ]; then
    echo -e "${GREEN}✅ .env Datei vorhanden${NC}"
    echo "   InfluxDB URL: $(grep INFLUXDB_URL .env | cut -d'=' -f2)"
    echo "   Bucket: $(grep INFLUXDB_BUCKET .env | cut -d'=' -f2)"
else
    error "❌ .env Datei fehlt!"
    echo "   Erstelle mit: cp .env.example .env"
fi

if [ -f "config/heating_circuits.yaml" ]; then
    echo -e "${GREEN}✅ Heizkreis-Konfiguration vorhanden${NC}"
    CIRCUITS=$(grep -c "^  circuit_" config/heating_circuits.yaml 2>/dev/null || echo "0")
    echo "   Konfigurierte Heizkreise: $CIRCUITS"
else
    error "❌ Heizkreis-Konfiguration fehlt!"
    echo "   Prüfe: config/heating_circuits.yaml"
fi

# 7. Python Virtual Environment
echo ""
info "7. Python Umgebung:"
if [ -d "venv" ]; then
    echo -e "${GREEN}✅ Virtual Environment vorhanden${NC}"
    source venv/bin/activate
    if python -c "import w1thermsensor, adafruit_dht, influxdb_client" 2>/dev/null; then
        echo -e "${GREEN}✅ Alle Python-Pakete installiert${NC}"
    else
        error "❌ Python-Pakete fehlen!"
        echo "   Installiere mit: pip install -r requirements.txt"
    fi
else
    error "❌ Virtual Environment fehlt!"
    echo "   Erstelle mit: python3 -m venv venv"
fi

# 8. InfluxDB Daten prüfen
echo ""
info "8. InfluxDB Daten:"
if [ -f ".env" ]; then
    source .env
    if command -v curl &>/dev/null && curl -s http://localhost:8086/health &>/dev/null; then
        # Versuche Daten aus InfluxDB zu lesen
        QUERY_RESULT=$(curl -s -G http://localhost:8086/api/v2/query \
            --data-urlencode "org=${INFLUXDB_ORG:-heizung-monitoring}" \
            --data-urlencode "bucket=${INFLUXDB_BUCKET:-heizung-daten}" \
            --data-urlencode "q=from(bucket: \"${INFLUXDB_BUCKET:-heizung-daten}\") |> range(start: -1h) |> limit(n: 1)" \
            -H "Authorization: Token ${INFLUXDB_TOKEN:-heizung-monitoring-token-2024}" 2>/dev/null)
        
        if echo "$QUERY_RESULT" | grep -q "_value"; then
            echo -e "${GREEN}✅ Daten in InfluxDB gefunden${NC}"
            echo "   Letzte Daten verfügbar"
        else
            warn "⚠️  Keine Daten in InfluxDB"
            echo "   Monitoring-Service startet möglicherweise gerade"
        fi
    fi
fi

# 9. Logs prüfen
echo ""
info "9. Aktuelle Logs (letzte 5 Zeilen):"
if systemctl is-active --quiet heizung-monitor; then
    echo "=== Monitoring Service ==="
    journalctl -u heizung-monitor -n 5 --no-pager -q 2>/dev/null || echo "Keine Logs verfügbar"
fi

if docker ps | grep -q influxdb; then
    echo ""
    echo "=== InfluxDB Container ==="
    docker logs heizung-influxdb --tail 3 2>/dev/null || echo "Keine Container-Logs verfügbar"
fi

echo ""
echo "🎯 Empfohlene Aktionen:"
echo "======================"

# Empfehlungen basierend auf Diagnose
if ! docker ps | grep -q influxdb; then
    echo "1. Container starten: docker-compose up -d"
fi

if ! systemctl is-active --quiet heizung-monitor; then
    echo "2. Monitoring-Service starten: sudo systemctl start heizung-monitor"
fi

if [ ! -f ".env" ]; then
    echo "3. Konfiguration erstellen: cp .env.example .env"
fi

SENSORS=$(ls /sys/bus/w1/devices/28-* 2>/dev/null | wc -l)
if [ "$SENSORS" -eq 0 ]; then
    echo "4. 1-Wire Interface aktivieren: sudo reboot"
fi

echo ""
echo "📊 Monitoring URLs:"
echo "  InfluxDB: http://$(hostname -I | awk '{print $1}'):8086"
echo "  Grafana:  http://$(hostname -I | awk '{print $1}'):3000"
if systemctl is-active --quiet heizung-dashboard; then
    echo "  Dashboard: http://$(hostname -I | awk '{print $1}'):5000"
fi

echo ""
echo "🔧 Weitere Hilfe:"
echo "  Live-Logs: sudo journalctl -u heizung-monitor -f"
echo "  Service-Status: ./service_manager.sh status"
echo "  Container-Logs: docker-compose logs -f"
