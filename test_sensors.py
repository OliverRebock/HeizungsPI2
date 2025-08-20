#!/usr/bin/env python3
"""
Test-Skript für alle Sensoren der Heizungsüberwachung
Überprüft DS18B20 und DHT22 Sensoren
"""

import sys
import time
import logging
from pathlib import Path

# Projekt-Root zum Python-Pfad hinzufügen
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

from src.sensors.heating_sensors import HeatingSystemManager
from src.sensors.dht22_sensor import HeatingRoomSensor

# Logging konfigurieren
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)

def test_1wire_interface():
    """Testet das 1-Wire Interface"""
    logger.info("🔍 Teste 1-Wire Interface...")
    
    try:
        import os
        devices = os.listdir('/sys/bus/w1/devices/')
        ds18b20_devices = [d for d in devices if d.startswith('28-')]
        
        logger.info(f"✅ 1-Wire Interface verfügbar")
        logger.info(f"📊 Gefundene DS18B20 Sensoren: {len(ds18b20_devices)}")
        
        for device in ds18b20_devices:
            logger.info(f"   - {device}")
        
        return len(ds18b20_devices) > 0
        
    except Exception as e:
        logger.error(f"❌ 1-Wire Interface-Fehler: {e}")
        return False

def test_heating_circuits():
    """Testet alle Heizungskreise"""
    logger.info("\n🏠 Teste Heizungskreise...")
    
    try:
        heating_manager = HeatingSystemManager()
        return heating_manager.test_all_circuits()
        
    except Exception as e:
        logger.error(f"❌ Heizungskreis-Test fehlgeschlagen: {e}")
        return False

def test_room_sensor():
    """Testet den DHT22 Raumsensor"""
    logger.info("\n🌡️ Teste DHT22 Raumsensor...")
    
    try:
        room_sensor = HeatingRoomSensor()
        success = room_sensor.test_sensor()
        
        if success:
            # Detaillierte Raumdaten anzeigen
            conditions = room_sensor.check_heating_room_conditions()
            logger.info("📊 Raumzustand:")
            logger.info(f"   Status: {conditions['status']}")
            logger.info(f"   Temperatur: {conditions['temperature']:.1f}°C")
            logger.info(f"   Luftfeuchtigkeit: {conditions['humidity']:.1f}%")
            logger.info(f"   Taupunkt: {conditions['dew_point']:.1f}°C")
            
            if conditions['alerts']:
                for alert in conditions['alerts']:
                    logger.warning(f"   ⚠️ {alert['type']}: {alert['message']}")
        
        room_sensor.cleanup()
        return success
        
    except Exception as e:
        logger.error(f"❌ DHT22-Test fehlgeschlagen: {e}")
        return False

def test_database_connection():
    """Testet die InfluxDB-Verbindung"""
    logger.info("\n📊 Teste InfluxDB-Verbindung...")
    
    try:
        from src.database.influxdb_client import HeatingInfluxDBClient
        
        influx_client = HeatingInfluxDBClient()
        
        # Test-Ping
        if influx_client.client.ping():
            logger.info("✅ InfluxDB-Verbindung erfolgreich")
            influx_client.close()
            return True
        else:
            logger.error("❌ InfluxDB nicht erreichbar")
            return False
            
    except Exception as e:
        logger.error(f"❌ InfluxDB-Test fehlgeschlagen: {e}")
        return False

def run_full_system_test():
    """Führt einen kompletten Systemtest durch"""
    logger.info("🧪 Starte vollständigen Systemtest...")
    logger.info("=" * 50)
    
    # Alle Tests durchführen
    tests = [
        ("1-Wire Interface", test_1wire_interface),
        ("Heizungskreise", test_heating_circuits), 
        ("DHT22 Raumsensor", test_room_sensor),
        ("InfluxDB-Verbindung", test_database_connection)
    ]
    
    results = {}
    
    for test_name, test_func in tests:
        try:
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
    try:
        # Umgebungsvariablen laden
        from dotenv import load_dotenv
        load_dotenv()
        
        # Vollständigen Systemtest ausführen
        success = run_full_system_test()
        
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
