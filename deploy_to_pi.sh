#!/bin/bash
# GitHub-basiertes Deployment für Heizungsüberwachung auf Raspberry Pi
# Das Projekt wird direkt von GitHub geklont

# Konfiguration
PI_IP="192.168.178.78"
PI_USER="pi"
GITHUB_REPO="https://github.com/OliverRebock/HeizungsPI2.git"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

echo "🚀 Heizungsüberwachung - GitHub-basiertes Deployment"
echo "=================================================="

log "Ziel-Raspberry Pi: $PI_IP"
log "GitHub Repository: $GITHUB_REPO"

# Methode 1: SSH-Befehl für direkte GitHub-Installation
log "Methode 1: SSH + GitHub Clone"
echo "Führe folgenden Befehl auf dem Pi aus:"
echo ""
echo -e "${BLUE}ssh $PI_USER@$PI_IP${NC}"
echo -e "${BLUE}curl -fsSL https://raw.githubusercontent.com/OliverRebock/HeizungsPI2/main/quick_install.sh | sudo bash${NC}"
echo ""

# Methode 2: SSH-Direktverbindung (falls SSH verfügbar)
if command -v ssh &> /dev/null; then
    read -p "Soll die Installation automatisch über SSH gestartet werden? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Starte SSH-Verbindung und Installation..."
        
        ssh "$PI_USER@$PI_IP" << 'ENDSSH'
            echo "🔧 Starte GitHub-basierte Installation auf Raspberry Pi..."
            curl -fsSL https://raw.githubusercontent.com/OliverRebock/HeizungsPI2/main/quick_install.sh | sudo bash
ENDSSH
        
        if [ $? -eq 0 ]; then
            log "✅ Installation erfolgreich abgeschlossen!"
            echo ""
            echo -e "${GREEN}System wurde installiert. Nächste Schritte:${NC}"
            echo "1. Pi neu starten: ssh $PI_USER@$PI_IP 'sudo reboot'"
            echo "2. InfluxDB konfigurieren: http://$PI_IP:8086"
            echo "3. Grafana öffnen: http://$PI_IP:3000"
        else
            error "Installation fehlgeschlagen"
        fi
    fi
else
    warn "SSH nicht verfügbar. Verwende manuelle Installation."
fi

# Methode 3: Manuelle Anweisungen
echo ""
echo -e "${BLUE}=== MANUELLE INSTALLATION ===${NC}"
echo "Falls SSH nicht funktioniert, führe direkt auf dem Pi aus:"
echo ""
echo "cd /home/pi"
echo "git clone $GITHUB_REPO heizung-monitor"
echo "cd heizung-monitor"
echo "chmod +x install_rpi5.sh"
echo "sudo bash install_rpi5.sh"
echo "sudo reboot"
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
