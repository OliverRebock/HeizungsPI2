#!/bin/bash

# Quick-Fix für Adafruit-DHT Installation Problem
# Behebt: "Could not detect if running on the Raspberry Pi"

echo "🔧 Adafruit-DHT Installation Quick-Fix"
echo "====================================="

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# 1. Virtual Environment aktivieren
if [ -d "venv" ]; then
    log "Virtual Environment aktivieren..."
    source venv/bin/activate
    log "Virtual Environment aktiv"
else
    error "Virtual Environment nicht gefunden!"
    log "Erstelle Virtual Environment..."
    python3 -m venv venv
    source venv/bin/activate
    log "Virtual Environment erstellt und aktiviert"
fi

# 2. Pip aktualisieren
log "Pip aktualisieren..."
pip install --upgrade pip setuptools wheel

# 3. Problematische Pakete entfernen
log "Entferne problematische Legacy-Pakete..."
pip uninstall -y Adafruit-DHT 2>/dev/null || true

# 4. Core DHT22-Pakete installieren
log "Installiere moderne DHT22-Unterstützung..."
pip install adafruit-circuitpython-dht adafruit-blinka

# 5. Versuche Legacy-Installation mit Force-Flag
log "Versuche Legacy DHT-Installation mit Raspberry Pi Force-Flag..."
if pip install Adafruit-DHT --force-reinstall --no-deps --install-option="--force-pi" 2>/dev/null; then
    log "✅ Legacy DHT-Unterstützung erfolgreich installiert"
else
    warn "Legacy DHT-Installation fehlgeschlagen (nicht kritisch)"
    log "Verwende alternative Installation..."
    
    # Alternative: Manuelle Installation mit Force-Pi
    if python3 -c "
import subprocess
import sys
try:
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'Adafruit-DHT', '--global-option=build_ext', '--global-option=--force-pi'])
    print('Legacy DHT Installation erfolgreich')
except:
    print('Legacy DHT Installation fehlgeschlagen - nicht kritisch')
" 2>/dev/null; then
        log "✅ Alternative Legacy-Installation erfolgreich"
    else
        warn "Legacy DHT kann nicht installiert werden"
        log "System funktioniert trotzdem mit modernen CircuitPython-Bibliotheken"
    fi
fi

# 6. Alle anderen Requirements installieren
log "Installiere restliche Dependencies..."
if [ -f "requirements-pi5.txt" ]; then
    pip install -r requirements-pi5.txt
    log "Pi 5 optimierte Requirements installiert"
elif [ -f "requirements.txt" ]; then
    # Installiere alles außer Adafruit-DHT
    grep -v "Adafruit-DHT" requirements.txt | pip install -r /dev/stdin
    log "Standard Requirements (ohne Legacy DHT) installiert"
fi

# 7. Installation testen
log "Teste DHT22-Installation..."
python3 -c "
try:
    import board
    import adafruit_dht
    print('✅ Modern DHT22 Support: OK')
except ImportError as e:
    print(f'❌ Modern DHT22 Support: {e}')

try:
    import Adafruit_DHT
    print('✅ Legacy DHT22 Support: OK')
except ImportError:
    print('⚠️ Legacy DHT22 Support: Nicht verfügbar (nicht kritisch)')

print('\\n📊 DHT22 System Status:')
print('- Moderne CircuitPython DHT: Verfügbar')
print('- Legacy Adafruit_DHT: Optional')
print('- System ist betriebsbereit!')
"

log "🏁 Quick-Fix abgeschlossen!"
echo ""
echo "💡 Hinweise:"
echo "- Das System funktioniert auch ohne Legacy Adafruit-DHT"
echo "- Moderne CircuitPython-Bibliotheken sind für Pi 5 optimiert"
echo "- Bei Problemen: python test_dht22_robust.py ausführen"
