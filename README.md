# Heizungsüberwachung mit Raspberry Pi 5

Ein spezialisiertes Python-System zur Überwachung von Heizungsanlagen mit DS18B20 Temperatursensoren für Vor- und Rückläufe, DHT22 Umgebungssensor, InfluxDB-Datenbank und Grafana-Dashboards - optimiert für Raspberry Pi 5.

## 🏠 Projekt-Übersicht

Dieses System überwacht kontinuierlich:
- **6x DS18B20 Sensoren** für 3 Heizkreise (Obergeschoss, Erdgeschoss, Keller)
- **2x DS18B20 Sensoren** für Wärmepumpe (Vor-/Rücklauf am Erzeuger)
- **1x DHT22 Sensor** für Raumtemperatur und Luftfeuchtigkeit
- **Wärmepumpen-Effizienz-Berechnungen** (COP-Werte, Leistungsaufnahme)
- **Heizkreis-Effizienz-Berechnungen** (Temperaturdifferenzen, Wärmeverluste)
- **Echtzeit-Visualisierung** in Grafana

## 🔧 Hardware-Anforderungen

### Komponenten
- **Raspberry Pi 5** (empfohlen, optimiert für) oder Pi 3/4
- 8x DS18B20 Temperatursensoren (wasserdicht für Rohrmontage)
- 1x DHT22 Temperatur-/Luftfeuchtigkeitssensor
- 4.7kΩ Pull-up Widerstand (1-Wire Bus)
- 10kΩ Pull-up Widerstand (DHT22, optional)
- Klemmleisten oder Schraubterminals
- Isoliertes Gehäuse (IP65 empfohlen)
- **SD-Karte** (min. 32GB, Class 10) für Raspberry Pi 5

### Verdrahtung

#### DS18B20 Sensoren (1-Wire Bus)
```
Sensor 1-6: 3 Heizkreise (je Vor-/Rücklauf)
Sensor 7-8: Wärmepumpe Vor-/Rücklauf
├── VDD (rot):    3.3V (Pin 1)
├── GND (schwarz): GND (Pin 6) 
└── Data (gelb):   GPIO 4 (Pin 7) + 4.7kΩ Pull-up zu 3.3V
```

#### DHT22 Raumsensor
```
├── VCC: 3.3V (Pin 17)
├── GND: GND (Pin 20)
└── Data: GPIO 18 (Pin 12)
```

**DHT22 Sensor testen:**
```bash
# Vollständiger DHT22-Test mit Diagnose (empfohlen)
python test_dht22_robust.py

# Original DHT22-Test 
python test_dht22.py

# DHT22-Test über allgemeines Test-Script
python test_sensors.py --dht22

# DHT22 im Systemtest
python test_sensors.py
```

**DHT22 Troubleshooting:**
```bash
# Häufiger Fehler: "No module named 'board'"
# Lösung 1 - Virtual Environment verwenden:
source venv/bin/activate
pip install adafruit-circuitpython-dht adafruit-blinka

# Lösung 2 - System-weite Installation:
sudo pip3 install adafruit-circuitpython-dht adafruit-blinka

# Lösung 3 - APT Installation:
sudo apt install python3-adafruit-circuitpython-dht

# GPIO Berechtigungen:
sudo usermod -a -G gpio pi
# Neuanmeldung erforderlich

# Häufiger Fehler: "Could not detect if running on the Raspberry Pi"
# bei Adafruit-DHT Installation (Legacy-Bibliothek)
# Quick-Fix:
chmod +x fix_adafruit_dht.sh
./fix_adafruit_dht.sh

# Alternative: Legacy DHT Library mit Force-Flag
pip install Adafruit-DHT --install-option="--force-pi"

# Hinweis: System funktioniert auch ohne Legacy Adafruit-DHT
# Moderne CircuitPython-Bibliotheken sind ausreichend
```

### Sensor-Zuordnung (Heizungskreise)
- **DS18B20_1**: Vorlauf Heizkreis Obergeschoss
- **DS18B20_2**: Rücklauf Heizkreis Obergeschoss
- **DS18B20_3**: Vorlauf Heizkreis Erdgeschoss
- **DS18B20_4**: Rücklauf Heizkreis Erdgeschoss
- **DS18B20_5**: Vorlauf Heizkreis Keller
- **DS18B20_6**: Rücklauf Heizkreis Keller
- **DS18B20_7**: Vorlauf Wärmepumpe (Haupterzeuger)
- **DS18B20_8**: Rücklauf Wärmepumpe (Haupterzeuger)
- **DHT22**: Raumtemperatur Heizungsraum

## 🖥️ Installation auf Raspberry Pi 5

### 🚀 Einfachste Installation (Ein-Befehl)

**Führe diesen einen Befehl direkt auf deinem Raspberry Pi aus:**

```bash
curl -fsSL https://raw.githubusercontent.com/OliverRebock/HeizungsPI2/main/quick_install.sh | sudo bash
```

Das war's! Der Rest passiert automatisch. Nach der Installation:
```bash
sudo reboot
```

### 📦 Standard GitHub-Installation

1. **Projekt von GitHub klonen und installieren:**
   ```bash
   # Direkt auf dem Raspberry Pi ausführen:
   cd /home/pi
   git clone https://github.com/OliverRebock/HeizungsPI2.git heizung-monitor
   cd heizung-monitor
   chmod +x install_rpi5.sh
   sudo bash install_rpi5.sh
   ```

2. **System neu starten:**
   ```bash
   sudo reboot
   ```

### 🖥️ Remote-Installation von Windows

Wenn du das System von deinem Windows-PC aus installieren möchtest:

```bash
# Im Git Bash oder PowerShell:
git clone https://github.com/OliverRebock/HeizungsPI2.git
cd HeizungsPI2
./deploy_to_pi.sh
```

### ⚡ Was passiert bei der automatischen Installation?

✅ **System wird aktualisiert** (apt update & upgrade)  
✅ **Git und Python werden installiert**  
✅ **Projekt wird von GitHub geklont**  
✅ **1-Wire Interface wird aktiviert** (GPIO 4)  
✅ **Docker und Docker Compose werden installiert**  
✅ **InfluxDB 2.x wird als Docker Container gestartet**  
✅ **Grafana wird als Docker Container gestartet**  
✅ **Python Virtual Environment wird erstellt**  
✅ **Alle Dependencies werden installiert** (requirements.txt)  
✅ **Systemd Service wird eingerichtet**  
✅ **Berechtigungen werden korrekt gesetzt**  
✅ **Grafana-Datasource wird automatisch konfiguriert**  

### 🐳 Docker Container Management

Nach der Installation laufen InfluxDB und Grafana als Docker Container:

```bash
# Container-Status prüfen
docker-compose ps

# Container-Logs anzeigen
docker-compose logs influxdb
docker-compose logs grafana

# Container neu starten
docker-compose restart

# Container stoppen
docker-compose down

# Container mit neuen Images aktualisieren
docker-compose pull
docker-compose up -d
```

### 📊 Standard-Zugangsdaten

**InfluxDB:** http://PI_IP_ADRESSE:8086
- **Benutzername:** admin
- **Passwort:** heizung123!
- **Organisation:** heizung-monitoring
- **Bucket:** heizung-daten
- **Token:** heizung-monitoring-token-2024

**Grafana:** http://PI_IP_ADRESSE:3000
- **Benutzername:** admin
- **Passwort:** heizung123!
- **Datasource:** Bereits konfiguriert ✅  

### Manuelle Installation (Schritt für Schritt)

#### 1. System vorbereiten
```bash
# System aktualisieren
sudo apt update && sudo apt upgrade -y

# Grundpakete installieren
sudo apt install -y python3 python3-pip python3-venv git curl wget
```

#### 2. 1-Wire Interface aktivieren
```bash
# 1-Wire in Boot-Konfiguration aktivieren (Raspberry Pi 5)
echo "dtoverlay=w1-gpio,gpiopin=4" | sudo tee -a /boot/firmware/config.txt

# Module automatisch laden
echo "w1-gpio" | sudo tee -a /etc/modules
echo "w1-therm" | sudo tee -a /etc/modules

# Neustart erforderlich
sudo reboot
```

#### 3. 1-Wire Sensoren testen
```bash
# Nach dem Neustart - Sensoren prüfen
ls /sys/bus/w1/devices/28-*

# Sensor-Daten lesen
cat /sys/bus/w1/devices/28-*/w1_slave
```

#### 4. Docker und Container installieren
```bash
# Docker installieren
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker pi

# Docker Compose installieren
sudo apt install -y docker-compose-plugin

# Docker Service starten
sudo systemctl enable docker
sudo systemctl start docker

# InfluxDB und Grafana Container starten
cd /home/pi/heizung-monitor
docker-compose up -d

# Container-Status prüfen
docker-compose ps
```

#### 5. Konfiguration
```bash
# Umgebungsvariablen konfigurieren
cp .env.example .env
nano .env

# Standard-Konfiguration ist bereits gesetzt:
# INFLUXDB_URL=http://localhost:8086
# INFLUXDB_TOKEN=heizung-monitoring-token-2024
# INFLUXDB_ORG=heizung-monitoring
# INFLUXDB_BUCKET=heizung-daten

# Sensor-IDs ermitteln und eintragen
ls /sys/bus/w1/devices/28-*
nano config/heating_circuits.yaml
```

#### 6. Systemd Service einrichten
```bash
# Service-Datei erstellen
sudo nano /etc/systemd/system/heizung-monitor.service
```

Inhalt der Service-Datei:
```ini
[Unit]
Description=Heizungsüberwachung mit Raspberry Pi 5
After=network.target influxdb.service
Wants=influxdb.service

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi/heizung-monitor
Environment=PATH=/home/pi/heizung-monitor/venv/bin
ExecStart=/home/pi/heizung-monitor/venv/bin/python main.py
Restart=always
RestartSec=10

StandardOutput=journal
StandardError=journal
SyslogIdentifier=heizung-monitor

[Install]
WantedBy=multi-user.target
```

```bash
# Service aktivieren
sudo systemctl daemon-reload
sudo systemctl enable heizung-monitor
```

## 🔄 System aktualisieren

### Update von GitHub

```bash
cd /home/pi/heizung-monitor
git pull origin main
sudo systemctl restart heizung-monitor
```

### Vollständige Neuinstallation

```bash
# Altes System stoppen
sudo systemctl stop heizung-monitor

# Neu installieren
curl -fsSL https://raw.githubusercontent.com/OliverRebock/HeizungsPI2/main/quick_install.sh | sudo bash

# System neu starten
sudo reboot
```

## 🚀 Raspberry Pi 5 Optimierungen

### Performance-Vorteile
- **4x Cortex-A76 CPU** mit 2.4 GHz für schnellere Datenverarbeitung
- **Erweiterte GPIO-Performance** für stabilere Sensor-Kommunikation
- **Verbesserte Docker-Performance** für InfluxDB und Grafana Container
- **Optimierte 1-Wire Unterstützung** mit reduzierten Latenzen

### Pi 5-spezifische Konfiguration
```bash
# GPU-Memory für headless Betrieb optimieren
echo "gpu_mem=16" | sudo tee -a /boot/firmware/config.txt

# USB-Power für stabile Sensor-Versorgung
echo "max_usb_current=1" | sudo tee -a /boot/firmware/config.txt

# Übertaktung für bessere Performance (optional)
echo "arm_freq=2600" | sudo tee -a /boot/firmware/config.txt
echo "over_voltage=2" | sudo tee -a /boot/firmware/config.txt
```

### Monitoring-Optimierungen
- **Parallel Sensor-Reading**: Gleichzeitiges Auslesen aller DS18B20 Sensoren
- **Optimierte Polling-Intervalle**: 30 Sekunden für beste Balance zwischen Aktualität und Performance
- **Intelligentes Caching**: Reduzierte InfluxDB-Writes durch Batch-Processing
- **Docker Memory Limits**: Optimierte Container-Ressourcen für Pi 5

## 🚀 System starten

#### Sensoren testen
```bash
cd /home/pi/heizung-monitor

# WICHTIG: Virtual Environment aktivieren
source venv/bin/activate

# Alle Sensoren testen
python test_sensors.py

# Spezifische Tests
python test_sensors.py --dht22    # Nur DHT22 Raumsensor
python test_sensors.py --1wire    # Nur DS18B20 Sensoren
python test_sensors.py --heating  # Nur Heizungskreise
python test_sensors.py --influxdb # Nur InfluxDB

# Detaillierte DHT22-Diagnose
python test_dht22.py

# Virtual Environment deaktivieren (optional)
deactivate
```

#### Service starten
```bash
sudo systemctl start heizung-monitor

# Status prüfen
sudo systemctl status heizung-monitor

# Logs anzeigen
sudo journalctl -u heizung-monitor -f
```

#### Grafana konfigurieren
1. **Web-Interface öffnen:** http://PI_IP_ADRESSE:3000
2. **Login:** admin/admin (Passwort ändern)
3. **InfluxDB Datenquelle hinzufügen:**
   - URL: http://localhost:8086
   - Organisation: heizung-monitoring
   - Token: [dein InfluxDB Token]
   - Bucket: heizung-daten

### 📊 Monitoring

#### Wichtige URLs
- **InfluxDB:** http://PI_IP_ADRESSE:8086
- **Grafana:** http://PI_IP_ADRESSE:3000
- **System-Status:** `sudo systemctl status heizung-monitor`

#### Log-Dateien
```bash
# Service-Logs
sudo journalctl -u heizung-monitor -f

# System-Logs
tail -f /var/log/heizung-monitor.log

# InfluxDB-Logs
sudo journalctl -u influxdb -f
```

## 📊 Grafana Dashboards

Das System erstellt automatisch Dashboards für:

### 1. Heizungsübersicht
- Aktuelle Temperaturen aller Kreise
- Vor-/Rücklauf-Differenzen
- Systemeffizienz
- Alarme bei Anomalien

### 2. Heizkreis-Details
- Temperaturverläufe
- Effizienz-Trends
- Wärmeverlust-Analyse
- Betriebszeiten

### 3. Umgebungsbedingungen
- Raumtemperatur/Luftfeuchtigkeit
- Außentemperatur-Einfluss
- Heizlast-Prognosen

## 📁 Projektstruktur

```
heizung-monitor/
├── src/
│   ├── sensors/
│   │   ├── ds18b20_manager.py      # DS18B20 Sensor-Management
│   │   ├── dht22_sensor.py         # DHT22 Raumsensor
│   │   └── heating_sensors.py      # Heizungslogik
│   ├── database/
│   │   ├── influxdb_client.py      # InfluxDB Integration
│   │   └── data_models.py          # Datenstrukturen
│   ├── analysis/
│   │   ├── efficiency_calc.py      # Effizienz-Berechnungen
│   │   ├── anomaly_detection.py    # Anomalie-Erkennung
│   │   └── trends.py               # Trend-Analyse
│   ├── grafana/
│   │   ├── dashboard_manager.py    # Dashboard-Automatisierung
│   │   └── templates/              # Dashboard-Vorlagen
│   └── utils/
│       ├── config.py               # Konfiguration
│       ├── alerts.py               # Alarm-System
│       └── logger.py               # Logging
├── config/
│   ├── heating_circuits.yaml       # Heizkreis-Konfiguration
│   └── grafana_dashboards.json     # Dashboard-Definitionen
├── scripts/
│   ├── install.sh                  # Installation
│   ├── backup.sh                   # Backup-Skript
│   └── maintenance.py              # Wartung
├── systemd/
│   └── heizung-monitor.service     # Systemd Service
├── main.py                         # Hauptprogramm
├── test_sensors.py                 # Sensor-Tests
├── test_dht22.py                   # DHT22 Sensor-Diagnose
├── requirements.txt                # Python-Dependencies
├── .env.example                    # Umgebungsvariablen
└── README.md
```

## 🔍 Überwachung & Wartung

### Wichtige Metriken
- **Temperatur-Differenzen**: Vorlauf - Rücklauf pro Kreis
- **Effizienz**: Wärmeabgabe vs. Energieeinsatz
- **Laufzeiten**: Brenner-/Pumpen-Betriebsstunden
- **Anomalien**: Ungewöhnliche Temperaturverläufe

### Alarm-Bedingungen
- Temperaturdifferenz < 5°C (schlechte Wärmeabgabe)
- Vorlauftemperatur > 80°C (Überhitzung)
- Sensor-Ausfälle
- Lange Brennerlaufzeiten ohne Temperaturanstieg

### Wartungsintervalle
- **Täglich**: Automatische Sensor-Checks
- **Wöchentlich**: Effizienz-Reports
- **Monatlich**: Kalibrierung und Reinigung
- **Jährlich**: Hardware-Prüfung

## 🆘 Troubleshooting

### DS18B20 Sensoren nicht erkannt
```bash
# 1-Wire Geräte prüfen
ls -la /sys/bus/w1/devices/
cat /sys/bus/w1/devices/28-*/w1_slave

# Module neu laden
sudo modprobe -r w1-therm w1-gpio
sudo modprobe w1-gpio w1-therm
```

### DHT22 Messfehler
```bash
# GPIO-Status prüfen
gpio readall

# Sensor-Test isoliert
python3 -c "from src.sensors.dht22_sensor import DHT22Sensor; s=DHT22Sensor(); print(s.read_data())"
```

### InfluxDB Verbindungsprobleme
```bash
# Container-Status prüfen
docker-compose ps
docker-compose logs influxdb

# Container neu starten
docker-compose restart influxdb

# Verbindung testen
curl -v http://localhost:8086/health

# Container direkt zugreifen
docker exec -it heizung-influxdb /bin/bash
```

### Grafana Dashboard fehlen
```bash
# Container-Status prüfen
docker-compose logs grafana

# Container neu starten
docker-compose restart grafana

# Grafana-Konfiguration neu laden
docker-compose restart grafana
```

### Docker Container Probleme
```bash
# Alle Container neu starten
docker-compose down
docker-compose up -d

# Container-Images aktualisieren
docker-compose pull
docker-compose up -d

# Logs aller Container anzeigen
docker-compose logs -f

# Volumes prüfen
docker volume ls
```

## � Troubleshooting

### Docker Compose Kompatibilität

⚠️ **Häufiger Fehler:** `docker-compose: command not found`

Das System unterstützt automatisch beide Docker Compose Varianten:
- **Legacy:** `docker-compose` (v1.x)
- **Modern:** `docker compose` (v2.x Plugin)

**Automatische Lösung:**
```bash
# Das Installationsskript erkennt automatisch die verfügbare Version
./install_rpi5.sh
```

**Manuelle Prüfung:**
```bash
# Verfügbare Versionen testen:
docker-compose version  # Legacy Version
docker compose version  # Plugin Version

# Plugin installieren falls nötig:
sudo apt install docker-compose-plugin
```

**Skript-Updates:** Alle Scripts (`install_rpi5.sh`, `docker-manage.sh`, `service_manager.sh`) verwenden automatisch die verfügbare Variante.

### Weitere häufige Probleme

**Git-Merge-Konflikt bei Installation:**
```bash
# Fehler: "Your local changes would be overwritten by merge"
# Lösung 1 - Quick-Fix (empfohlen):
cd /home/pi/heizung-monitor
sudo ./quick_fix.sh
sudo ./install_rpi5.sh

# Lösung 2 - Komplette Neuinstallation:
curl -fsSL https://raw.githubusercontent.com/OliverRebock/HeizungsPI2/main/fresh_install.sh | sudo bash
sudo ./install_rpi5.sh

# Lösung 3 - Manuell:
cd /home/pi/heizung-monitor
sudo git stash
sudo git pull origin main
sudo chmod +x *.sh
sudo ./install_rpi5.sh
```

**Git Ownership Fehler:**
```bash
# Fehler: "fatal: detected dubious ownership in repository"
# Lösung:
cd /home/pi/heizung-monitor
sudo ./git_ownership_fix.sh

# Oder manuell:
sudo chown -R pi:pi /home/pi/heizung-monitor
sudo -u pi git config --global --add safe.directory /home/pi/heizung-monitor
```

**System-Update (wenn bereits installiert):**
```bash
# Für Updates ohne Neuinstallation:
sudo ./update_system.sh
```

**1-Wire Sensoren nicht erkannt:**
```bash
# Interface prüfen
ls /sys/bus/w1/devices/
# Sollte 28-xxxxxxxxxxxx Verzeichnisse zeigen

# Neustart erforderlich nach config.txt Änderung
sudo reboot
```

**Keine Daten in InfluxDB:**
```bash
# Vollständige Diagnose ausführen
cd /home/pi/heizung-monitor
chmod +x diagnose_influxdb.sh
./diagnose_influxdb.sh

# Services prüfen und starten
sudo systemctl status heizung-monitor
sudo systemctl start heizung-monitor

# Container prüfen
docker-compose ps
docker-compose up -d

# Logs überwachen
sudo journalctl -u heizung-monitor -f

# Sensoren manuell testen
python test_sensors.py
```

**InfluxDB Verbindungsprobleme:**
```bash
# Container-Status prüfen
docker-compose ps
docker-compose logs influxdb

# InfluxDB Gesundheitscheck
curl http://localhost:8086/health

# Container neu starten
docker-compose restart influxdb

# Konfiguration prüfen
cat .env
```

**Permission Denied Fehler:**
```bash
# Benutzer zur docker Gruppe hinzufügen
sudo usermod -aG docker $USER
# Neuanmeldung erforderlich
```

**Service-Status prüfen:**
```bash
# Alle Services prüfen
./service_manager.sh status

# Logs überwachen
./service_manager.sh logs
```

**Python Virtual Environment Fehler:**
```bash
# Fehler: "externally-managed-environment" beim pip install
# Ursache: Moderne Python-Installationen verhindern System-weite Package-Installation

# Lösung - Virtual Environment verwenden:
cd /home/pi/heizung-monitor

# Virtual Environment erstellen (falls nicht vorhanden)
python3 -m venv venv

# Virtual Environment aktivieren
source venv/bin/activate

# Dependencies installieren
pip install -r requirements.txt

# Für zukünftige Sessions immer zuerst aktivieren:
source venv/bin/activate
python test_sensors.py

# Virtual Environment deaktivieren:
deactivate
```

**Alternative: Komplette Neuinstallation (empfohlen):**
```bash
# Das Installationsskript erstellt automatisch das Virtual Environment
curl -fsSL https://raw.githubusercontent.com/OliverRebock/HeizungsPI2/main/quick_install.sh | sudo bash
```

## �📄 Lizenz

MIT License - Siehe LICENSE Datei für Details.
