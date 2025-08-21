#!/usr/bin/env python3
"""
Test-Skript für alle Sensoren der Heizungsüberwachung
Überprüft DS18B20 und DHT22 Sensoren mit erweiterten Diagnose-Funktionen
"""

import sys
import time
import logging
import subprocess
import argparse
import glob
import statistics
from pathlib import Path

# Projekt-Root zum Python-Pfad hinzufügen
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

# Logging konfigurieren
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

def test_1wire_interface():
    """Testet das 1-Wire Interface und alle DS18B20 Sensoren"""
    logger.info("🔍 Teste 1-Wire Interface...")
    
    try:
        # 1-Wire Interface prüfen
        devices = glob.glob('/sys/bus/w1/devices/28-*')
        if not devices:
            logger.error("❌ Keine 1-Wire Sensoren gefunden!")
            logger.info("💡 Prüfe /boot/firmware/config.txt: dtoverlay=w1-gpio")
            return False
            
        logger.info(f"✅ {len(devices)} DS18B20 Sensoren gefunden")
        
        # Alle Sensoren testen
        working_sensors = 0
        for device in devices:
            device_id = device.split('/')[-1]
            try:
                with open(f"{device}/w1_slave", 'r') as f:
                    data = f.read()
                    if "YES" in data and "t=" in data:
                        temp = int(data.split("t=")[1]) / 1000.0
                        logger.info(f"  📡 {device_id}: {temp:.1f}°C")
                        working_sensors += 1
                    else:
                        logger.warning(f"  ⚠️ {device_id}: Lesefehler")
            except Exception as e:
                logger.error(f"  ❌ {device_id}: {e}")
                
        logger.info(f"✅ {working_sensors}/{len(devices)} Sensoren funktionsfähig")
        return working_sensors > 0
        
    except Exception as e:
        logger.error(f"❌ 1-Wire Test fehlgeschlagen: {e}")
        return False

def test_room_sensor():
    """Testet den DHT22 Raumsensor (Basic-Version)"""
    logger.info("🌡️ Teste DHT22 Raumsensor...")
    
    try:
        import board
        import adafruit_dht
        
        # DHT22 am GPIO 18 initialisieren
        dht = adafruit_dht.DHT22(board.D18)
        
        # 3 Versuche für stabile Messung
        for attempt in range(3):
            try:
                temperature = dht.temperature
                humidity = dht.humidity
                
                if temperature is not None and humidity is not None:
                    logger.info(f"  🌡️ Temperatur: {temperature:.1f}°C")
                    logger.info(f"  💧 Luftfeuchtigkeit: {humidity:.1f}%")
                    dht.exit()
                    return True
                else:
                    logger.warning(f"  ⚠️ Versuch {attempt + 1}: Keine Daten")
                    
            except RuntimeError as e:
                logger.warning(f"  ⚠️ Versuch {attempt + 1}: {e}")
                time.sleep(2)
                
        dht.exit()
        logger.error("❌ DHT22 Sensor nicht lesbar")
        return False
        
    except Exception as e:
        logger.error(f"❌ DHT22 Test fehlgeschlagen: {e}")
        return False

def test_dht22_detailed():
    """Erweiterte DHT22-Tests mit Statistiken"""
    logger.info("🌡️ Detaillierte DHT22-Analyse...")
    
    try:
        import board
        import adafruit_dht
        
        dht = adafruit_dht.DHT22(board.D18)
        
        temperatures = []
        humidities = []
        successful_reads = 0
        total_attempts = 5
        
        logger.info(f"📊 Führe {total_attempts} Messungen durch...")
        
        for attempt in range(total_attempts):
            try:
                temperature = dht.temperature
                humidity = dht.humidity
                
                if temperature is not None and humidity is not None:
                    temperatures.append(temperature)
                    humidities.append(humidity)
                    successful_reads += 1
                    logger.info(f"  ✅ Messung {attempt + 1}: {temperature:.1f}°C, {humidity:.1f}%")
                else:
                    logger.warning(f"  ❌ Messung {attempt + 1}: Keine Daten")
                    
            except RuntimeError as e:
                logger.warning(f"  ❌ Messung {attempt + 1}: {e}")
                
            time.sleep(2)
        
        dht.exit()
        
        # Statistiken berechnen
        success_rate = (successful_reads / total_attempts) * 100
        logger.info(f"\n📈 DHT22 Statistiken:")
        logger.info(f"  📊 Erfolgsrate: {success_rate:.1f}% ({successful_reads}/{total_attempts})")
        
        if temperatures:
            temp_avg = statistics.mean(temperatures)
            temp_min = min(temperatures)
            temp_max = max(temperatures)
            logger.info(f"  🌡️ Temperatur: {temp_avg:.1f}°C (Min: {temp_min:.1f}°C, Max: {temp_max:.1f}°C)")
            
            # Plausibilitätsprüfung
            if -40 <= temp_avg <= 80:
                logger.info("  ✅ Temperatur plausibel")
            else:
                logger.warning("  ⚠️ Temperatur außerhalb des normalen Bereichs")
        
        if humidities:
            hum_avg = statistics.mean(humidities)
            hum_min = min(humidities)
            hum_max = max(humidities)
            logger.info(f"  💧 Luftfeuchtigkeit: {hum_avg:.1f}% (Min: {hum_min:.1f}%, Max: {hum_max:.1f}%)")
            
            # Plausibilitätsprüfung
            if 0 <= hum_avg <= 100:
                logger.info("  ✅ Luftfeuchtigkeit plausibel")
            else:
                logger.warning("  ⚠️ Luftfeuchtigkeit außerhalb des normalen Bereichs")
        
        # Stabilitätsprüfung
        if len(temperatures) > 1:
            temp_range = max(temperatures) - min(temperatures)
            if temp_range < 2.0:
                logger.info("  ✅ Temperatur-Messwerte stabil")
            else:
                logger.warning(f"  ⚠️ Temperatur-Schwankung: {temp_range:.1f}°C")
        
        return successful_reads > 0
        
    except Exception as e:
        logger.error(f"❌ DHT22 Detailtest fehlgeschlagen: {e}")
        return False

def run_dht22_only_test():
    """Führt spezifische DHT22-Tests durch"""
    logger.info("🎯 DHT22-spezifischer Test...")
    
    # Prüfe zuerst GPIO-Verfügbarkeit
    try:
        import board
        import digitalio
        
        # GPIO 18 testen
        pin = digitalio.DigitalInOut(board.D18)
        pin.direction = digitalio.Direction.INPUT
        pin.pull = digitalio.Pull.UP
        logger.info("✅ GPIO 18 verfügbar")
        pin.deinit()
        
    except Exception as e:
        logger.error(f"❌ GPIO 18 Test fehlgeschlagen: {e}")
        return False
    
    # Versuche zuerst das dedizierte Test-Script
    try:
        logger.info("🔧 Versuche dediziertes DHT22-Test-Script...")
        result = subprocess.run([sys.executable, "test_dht22.py"], 
                              capture_output=True, text=True, timeout=60)
        
        if result.returncode == 0:
            logger.info("✅ Dediziertes DHT22-Test erfolgreich")
            # Output anzeigen
            for line in result.stdout.split('\n'):
                if line.strip():
                    logger.info(f"  {line}")
            return True
        else:
            logger.warning("⚠️ Dediziertes DHT22-Test fehlgeschlagen, versuche Basic-Test...")
            return test_dht22_detailed()
            
    except (subprocess.TimeoutExpired, FileNotFoundError):
        logger.warning("⚠️ Spezifisches DHT22-Test-Script nicht gefunden")
        return test_dht22_detailed()
            
    except Exception as e:
        logger.error(f"❌ DHT22-Test Fehler: {e}")
        return test_dht22_detailed()

def test_heating_circuits():
    """Testet die konfigurierten Heizungskreise"""
    logger.info("🏠 Teste Heizungskreise...")
    
    try:
        # Konfiguration laden
        config_file = Path("config/heating_circuits.yaml")
        if not config_file.exists():
            logger.warning("⚠️ Keine Heizkreis-Konfiguration gefunden")
            return test_1wire_interface()  # Fallback auf 1-Wire Test
        
        import yaml
        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)
        
        circuits = config.get('heating_circuits', {})
        if not circuits:
            logger.warning("⚠️ Keine Heizkreise konfiguriert")
            return False
        
        logger.info(f"📋 Teste {len(circuits)} Heizungskreise...")
        
        working_circuits = 0
        for circuit_name, circuit_config in circuits.items():
            logger.info(f"\n🔍 Teste Heizkreis: {circuit_name}")
            
            # Vorlauf-Sensor testen
            vorlauf_id = circuit_config.get('vorlauf_sensor')
            ruecklauf_id = circuit_config.get('ruecklauf_sensor')
            
            vorlauf_temp = None
            ruecklauf_temp = None
            
            if vorlauf_id:
                try:
                    with open(f"/sys/bus/w1/devices/{vorlauf_id}/w1_slave", 'r') as f:
                        data = f.read()
                        if "YES" in data and "t=" in data:
                            vorlauf_temp = int(data.split("t=")[1]) / 1000.0
                            logger.info(f"  🔥 Vorlauf: {vorlauf_temp:.1f}°C")
                except Exception as e:
                    logger.error(f"  ❌ Vorlauf-Sensor: {e}")
            
            if ruecklauf_id:
                try:
                    with open(f"/sys/bus/w1/devices/{ruecklauf_id}/w1_slave", 'r') as f:
                        data = f.read()
                        if "YES" in data and "t=" in data:
                            ruecklauf_temp = int(data.split("t=")[1]) / 1000.0
                            logger.info(f"  🔄 Rücklauf: {ruecklauf_temp:.1f}°C")
                except Exception as e:
                    logger.error(f"  ❌ Rücklauf-Sensor: {e}")
            
            # Temperaturdifferenz berechnen
            if vorlauf_temp and ruecklauf_temp:
                diff = vorlauf_temp - ruecklauf_temp
                logger.info(f"  📊 Temperaturdifferenz: {diff:.1f}°C")
                
                if diff > 0:
                    logger.info(f"  ✅ Heizkreis {circuit_name} funktional")
                    working_circuits += 1
                else:
                    logger.warning(f"  ⚠️ Heizkreis {circuit_name}: Keine Wärmeabgabe")
            else:
                logger.error(f"  ❌ Heizkreis {circuit_name}: Sensordaten unvollständig")
        
        logger.info(f"\n📈 Ergebnis: {working_circuits}/{len(circuits)} Heizkreise funktional")
        return working_circuits > 0
        
    except Exception as e:
        logger.error(f"❌ Heizkreis-Test fehlgeschlagen: {e}")
        return False

def test_influxdb_connection():
    """Testet die InfluxDB-Verbindung"""
    logger.info("📊 Teste InfluxDB-Verbindung...")
    
    try:
        import os
        import requests
        
        # InfluxDB-Parameter aus Umgebungsvariablen
        influxdb_url = os.getenv('INFLUXDB_URL', 'http://localhost:8086')
        influxdb_token = os.getenv('INFLUXDB_TOKEN', 'heizung-monitoring-token-2024')
        influxdb_org = os.getenv('INFLUXDB_ORG', 'heizung-monitoring')
        influxdb_bucket = os.getenv('INFLUXDB_BUCKET', 'heizung-daten')
        
        # Health-Check
        response = requests.get(f"{influxdb_url}/health", timeout=10)
        if response.status_code == 200:
            logger.info("✅ InfluxDB Server erreichbar")
        else:
            logger.error(f"❌ InfluxDB Health-Check fehlgeschlagen: {response.status_code}")
            return False
        
        # Ping-Test mit Token
        headers = {'Authorization': f'Token {influxdb_token}'}
        response = requests.get(f"{influxdb_url}/ping", headers=headers, timeout=10)
        if response.status_code == 204:
            logger.info("✅ InfluxDB Authentifizierung erfolgreich")
        else:
            logger.error(f"❌ InfluxDB Authentifizierung fehlgeschlagen: {response.status_code}")
            return False
        
        # Bucket-Test
        response = requests.get(f"{influxdb_url}/api/v2/buckets", headers=headers, timeout=10)
        if response.status_code == 200:
            buckets = response.json().get('buckets', [])
            bucket_names = [b['name'] for b in buckets]
            logger.info(f"✅ Verfügbare Buckets: {bucket_names}")
            
            if influxdb_bucket in bucket_names:
                logger.info(f"✅ Ziel-Bucket '{influxdb_bucket}' gefunden")
            else:
                logger.warning(f"⚠️ Ziel-Bucket '{influxdb_bucket}' nicht gefunden")
        else:
            logger.error(f"❌ Bucket-Abfrage fehlgeschlagen: {response.status_code}")
            return False
        
        logger.info("✅ InfluxDB-Verbindung erfolgreich")
        return True
        
    except Exception as e:
        logger.error(f"❌ InfluxDB-Test fehlgeschlagen: {e}")
        return False

def run_all_tests():
    """Führt alle Sensor-Tests durch"""
    tests = [
        ("1-Wire Sensoren", test_1wire_interface),
        ("DHT22 Raumsensor", test_dht22_detailed),
        ("Heizungskreise", test_heating_circuits),
        ("InfluxDB Verbindung", test_influxdb_connection)
    ]
    
    results = {}
    
    for test_name, test_func in tests:
        try:
            logger.info("\n" + "=" * 50)
            results[test_name] = test_func()
            time.sleep(2)  # Pause zwischen Tests
        except Exception as e:
            logger.error(f"❌ Test '{test_name}' abgebrochen: {e}")
            results[test_name] = False
    
    # Ergebnisse zusammenfassen
    logger.info("\n" + "=" * 50)
    logger.info("📋 TEST-ZUSAMMENFASSUNG:")
    logger.info("=" * 50)
    
    all_passed = True
    for test_name, result in results.items():
        status = "✅ BESTANDEN" if result else "❌ FEHLGESCHLAGEN"
        logger.info(f"{test_name:20} : {status}")
        if not result:
            all_passed = False
    
    logger.info("=" * 50)
    
    if all_passed:
        logger.info("🎉 ALLE TESTS BESTANDEN - System bereit!")
        return True
    else:
        logger.error("⚠️ EINIGE TESTS FEHLGESCHLAGEN - Prüfe Konfiguration!")
        return False

def main():
    """Hauptfunktion"""
    parser = argparse.ArgumentParser(description='Test-Skript für Heizungsüberwachung Sensoren')
    parser.add_argument('--dht22', action='store_true', 
                       help='Führe nur DHT22-Test durch')
    parser.add_argument('--1wire', action='store_true', 
                       help='Führe nur 1-Wire-Test durch')
    parser.add_argument('--heating', action='store_true', 
                       help='Führe nur Heizungskreis-Test durch')
    parser.add_argument('--influxdb', action='store_true', 
                       help='Führe nur InfluxDB-Test durch')
    parser.add_argument('--all', action='store_true', 
                       help='Führe alle Tests durch (Standard)')
    
    args = parser.parse_args()
    
    try:
        # .env-Datei laden falls vorhanden
        try:
            from dotenv import load_dotenv
            load_dotenv()
        except ImportError:
            pass  # dotenv ist optional
        
        success = True
        
        # Spezifische Tests ausführen
        if args.dht22:
            logger.info("🌡️ Führe nur DHT22-Test durch...")
            success = run_dht22_only_test()
        elif getattr(args, '1wire', False):  # Workaround für 1wire Argument
            logger.info("🔍 Führe nur 1-Wire-Test durch...")
            success = test_1wire_interface()
        elif args.heating:
            logger.info("🏠 Führe nur Heizungskreis-Test durch...")
            success = test_heating_circuits()
        elif args.influxdb:
            logger.info("📊 Führe nur InfluxDB-Test durch...")
            success = test_influxdb_connection()
        else:
            # Vollständigen Systemtest ausführen (Standard)
            logger.info("🚀 Starte vollständigen Systemtest...")
            success = run_all_tests()
        
        # Hilfreiche Ausgabe am Ende
        if success:
            logger.info("\n🎉 Test erfolgreich abgeschlossen!")
        else:
            logger.error("\n❌ Test fehlgeschlagen!")
            logger.info("💡 Für detaillierte DHT22-Diagnose: python test_dht22.py")
            logger.info("💡 Für vollständige System-Diagnose: ./diagnose_influxdb.sh")
        
        # Exit-Code setzen
        sys.exit(0 if success else 1)
        
    except KeyboardInterrupt:
        logger.info("Test durch Benutzer abgebrochen")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unerwarteter Fehler: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
