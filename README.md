# Heizungsüberwachung mit Raspberry Pi

Ein spezialisiertes Python-System zur Überwachung von Heizungsanlagen mit DS18B20 Temperatursensoren für Vor- und Rückläufe, DHT22 Umgebungssensor, InfluxDB-Datenbank und Grafana-Dashboards.

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
- Raspberry Pi 3/4 (empfohlen)
- 8x DS18B20 Temperatursensoren (wasserdicht für Rohrmontage)
- 1x DHT22 Temperatur-/Luftfeuchtigkeitssensor
- 4.7kΩ Pull-up Widerstand (1-Wire Bus)
- 10kΩ Pull-up Widerstand (DHT22, optional)
- Klemmleisten oder Schraubterminals
- Isoliertes Gehäuse (IP65 empfohlen)

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

### Automatische Installation

1. **Projekt auf Raspberry Pi übertragen:**
   ```bash
   # Von deinem Windows-PC aus:
   scp -r HeizungsPI2/ pi@DEINE_PI_IP:/home/pi/heizung-monitor
   
   # Oder mit USB-Stick/SD-Karte übertragen
   ```

2. **Auf dem Raspberry Pi ausführen:**
   ```bash
   cd /home/pi/heizung-monitor
   chmod +x install_rpi5.sh
   sudo bash install_rpi5.sh
   ```

3. **System neu starten:**
   ```bash
   sudo reboot
   ```

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

#### 4. InfluxDB 2.x installieren
```bash
# Alte Repository-Einträge entfernen (falls vorhanden)
sudo rm -f /etc/apt/sources.list.d/influxdb.list
sudo rm -f /usr/share/keyrings/influxdb-archive-keyring.gpg

# Neuen GPG-Schlüssel korrekt importieren
wget -q https://repos.influxdata.com/influxdata-archive_compat.key
echo '393e8779c89ac8d958f81f942f9ad7fb82a25e133faddaf92e15b16e6ac9ce4c' influxdata-archive_compat.key | sha256sum -c && cat influxdata-archive_compat.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg > /dev/null

# Repository hinzufügen
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdb.list

# InfluxDB installieren
sudo apt update && sudo apt install -y influxdb2

# Service starten
sudo systemctl enable influxdb
sudo systemctl start influxdb

# Web-Setup: http://PI_IP_ADRESSE:8086
```

#### 5. Grafana installieren
```bash
# Repository hinzufügen
curl -s https://packages.grafana.com/gpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/grafana.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

# Grafana installieren
sudo apt update && sudo apt install -y grafana

# Service starten
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

# Web-Interface: http://PI_IP_ADRESSE:3000
# Standard-Login: admin/admin
```

#### 6. Python-Projekt einrichten
```bash
# Projekt-Verzeichnis
cd /home/pi/heizung-monitor

# Virtuelle Umgebung erstellen
python3 -m venv venv
source venv/bin/activate

# Python-Abhängigkeiten installieren
pip install --upgrade pip
pip install -r requirements.txt
```

#### 7. Konfiguration
```bash
# Umgebungsvariablen konfigurieren
cp .env.example .env
nano .env

# InfluxDB-Verbindungsdaten eintragen:
# INFLUXDB_URL=http://localhost:8086
# INFLUXDB_TOKEN=dein-token-hier
# INFLUXDB_ORG=heizung-monitoring
# INFLUXDB_BUCKET=heizung-daten

# Sensor-IDs ermitteln und eintragen
ls /sys/bus/w1/devices/28-*
nano config/heating_circuits.yaml
```

#### 8. Systemd Service einrichten
```bash
# Service-Datei erstellen
sudo nano /etc/systemd/system/heizung-monitor.service
```

Inhalt der Service-Datei:
```ini
[Unit]
Description=Heizungsüberwachung mit Raspberry Pi
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

### 🚀 System starten

#### Sensoren testen
```bash
cd /home/pi/heizung-monitor
source venv/bin/activate
python test_sensors.py
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
# Service-Status
sudo systemctl status influxdb

# Logs prüfen
sudo journalctl -u influxdb -f

# Verbindung testen
curl -v http://localhost:8086/health
```

### Grafana Dashboard fehlen
```bash
# Dashboard-Import
python3 scripts/import_dashboards.py

# Grafana neu starten
sudo systemctl restart grafana-server
```

## 📄 Lizenz

MIT License - Siehe LICENSE Datei für Details.
