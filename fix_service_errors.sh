#!/bin/bash

# Heizungsüberwachung Service Error Fix Script
# Speziell für systemd Service Fehler (exit code 1)

echo "🔧 Heizungsüberwachung Service Error Fix"
echo "========================================"
echo ""

# Farben für bessere Lesbarkeit
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Schritt 1: Service stoppen
print_status "Stoppe heizung-monitor Service..."
sudo systemctl stop heizung-monitor
sleep 2

# Schritt 2: Detaillierte Fehleranalyse
print_status "Analysiere Service-Fehler..."
echo ""
echo "=== AKTUELLE SERVICE LOGS ==="
sudo journalctl -u heizung-monitor --no-pager -n 20
echo ""

# Schritt 3: Python-Umgebung prüfen
print_status "Prüfe Python Virtual Environment..."
cd /home/pi/heizung-monitor

if [ ! -d "venv" ]; then
    print_warning "Virtual Environment nicht gefunden. Erstelle neues..."
    python3 -m venv venv
    print_success "Virtual Environment erstellt"
fi

# Virtual Environment aktivieren
source venv/bin/activate

# Schritt 4: Dependencies prüfen und reparieren
print_status "Prüfe und repariere Python-Dependencies..."
pip install --upgrade pip

# Installiere alle Requirements neu
if [ -f "requirements.txt" ]; then
    print_status "Installiere requirements.txt..."
    pip install -r requirements.txt
else
    print_warning "requirements.txt nicht gefunden. Installiere Basis-Pakete..."
    pip install influxdb-client pyyaml adafruit-circuitpython-dht adafruit-blinka
fi

# Raspberry Pi 5 spezifische Pakete
if [ -f "requirements-pi5.txt" ]; then
    print_status "Installiere Raspberry Pi 5 spezifische Pakete..."
    pip install -r requirements-pi5.txt
fi

# Schritt 5: Python-Syntax prüfen
print_status "Prüfe Python-Syntax..."
if python3 -m py_compile main.py; then
    print_success "main.py Syntax OK"
else
    print_error "main.py hat Syntax-Fehler!"
    python3 -m py_compile main.py
    echo ""
fi

# Schritt 6: Konfigurationsdateien prüfen
print_status "Prüfe Konfigurationsdateien..."

# .env Datei prüfen
if [ ! -f ".env" ]; then
    print_warning ".env Datei fehlt. Erstelle Standard-Konfiguration..."
    cat > .env << EOF
# InfluxDB Konfiguration
INFLUXDB_URL=http://localhost:8086
INFLUXDB_TOKEN=heizung-monitoring-token-2024
INFLUXDB_ORG=heizung-monitoring
INFLUXDB_BUCKET=heizung-daten

# Sensor Konfiguration
SENSOR_INTERVAL=30
DHT22_PIN=18
W1_THERMAL_PATH=/sys/bus/w1/devices

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/heizung-monitor.log
EOF
    print_success ".env Datei erstellt"
else
    print_success ".env Datei gefunden"
fi

# heating_circuits.yaml prüfen
if [ ! -f "config/heating_circuits.yaml" ]; then
    print_warning "Heizkreis-Konfiguration fehlt. Kopiere Beispiel..."
    mkdir -p config
    if [ -f "config/heating_circuits_example.yaml" ]; then
        cp config/heating_circuits_example.yaml config/heating_circuits.yaml
        print_success "Heizkreis-Konfiguration erstellt"
    else
        print_error "Beispiel-Konfiguration nicht gefunden!"
    fi
else
    print_success "Heizkreis-Konfiguration gefunden"
fi

# Schritt 7: 1-Wire Interface prüfen
print_status "Prüfe 1-Wire Interface..."
if [ -d "/sys/bus/w1/devices" ]; then
    SENSOR_COUNT=$(ls /sys/bus/w1/devices/28-* 2>/dev/null | wc -l)
    if [ $SENSOR_COUNT -gt 0 ]; then
        print_success "$SENSOR_COUNT DS18B20 Sensoren gefunden"
    else
        print_warning "Keine DS18B20 Sensoren gefunden"
        print_status "Prüfe 1-Wire Konfiguration..."
        
        # Boot-Konfiguration prüfen
        if grep -q "dtoverlay=w1-gpio" /boot/firmware/config.txt; then
            print_success "1-Wire Interface konfiguriert"
        else
            print_warning "1-Wire Interface nicht konfiguriert. Füge hinzu..."
            echo "dtoverlay=w1-gpio,gpiopin=4" | sudo tee -a /boot/firmware/config.txt
            print_warning "Neustart erforderlich für 1-Wire Interface!"
        fi
    fi
else
    print_error "1-Wire Interface nicht verfügbar!"
fi

# Schritt 8: Berechtigungen korrigieren
print_status "Korrigiere Dateiberechtigungen..."
sudo chown -R pi:pi /home/pi/heizung-monitor
chmod +x *.sh
print_success "Berechtigungen korrigiert"

# Schritt 9: Service-Datei prüfen
print_status "Prüfe systemd Service-Datei..."
SERVICE_FILE="/etc/systemd/system/heizung-monitor.service"

if [ ! -f "$SERVICE_FILE" ]; then
    print_warning "Service-Datei fehlt. Erstelle neue..."
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Heizungsüberwachung mit Raspberry Pi 5
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi/heizung-monitor
Environment=PATH=/home/pi/heizung-monitor/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStartPre=/bin/sleep 10
ExecStart=/home/pi/heizung-monitor/venv/bin/python main.py
Restart=always
RestartSec=30
StartLimitInterval=0

StandardOutput=journal
StandardError=journal
SyslogIdentifier=heizung-monitor

# Umgebungsvariablen
EnvironmentFile=/home/pi/heizung-monitor/.env

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    print_success "Service-Datei erstellt"
else
    print_success "Service-Datei gefunden"
fi

# Schritt 10: Docker Container prüfen
print_status "Prüfe Docker Container..."
cd /home/pi/heizung-monitor

# Docker Compose Version automatisch erkennen
if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
    print_status "Verwende Legacy docker-compose"
elif docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
    print_status "Verwende Docker Compose Plugin"
else
    print_error "Docker Compose nicht gefunden!"
    exit 1
fi

# Container Status prüfen
if $DOCKER_COMPOSE_CMD ps | grep -q "Up"; then
    print_success "Docker Container laufen"
else
    print_warning "Docker Container nicht aktiv. Starte..."
    $DOCKER_COMPOSE_CMD up -d
    sleep 5
    
    if $DOCKER_COMPOSE_CMD ps | grep -q "Up"; then
        print_success "Docker Container gestartet"
    else
        print_error "Docker Container konnten nicht gestartet werden!"
        $DOCKER_COMPOSE_CMD logs
    fi
fi

# Schritt 11: InfluxDB Verbindung testen
print_status "Teste InfluxDB Verbindung..."
sleep 5

if curl -s http://localhost:8086/health >/dev/null; then
    print_success "InfluxDB erreichbar"
    
    # Test-Daten schreiben
    print_status "Teste Datenbank-Schreibvorgang..."
    source venv/bin/activate
    
    python3 -c "
import sys
sys.path.append('/home/pi/heizung-monitor')
try:
    from src.database.influxdb_client import InfluxDBClient
    import time
    
    client = InfluxDBClient()
    
    # Test-Datenpunkt
    data = {
        'measurement': 'test_connection',
        'tags': {'location': 'service_fix'},
        'fields': {'temperature': 20.5, 'status': 'ok'},
        'time': time.time_ns()
    }
    
    result = client.write_data('heizung-daten', [data])
    if result:
        print('✅ Test-Daten erfolgreich geschrieben')
    else:
        print('❌ Fehler beim Schreiben von Test-Daten')
        
except Exception as e:
    print(f'❌ InfluxDB Test fehlgeschlagen: {e}')
"
else
    print_error "InfluxDB nicht erreichbar!"
    print_status "Starte InfluxDB Container neu..."
    $DOCKER_COMPOSE_CMD restart influxdb
    sleep 10
fi

# Schritt 12: Manuelle Sensor-Tests
print_status "Führe Sensor-Tests durch..."
source venv/bin/activate

echo ""
echo "=== SENSOR TEST RESULTS ==="
python3 test_sensors.py 2>&1 | head -20
echo ""

# Schritt 13: Service neu starten
print_status "Starte heizung-monitor Service..."
sudo systemctl daemon-reload
sudo systemctl enable heizung-monitor
sudo systemctl start heizung-monitor

# Warte kurz und prüfe Status
sleep 5

if sudo systemctl is-active --quiet heizung-monitor; then
    print_success "Service erfolgreich gestartet!"
    
    echo ""
    echo "=== SERVICE STATUS ==="
    sudo systemctl status heizung-monitor --no-pager -l
    
else
    print_error "Service konnte nicht gestartet werden!"
    echo ""
    echo "=== FEHLER-LOGS ==="
    sudo journalctl -u heizung-monitor --no-pager -n 10
fi

echo ""
echo "=== ZUSAMMENFASSUNG ==="
print_status "Service Status: $(sudo systemctl is-active heizung-monitor)"
print_status "Docker Container: $($DOCKER_COMPOSE_CMD ps --services | wc -l) definiert"
print_status "InfluxDB: $(curl -s http://localhost:8086/health >/dev/null && echo 'Erreichbar' || echo 'Nicht erreichbar')"

# Schritt 14: Live-Monitoring Empfehlung
echo ""
print_status "Für Live-Monitoring verwende:"
echo "  sudo journalctl -u heizung-monitor -f"
echo ""
print_status "Für Container-Logs verwende:"
echo "  $DOCKER_COMPOSE_CMD logs -f"
echo ""
print_status "Für Sensor-Test verwende:"
echo "  cd /home/pi/heizung-monitor && source venv/bin/activate && python test_sensors.py"

echo ""
print_success "Service Error Fix abgeschlossen!"
