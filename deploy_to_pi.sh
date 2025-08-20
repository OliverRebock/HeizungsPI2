#!/b# Konfiguration
PI_HOST="pi@192.168.178.78"
PI_PATH="/home/pi/heizung-monitor"
LOCAL_PATH="."ash
# Deployment-Skript für Windows zu Raspberry Pi 5
# Führe dieses Skript auf Windows (Git Bash/WSL) aus

# Konfiguration
PI_HOST="pi@192.168.1.100"  # ⚠️ ÄNDERE DIESE IP-ADRESSE ZU DEINER RASPBERRY PI IP!
PI_PATH="/home/pi/heizung-monitor"
LOCAL_PATH="."

echo "🚀 Deploying Heizungsüberwachung to Raspberry Pi 5"
echo "================================================="

# Farben für Output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Prüfe ob SSH-Verbindung funktioniert
echo -e "${YELLOW}Teste SSH-Verbindung zu $PI_HOST...${NC}"
if ! ssh -o ConnectTimeout=5 $PI_HOST "echo 'SSH-Verbindung erfolgreich'"; then
    echo -e "${RED}❌ SSH-Verbindung fehlgeschlagen!${NC}"
    echo ""
    echo "Mögliche Lösungen:"
    echo "1. IP-Adresse in diesem Skript anpassen (Zeile 5)"
    echo "2. SSH auf dem Pi aktivieren: sudo systemctl enable ssh"
    echo "3. SSH-Keys einrichten für passwortlose Anmeldung"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ SSH-Verbindung erfolgreich${NC}"

# Projekt-Ordner auf Pi erstellen
echo -e "${YELLOW}Erstelle Projekt-Ordner auf Pi...${NC}"
ssh $PI_HOST "mkdir -p $PI_PATH"

# Dateien übertragen (mit Ausschlüssen)
echo -e "${YELLOW}Übertrage Projekt-Dateien...${NC}"
rsync -avz --progress \
    --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='*.pyo' \
    --exclude='.env' \
    --exclude='venv' \
    --exclude='node_modules' \
    --exclude='.DS_Store' \
    --exclude='Thumbs.db' \
    $LOCAL_PATH/ $PI_HOST:$PI_PATH/

echo -e "${GREEN}✅ Upload abgeschlossen!${NC}"

# Installation auf Pi ausführen
echo ""
echo -e "${YELLOW}Führe Installation auf Pi aus...${NC}"
echo "Das kann einige Minuten dauern..."

ssh $PI_HOST "cd $PI_PATH && chmod +x install_rpi5.sh && sudo bash install_rpi5.sh"

echo ""
echo "============================================"
echo -e "${GREEN}🎉 Deployment erfolgreich abgeschlossen!${NC}"
echo "============================================"
echo ""

# Nächste Schritte anzeigen
echo -e "${YELLOW}📋 Nächste Schritte:${NC}"
echo ""
echo "1. 🔄 Raspberry Pi neu starten:"
echo "   ssh $PI_HOST 'sudo reboot'"
echo ""
echo "2. 🌡️ Nach dem Neustart - Sensoren prüfen:"
echo "   ssh $PI_HOST 'ls /sys/bus/w1/devices/28-*'"
echo ""
echo "3. 🗄️ InfluxDB konfigurieren:"
echo "   http://$(ssh $PI_HOST 'hostname -I | awk "{print \$1}"' 2>/dev/null):8086"
echo ""
echo "4. ⚙️ Konfiguration anpassen:"
echo "   ssh $PI_HOST"
echo "   cd $PI_PATH"
echo "   nano .env"
echo "   nano config/heating_circuits.yaml"
echo ""
echo "5. 🧪 Sensoren testen:"
echo "   ssh $PI_HOST 'cd $PI_PATH && source venv/bin/activate && python test_sensors.py'"
echo ""
echo "6. 🚀 Service starten:"
echo "   ssh $PI_HOST 'sudo systemctl start heizung-monitor'"
echo ""
echo "7. 📊 Grafana öffnen:"
echo "   http://$(ssh $PI_HOST 'hostname -I | awk "{print \$1}"' 2>/dev/null):3000"
echo ""
echo "8. 📝 Logs überwachen:"
echo "   ssh $PI_HOST 'sudo journalctl -u heizung-monitor -f'"
echo ""

# IP-Adresse des Pi anzeigen
PI_IP=$(ssh $PI_HOST 'hostname -I | awk "{print \$1}"' 2>/dev/null)
if [ ! -z "$PI_IP" ]; then
    echo -e "${GREEN}🌐 Raspberry Pi IP-Adresse: $PI_IP${NC}"
    echo ""
    echo "Bookmarks für deinen Browser:"
    echo "- InfluxDB: http://$PI_IP:8086"
    echo "- Grafana: http://$PI_IP:3000"
fi

echo ""
echo -e "${YELLOW}⚠️  Wichtig: Neustart erforderlich für 1-Wire Interface!${NC}"
