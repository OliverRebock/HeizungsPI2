#!/bin/bash

# Quick-Fix für 1-Wire DS18B20 Sensor Probleme
# Heizungsüberwachung Raspberry Pi

echo "🔧 1-Wire Sensor Quick-Fix"
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

# 1. Module neu laden
echo ""
info "1. 1-Wire Module neu laden..."
if sudo modprobe -r w1-therm w1-gpio 2>/dev/null; then
    log "Module entladen: w1-therm, w1-gpio"
else
    warn "Module konnten nicht entladen werden (eventuell nicht geladen)"
fi

sleep 2

if sudo modprobe w1-gpio && sudo modprobe w1-therm; then
    log "Module geladen: w1-gpio, w1-therm"
else
    error "Module konnten nicht geladen werden!"
    exit 1
fi

sleep 3

# 2. Interface prüfen
echo ""
info "2. 1-Wire Interface prüfen..."
if [ -d "/sys/bus/w1/devices" ]; then
    log "1-Wire Interface verfügbar"
    
    # Master prüfen
    if [ -d "/sys/bus/w1/devices/w1_bus_master1" ]; then
        log "1-Wire Master aktiv"
    else
        error "1-Wire Master nicht gefunden!"
        echo "   Prüfe /boot/firmware/config.txt für: dtoverlay=w1-gpio,gpiopin=4"
    fi
else
    error "1-Wire Interface nicht verfügbar!"
    echo "   1-Wire nicht in Kernel aktiviert"
    exit 1
fi

# 3. Sensoren scannen
echo ""
info "3. Sensoren scannen..."
SENSOR_COUNT=$(ls -1 /sys/bus/w1/devices/28-* 2>/dev/null | wc -l)

if [ "$SENSOR_COUNT" -gt 0 ]; then
    log "$SENSOR_COUNT DS18B20 Sensoren gefunden"
    
    # Jeden Sensor 3x testen
    for sensor_dir in /sys/bus/w1/devices/28-*; do
        if [ -d "$sensor_dir" ]; then
            SENSOR_ID=$(basename "$sensor_dir")
            echo ""
            info "Teste Sensor: $SENSOR_ID"
            
            SUCCESS=false
            for attempt in {1..3}; do
                echo -n "   Versuch $attempt/3: "
                
                if [ -f "$sensor_dir/w1_slave" ]; then
                    # Sensor lesen
                    DATA=$(cat "$sensor_dir/w1_slave" 2>/dev/null)
                    
                    if [ -n "$DATA" ]; then
                        # CRC prüfen
                        CRC_LINE=$(echo "$DATA" | head -1)
                        if echo "$CRC_LINE" | grep -q "YES"; then
                            # Temperatur extrahieren
                            TEMP_LINE=$(echo "$DATA" | grep "t=" | tail -1)
                            if [ -n "$TEMP_LINE" ]; then
                                TEMP=$(echo "$TEMP_LINE" | sed 's/.*t=//')
                                if [ -n "$TEMP" ] && [ "$TEMP" != "85000" ]; then
                                    # Temperatur berechnen (mit awk statt bc)
                                    TEMP_C=$(awk "BEGIN {printf \"%.1f\", $TEMP/1000}")
                                    echo -e "${GREEN}${TEMP_C}°C${NC}"
                                    SUCCESS=true
                                    break
                                else
                                    echo -e "${YELLOW}85.0°C (nicht initialisiert)${NC}"
                                fi
                            else
                                echo -e "${RED}Keine Temperatur${NC}"
                            fi
                        else
                            echo -e "${RED}CRC Fehler${NC}"
                        fi
                    else
                        echo -e "${RED}Keine Daten${NC}"
                    fi
                else
                    echo -e "${RED}w1_slave fehlt${NC}"
                fi
                
                # Kurz warten zwischen Versuchen
                if [ $attempt -lt 3 ]; then
                    sleep 2
                fi
            done
            
            if [ "$SUCCESS" = true ]; then
                log "✅ Sensor $SENSOR_ID funktioniert"
            else
                error "❌ Sensor $SENSOR_ID defekt oder Verkabelung prüfen"
            fi
        fi
    done
else
    error "Keine DS18B20 Sensoren gefunden!"
    echo ""
    echo "Mögliche Ursachen:"
    echo "📌 1-Wire nicht aktiviert:"
    echo "   sudo nano /boot/firmware/config.txt"
    echo "   # Zeile hinzufügen: dtoverlay=w1-gpio,gpiopin=4"
    echo "   sudo reboot"
    echo ""
    echo "📌 Verkabelung prüfen:"
    echo "   VDD (rot)    -> 3.3V (Pin 1)"
    echo "   GND (schwarz)-> GND (Pin 6)"
    echo "   Data (gelb)  -> GPIO 4 (Pin 7)"
    echo "   Pull-up      -> 4.7kΩ zwischen Data und VDD"
    echo ""
    echo "📌 GPIO-Status prüfen:"
    echo "   gpio readall"
    exit 1
fi

# 4. Systemd Service neu starten
echo ""
info "4. Heizungsservice neu starten..."
if sudo systemctl is-active --quiet heizung-monitor; then
    if sudo systemctl restart heizung-monitor; then
        log "Service erfolgreich neu gestartet"
        
        # Kurz warten und Status prüfen
        sleep 3
        if sudo systemctl is-active --quiet heizung-monitor; then
            log "Service läuft korrekt"
        else
            warn "Service läuft nicht - Logs prüfen:"
            echo "   sudo journalctl -u heizung-monitor -n 20"
        fi
    else
        error "Service konnte nicht neu gestartet werden"
    fi
else
    warn "Service war nicht aktiv - starte neu"
    sudo systemctl start heizung-monitor
fi

# 5. Quick-Test mit Python
echo ""
info "5. Python-Test ausführen..."
cd /home/pi/heizung-monitor 2>/dev/null || cd .

if [ -f "test_1wire_debug.py" ]; then
    echo "Führe detaillierte Diagnose aus..."
    python3 test_1wire_debug.py
else
    warn "test_1wire_debug.py nicht gefunden - verwende Standard-Test"
    if [ -f "test_sensors.py" ]; then
        # Virtual Environment prüfen und verwenden
        if [ -d "venv" ]; then
            source venv/bin/activate
            python test_sensors.py --1wire
            deactivate
        else
            python3 test_sensors.py --1wire
        fi
    fi
fi

echo ""
log "🏁 Quick-Fix abgeschlossen!"
echo ""
echo "📋 Nächste Schritte bei anhaltenden Problemen:"
echo "   1. Verkabelung physisch prüfen"
echo "   2. Pull-up Widerstand messen (4.7kΩ)"
echo "   3. Andere GPIO-Pins testen"
echo "   4. Logs analysieren: sudo journalctl -u heizung-monitor -f"
echo "   5. Vollständige Diagnose: ./diagnose_influxdb.sh"
