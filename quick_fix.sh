#!/bin/bash

# Quick-Fix für Git-Konflikte bei der Installation
# Löst das "Your local changes would be overwritten by merge" Problem

echo "🔧 Git-Konflikt Quick-Fix"
echo "========================="

# Prüfen ob als root ausgeführt
if [[ $EUID -ne 0 ]]; then
    echo "❌ Dieses Script muss als root ausgeführt werden!"
    echo "Verwendung: sudo $0"
    exit 1
fi

# Zum Projekt-Verzeichnis wechseln
if [ ! -d "/home/pi/heizung-monitor" ]; then
    echo "❌ Projekt-Verzeichnis nicht gefunden: /home/pi/heizung-monitor"
    echo "Führe zuerst die Erstinstallation aus!"
    exit 1
fi

cd /home/pi/heizung-monitor

echo "📋 Sichere lokale Änderungen..."
# Konfigurationsdateien sichern
if [ -f ".env" ]; then
    cp .env .env.backup
    echo "✅ .env gesichert"
fi

if [ -f "config/heating_circuits.yaml" ]; then
    cp config/heating_circuits.yaml config/heating_circuits.yaml.backup
    echo "✅ heating_circuits.yaml gesichert"
fi

echo "🔄 Löse Git-Konflikt..."

# Git-Berechtigungen korrigieren
chown -R pi:pi /home/pi/heizung-monitor/.git
chmod -R 755 /home/pi/heizung-monitor/.git

# Als pi-User git-Operationen ausführen
sudo -u pi git stash  # Sichere lokale Änderungen
sudo -u pi git fetch origin
sudo -u pi git reset --hard origin/main  # Harte Zurücksetzung
sudo -u pi git clean -fd  # Entferne unverfolgte Dateien

echo "📁 Stelle Konfigurationen wieder her..."
if [ -f ".env.backup" ]; then
    cp .env.backup .env
    chown pi:pi .env
    echo "✅ .env wiederhergestellt"
fi

if [ -f "config/heating_circuits.yaml.backup" ]; then
    cp config/heating_circuits.yaml.backup config/heating_circuits.yaml
    chown pi:pi config/heating_circuits.yaml
    echo "✅ heating_circuits.yaml wiederhergestellt"
fi

echo "🔧 Mache Scripts ausführbar..."
# Alle .sh Dateien ausführbar machen
find . -name "*.sh" -type f -exec chmod +x {} \;
chown -R pi:pi /home/pi/heizung-monitor

# Spezielle Script-Berechtigungen
[ -f "scripts/backup.sh" ] && chmod +x scripts/backup.sh

echo "🧹 Räume temporäre Dateien auf..."
rm -f .env.backup config/heating_circuits.yaml.backup
rm -f get-docker.sh 2>/dev/null || true  # Docker-Installationsskript entfernen falls vorhanden

echo ""
echo "✅ Git-Konflikt erfolgreich gelöst!"
echo ""
echo "📋 Nächste Schritte:"
echo "1. Installation fortsetzen: sudo ./install_rpi5.sh"
echo "2. Oder System-Update: sudo ./update_system.sh"
echo ""
