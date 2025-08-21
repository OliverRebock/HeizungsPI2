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
    # Nur echte DS18B20 Sensoren zählen (beginnen mit 28-)
    SENSORS=$(ls -d /sys/bus/w1/devices/28-* 2>/dev/null | wc -l)
    if [ "$SENSORS" -gt 0 ]; then
        echo -e "${GREEN}✅ $SENSORS DS18B20 Sensoren erkannt${NC}"
        # Nur die echten Sensor-Verzeichnisse durchgehen
        for sensor_dir in /sys/bus/w1/devices/28-*; do
            if [ -d "$sensor_dir" ]; then
                SENSOR_ID=$(basename "$sensor_dir")
                echo "   🔍 Prüfe Sensor: $SENSOR_ID"
                
                # w1_slave Datei prüfen
                if [ -f "$sensor_dir/w1_slave" ]; then
                    echo "     - w1_slave Datei gefunden"
                    
                    # Sensor-Daten vollständig anzeigen für Debugging
                    SLAVE_DATA=$(cat "$sensor_dir/w1_slave" 2>/dev/null)
                    if [ -n "$SLAVE_DATA" ]; then
                        echo "     - Rohdaten: $SLAVE_DATA"
                        
                        # CRC-Check (erste Zeile sollte 'YES' enthalten)
                        CRC_LINE=$(echo "$SLAVE_DATA" | head -1)
                        if echo "$CRC_LINE" | grep -q "YES"; then
                            echo "     - CRC Check: ✅ OK"
                            
                            # Temperatur extrahieren
                            TEMP_LINE=$(echo "$SLAVE_DATA" | grep "t=" | tail -1)
                            if [ -n "$TEMP_LINE" ]; then
                                TEMP=$(echo "$TEMP_LINE" | sed 's/.*t=//')
                                echo "     - Temperatur Raw: $TEMP"
                                
                                if [ -n "$TEMP" ] && [ "$TEMP" != "85000" ] && [ "$TEMP" -gt -55000 ] && [ "$TEMP" -lt 125000 ]; then
                                    # bc installiert prüfen
                                    if command -v bc &> /dev/null; then
                                        TEMP_C=$(echo "scale=1; $TEMP/1000" | bc -l)
                                    else
                                        # Fallback ohne bc
                                        TEMP_C=$(awk "BEGIN {printf \"%.1f\", $TEMP/1000}")
                                    fi
                                    echo "   📡 $SENSOR_ID: ${GREEN}${TEMP_C}°C${NC}"
                                else
                                    warn "   ⚠️ $SENSOR_ID: Ungültige Temperatur ($TEMP)"
                                fi
                            else
                                warn "   ❌ $SENSOR_ID: Keine Temperatur-Zeile gefunden"
                            fi
                        else
                            error "   ❌ $SENSOR_ID: CRC Check fehlgeschlagen - $CRC_LINE"
                            echo "     Sensor möglicherweise defekt oder Verkabelung prüfen"
                        fi
                    else
                        error "   ❌ $SENSOR_ID: w1_slave Datei ist leer"
                    fi
                else
                    warn "   ❌ $SENSOR_ID: w1_slave Datei fehlt"
                fi
                echo ""
            fi
        done
    else
        error "❌ Keine DS18B20 Sensoren gefunden!"
        echo "   Prüfe 1-Wire Konfiguration und Verkabelung"
        echo "   Module neu laden: sudo modprobe -r w1-therm w1-gpio && sudo modprobe w1-gpio w1-therm"
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
info "8. InfluxDB Daten & Verbindung:"
if [ -f ".env" ]; then
    source .env
    
    # InfluxDB Gesundheitscheck
    if curl -s http://localhost:8086/health &>/dev/null; then
        echo -e "${GREEN}✅ InfluxDB Service erreichbar${NC}"
        
        # Bucket prüfen
        BUCKETS=$(curl -s -H "Authorization: Token ${INFLUXDB_TOKEN:-heizung-monitoring-token-2024}" \
            http://localhost:8086/api/v2/buckets 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
        
        if echo "$BUCKETS" | grep -q "${INFLUXDB_BUCKET:-heizung-daten}"; then
            echo -e "${GREEN}✅ InfluxDB Bucket '${INFLUXDB_BUCKET:-heizung-daten}' existiert${NC}"
        else
            error "❌ InfluxDB Bucket '${INFLUXDB_BUCKET:-heizung-daten}' fehlt!"
            echo "   Verfügbare Buckets: $BUCKETS"
        fi
        
        # Versuche Daten zu lesen
        echo ""
        echo "   📊 Datenbankinhalt prüfen..."
        
        # Query für letzte Daten
        QUERY_RESULT=$(curl -s -G http://localhost:8086/api/v2/query \
            --data-urlencode "org=${INFLUXDB_ORG:-heizung-monitoring}" \
            --data-urlencode "q=from(bucket: \"${INFLUXDB_BUCKET:-heizung-daten}\") |> range(start: -24h) |> group() |> count() |> yield()" \
            -H "Authorization: Token ${INFLUXDB_TOKEN:-heizung-monitoring-token-2024}" 2>/dev/null)
        
        if echo "$QUERY_RESULT" | grep -q "_value"; then
            DATA_COUNT=$(echo "$QUERY_RESULT" | grep -o '"_value":[0-9]*' | head -1 | cut -d':' -f2)
            echo -e "${GREEN}✅ $DATA_COUNT Datenpunkte in letzten 24h gefunden${NC}"
        else
            warn "⚠️  Keine Daten in InfluxDB (letzte 24h)"
        fi
        
        # Query für verschiedene Measurements
        echo ""
        echo "   📈 Measurement-Typen prüfen..."
        for measurement in "temperature" "heating_room" "sensor_data" "heating_circuit"; do
            MEASUREMENT_DATA=$(curl -s -G http://localhost:8086/api/v2/query \
                --data-urlencode "org=${INFLUXDB_ORG:-heizung-monitoring}" \
                --data-urlencode "q=from(bucket: \"${INFLUXDB_BUCKET:-heizung-daten}\") |> range(start: -1h) |> filter(fn: (r) => r._measurement == \"$measurement\") |> limit(n: 1)" \
                -H "Authorization: Token ${INFLUXDB_TOKEN:-heizung-monitoring-token-2024}" 2>/dev/null)
            
            if echo "$MEASUREMENT_DATA" | grep -q "_value"; then
                echo -e "   ${GREEN}✅ $measurement: Daten vorhanden${NC}"
            else
                echo -e "   ${YELLOW}⚠️  $measurement: Keine Daten${NC}"
            fi
        done
        
    else
        error "❌ InfluxDB Service nicht erreichbar!"
        echo "   Prüfe Container-Status: docker-compose ps"
        echo "   Prüfe Container-Logs: docker-compose logs influxdb"
    fi
else
    error "❌ .env Datei nicht gefunden!"
    echo "   Kopiere .env.example zu .env"
fi

# 9. Service-Status detailliert
echo ""
info "9. Heizung-Monitor Service Status:"
if systemctl is-active --quiet heizung-monitor; then
    echo -e "${GREEN}✅ Service läuft${NC}"
    
    # Service-Details
    echo "   📊 Service-Details:"
    systemctl show heizung-monitor --property=ActiveState,SubState,LoadState,ExecMainStartTimestamp | while read line; do
        echo "      $line"
    done
    
    # Prozess-Info
    PID=$(systemctl show heizung-monitor --property=MainPID | cut -d'=' -f2)
    if [ "$PID" != "0" ]; then
        echo "   🔍 Prozess-Info (PID: $PID):"
        ps -p $PID -o pid,ppid,cmd,etime 2>/dev/null || echo "      Prozess-Info nicht verfügbar"
    fi
    
else
    error "❌ Service läuft NICHT!"
    echo "   Status: $(systemctl is-active heizung-monitor)"
    echo "   Starte mit: sudo systemctl start heizung-monitor"
fi

# 10. Logs erweitert prüfen
echo ""
info "10. Detaillierte Log-Analyse:"

echo "   === Heizung-Monitor Service Logs (letzte 10 Zeilen) ==="
if journalctl -u heizung-monitor -n 10 --no-pager -q 2>/dev/null; then
    echo ""
else
    echo "   Keine Service-Logs verfügbar"
fi

# Nach Fehlern suchen
echo "   === Fehler in Service-Logs ==="
ERROR_LOGS=$(journalctl -u heizung-monitor --since "1 hour ago" | grep -i "error\|failed\|exception" | tail -5)
if [ -n "$ERROR_LOGS" ]; then
    echo "$ERROR_LOGS"
else
    echo "   Keine Fehler in letzter Stunde gefunden"
fi

echo ""
echo "   === InfluxDB Container Logs (letzte 5 Zeilen) ==="
if docker ps | grep -q influxdb; then
    docker logs heizung-influxdb --tail 5 2>/dev/null || echo "   Keine Container-Logs verfügbar"
else
    echo "   InfluxDB Container läuft nicht!"
fi

# 11. Konfiguration prüfen
echo ""
info "11. Konfiguration prüfen:"

if [ -f "main.py" ]; then
    echo -e "${GREEN}✅ main.py vorhanden${NC}"
    
    # Nach InfluxDB-Verbindung in main.py suchen
    if grep -q "influxdb_client\|InfluxDB" main.py; then
        echo "   ✅ InfluxDB-Integration in main.py gefunden"
    else
        warn "   ⚠️  Keine InfluxDB-Integration in main.py erkannt"
    fi
else
    error "❌ main.py fehlt!"
fi

if [ -f "config/heating_circuits.yaml" ]; then
    echo -e "${GREEN}✅ Heizkreis-Konfiguration vorhanden${NC}"
    SENSOR_COUNT=$(grep -c "sensor_id:" config/heating_circuits.yaml 2>/dev/null || echo "0")
    echo "   📊 Konfigurierte Sensoren: $SENSOR_COUNT"
else
    warn "⚠️  config/heating_circuits.yaml fehlt"
fi

echo ""
echo "🎯 Empfohlene Aktionen (InfluxDB Daten-Problem):"
echo "==============================================="

# Priorisierte Empfehlungen für fehlende Daten
echo ""
echo "🔴 KRITISCH - Sofortige Maßnahmen:"

if ! docker ps | grep -q influxdb; then
    echo "   1. InfluxDB Container starten:"
    echo "      docker-compose up -d"
    echo ""
fi

if ! systemctl is-active --quiet heizung-monitor; then
    echo "   2. Monitoring-Service starten:"
    echo "      sudo systemctl start heizung-monitor"
    echo "      sudo systemctl enable heizung-monitor"
    echo ""
fi

# Sensor-Probleme
SENSORS=$(ls /sys/bus/w1/devices/28-* 2>/dev/null | wc -l)
if [ "$SENSORS" -eq 0 ]; then
    echo "   3. 1-Wire Sensoren aktivieren:"
    echo "      sudo modprobe w1-gpio w1-therm"
    echo "      # Falls das nicht hilft: sudo reboot"
    echo ""
fi

echo "🟡 KONFIGURATION - Prüfen und korrigieren:"

if [ ! -f ".env" ]; then
    echo "   4. InfluxDB-Konfiguration erstellen:"
    echo "      cp .env.example .env"
    echo "      nano .env  # Zugangsdaten prüfen"
    echo ""
fi

# Python Environment
if [ ! -d "venv" ]; then
    echo "   5. Python Virtual Environment reparieren:"
    echo "      python3 -m venv venv"
    echo "      source venv/bin/activate"
    echo "      pip install -r requirements.txt"
    echo ""
fi

echo "🟢 DIAGNOSE - Probleme identifizieren:"

echo "   6. Sensoren manuell testen:"
echo "      source venv/bin/activate"
echo "      python test_sensors.py"
echo "      python test_dht22_robust.py"
echo ""

echo "   7. InfluxDB Verbindung testen:"
echo "      curl http://localhost:8086/health"
echo "      # Sollte Status 'pass' zeigen"
echo ""

echo "   8. Service-Logs live überwachen:"
echo "      sudo journalctl -u heizung-monitor -f"
echo "      # Auf Fehler beim Datenschreiben achten"
echo ""

echo "   9. Manuelle Datenprüfung in InfluxDB:"
echo "      docker exec -it heizung-influxdb influx"
echo "      # Dann in InfluxDB CLI: SHOW BUCKETS"
echo ""

echo "🔧 REPARATUR - Häufige Lösungen:"

echo "   10. Kompletter Service-Neustart:"
echo "       sudo systemctl stop heizung-monitor"
echo "       docker-compose restart"
echo "       sleep 10"
echo "       sudo systemctl start heizung-monitor"
echo ""

echo "   11. Virtual Environment neu aufbauen:"
echo "       rm -rf venv"
echo "       python3 -m venv venv"
echo "       source venv/bin/activate"
echo "       pip install -r requirements.txt"
echo ""

echo "   12. InfluxDB Bucket neu erstellen:"
echo "       # In InfluxDB Web-UI (http://PI_IP:8086):"
echo "       # Buckets -> Create Bucket -> 'heizung-daten'"
echo ""

echo "🚨 NOTFALL - Bei anhaltenden Problemen:"

echo "   13. System komplett neu installieren:"
echo "       sudo systemctl stop heizung-monitor"
echo "       docker-compose down -v  # Löscht alle Daten!"
echo "       sudo ./install_rpi5.sh"
echo ""

echo "   14. 1-Wire Quick-Fix:"
echo "       chmod +x fix_1wire_sensors.sh"
echo "       ./fix_1wire_sensors.sh"
echo ""

echo "   15. DHT22 Quick-Fix:"
echo "       chmod +x fix_adafruit_dht.sh"
echo "       ./fix_adafruit_dht.sh"
echo ""

# Automatische Tests vorschlagen
echo "💡 AUTOMATISCHE PROBLEMBEHEBUNG:"
echo ""
echo "   Führe diese Befehle in der angegebenen Reihenfolge aus:"
echo ""
echo "   # 1. Grundsystem prüfen"
echo "   docker-compose ps"
echo "   sudo systemctl status heizung-monitor"
echo ""
echo "   # 2. Sensoren testen"
echo "   source venv/bin/activate && python test_sensors.py"
echo ""
echo "   # 3. Bei Problemen: Services neu starten"
echo "   sudo systemctl restart heizung-monitor"
echo "   docker-compose restart"
echo ""
echo "   # 4. Logs überwachen (in separatem Terminal)"
echo "   sudo journalctl -u heizung-monitor -f"

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
