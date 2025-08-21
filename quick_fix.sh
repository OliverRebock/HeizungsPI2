#!/bin/bash

# Quick-Fix für Git-Konflikte bei der Installation
# Löst das "Your local changes would be overwritten by merge" Problem

echo "🔧 Git-Konflikt Quick-Fix"
echo "========================="

cd /home/pi/heizung-monitor

echo "Sichere lokale Änderungen..."
[ -f ".env" ] && cp .env .env.backup
[ -f "config/heating_circuits.yaml" ] && cp config/heating_circuits.yaml config/heating_circuits.yaml.backup

echo "Löse Git-Konflikt..."
git stash  # Sichere lokale Änderungen
git pull origin main  # Update vom Repository

echo "Stelle Konfigurationen wieder her..."
[ -f ".env.backup" ] && cp .env.backup .env
[ -f "config/heating_circuits.yaml.backup" ] && cp config/heating_circuits.yaml.backup config/heating_circuits.yaml

echo "Mache Scripts ausführbar..."
chmod +x *.sh
[ -f "scripts/backup.sh" ] && chmod +x scripts/backup.sh

echo "✅ Git-Konflikt gelöst!"
echo ""
echo "Führe jetzt die Installation fort:"
echo "sudo ./install_rpi5.sh"
