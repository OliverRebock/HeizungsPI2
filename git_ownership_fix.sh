#!/bin/bash

# Git Ownership Fix für Raspberry Pi Heizungsüberwachung
# Behebt "fatal: detected dubious ownership in repository" Fehler

echo "🔧 Git Ownership Fix"
echo "===================="

# Prüfen ob als root ausgeführt
if [[ $EUID -ne 0 ]]; then
    echo "❌ Dieses Script muss als root ausgeführt werden!"
    echo "Verwendung: sudo $0"
    exit 1
fi

PROJECT_DIR="/home/pi/heizung-monitor"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Projekt-Verzeichnis nicht gefunden: $PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"

echo "🔧 Korrigiere Git Repository-Berechtigungen..."

# Repository-Berechtigungen korrigieren
chown -R pi:pi "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR/.git"

# Git safe.directory Konfiguration
echo "🛡️ Füge Repository zur Git safe.directory Liste hinzu..."
sudo -u pi git config --global --add safe.directory "$PROJECT_DIR"

# Test ob Git jetzt funktioniert
echo "✅ Teste Git-Funktionalität..."
if sudo -u pi git status &>/dev/null; then
    echo "✅ Git Repository erfolgreich repariert!"
    echo ""
    echo "📋 Git-Status:"
    sudo -u pi git status --short
else
    echo "❌ Git-Problem weiterhin vorhanden"
    exit 1
fi

echo ""
echo "🎯 Repository ist jetzt einsatzbereit!"
echo "Verwende: sudo ./install_rpi5.sh"
