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

from def main():
    """Hauptfunktion"""
    import argparse
    
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
        from dotenv import load_dotenv
        load_dotenv()
        
        success = True
        
        # Spezifische Tests ausführen
        if args.dht22:
            logger.info("🌡️ Führe nur DHT22-Test durch...")
            success = run_dht22_only_test()
        elif args.__dict__.get('1wire'):  # Workaround für 1wire Argument
            logger.info("🔍 Führe nur 1-Wire-Test durch...")
            success = test_1wire_interface()
        elif args.heating:
            logger.info("🏠 Führe nur Heizungskreis-Test durch...")
            success = test_heating_circuits()
        elif args.influxdb:
            logger.info("📊 Führe nur InfluxDB-Test durch...")
            success = test_database_connection()
        else:
            # Vollständigen Systemtest ausführen (Standard)
            success = run_full_system_test()
        
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
        sys.exit(1)_sensors import HeatingSystemManager
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
    """Testet den DHT22 Raumsensor ausführlich"""
    logger.info("\n🌡️ Teste DHT22 Raumsensor (GPIO 18)...")
    
    try:
        room_sensor = HeatingRoomSensor()
        
        # 1. Grundfunktionstest
        logger.info("📋 DHT22 Grundfunktionstest:")
        success_count = 0
        total_attempts = 5
        temperatures = []
        humidities = []
        
        for i in range(total_attempts):
            logger.info(f"   Messversuch {i+1}...")
            success = room_sensor.test_sensor()
            
            if success:
                conditions = room_sensor.check_heating_room_conditions()
                temp = conditions['temperature']
                hum = conditions['humidity']
                
                if temp is not None and hum is not None:
                    logger.info(f"   ✅ Temperatur: {temp:.1f}°C, Luftfeuchtigkeit: {hum:.1f}%")
                    temperatures.append(temp)
                    humidities.append(hum)
                    success_count += 1
                else:
                    logger.warning(f"   ⚠️ Leere Daten erhalten")
            else:
                logger.warning(f"   ⚠️ Sensor-Test fehlgeschlagen")
            
            time.sleep(3)  # DHT22 benötigt Pause zwischen Messungen
        
        # 2. Statistiken berechnen
        if temperatures and humidities:
            avg_temp = sum(temperatures) / len(temperatures)
            avg_hum = sum(humidities) / len(humidities)
            min_temp, max_temp = min(temperatures), max(temperatures)
            min_hum, max_hum = min(humidities), max(humidities)
            
            logger.info(f"📊 DHT22 Statistiken:")
            logger.info(f"   📈 Erfolgsrate: {success_count}/{total_attempts} ({success_count/total_attempts*100:.1f}%)")
            logger.info(f"   🌡️ Temperatur - Mittel: {avg_temp:.1f}°C, Bereich: {min_temp:.1f}°C - {max_temp:.1f}°C")
            logger.info(f"   💧 Luftfeuchtigkeit - Mittel: {avg_hum:.1f}%, Bereich: {min_hum:.1f}% - {max_hum:.1f}%")
            
            # 3. Plausibilitätsprüfung
            logger.info("🔍 DHT22 Plausibilitätsprüfung:")
            temp_plausible = -20 <= avg_temp <= 60  # Typischer Bereich für Heizungsraum
            hum_plausible = 10 <= avg_hum <= 90     # Typischer Luftfeuchtigkeitsbereich
            
            if temp_plausible:
                logger.info(f"   ✅ Temperaturwerte plausibel ({avg_temp:.1f}°C)")
            else:
                logger.warning(f"   ⚠️ Temperaturwerte unplausibel ({avg_temp:.1f}°C)")
            
            if hum_plausible:
                logger.info(f"   ✅ Luftfeuchtigkeitswerte plausibel ({avg_hum:.1f}%)")
            else:
                logger.warning(f"   ⚠️ Luftfeuchtigkeitswerte unplausibel ({avg_hum:.1f}%)")
            
            # 4. Stabilität prüfen
            if len(temperatures) > 1:
                temp_variation = max_temp - min_temp
                hum_variation = max_hum - min_hum
                
                temp_stable = temp_variation < 5.0  # Temperatur sollte relativ stabil sein
                hum_stable = hum_variation < 20.0   # Luftfeuchtigkeit kann mehr schwanken
                
                logger.info("📊 DHT22 Stabilität:")
                logger.info(f"   🌡️ Temperatur-Schwankung: {temp_variation:.1f}°C {'✅' if temp_stable else '⚠️'}")
                logger.info(f"   💧 Luftfeuchtigkeits-Schwankung: {hum_variation:.1f}% {'✅' if hum_stable else '⚠️'}")
            
            # 5. Detaillierte Raumdaten anzeigen (bei Erfolg)
            if success_count > 0:
                conditions = room_sensor.check_heating_room_conditions()
                logger.info("📊 Heizungsraum-Zustand:")
                logger.info(f"   Status: {conditions['status']}")
                logger.info(f"   Taupunkt: {conditions['dew_point']:.1f}°C")
                
                if conditions['alerts']:
                    for alert in conditions['alerts']:
                        logger.warning(f"   ⚠️ {alert['type']}: {alert['message']}")
        
        # 6. GPIO-Test
        logger.info("🔌 DHT22 GPIO-Diagnose:")
        try:
            import board
            import digitalio
            
            # GPIO 18 als Digital-Pin testen
            pin = digitalio.DigitalInOut(board.D18)
            pin.direction = digitalio.Direction.OUTPUT
            pin.value = True
            time.sleep(0.1)
            pin.value = False
            pin.deinit()
            logger.info("   ✅ GPIO 18 Funktionstest erfolgreich")
            
        except Exception as gpio_error:
            logger.warning(f"   ⚠️ GPIO-Test fehlgeschlagen: {gpio_error}")
        
        success = success_count > 0
        
        if success:
            logger.info("✅ DHT22 Raumsensor funktioniert korrekt")
        else:
            logger.error("❌ DHT22 Raumsensor-Test fehlgeschlagen")
            logger.info("💡 Troubleshooting-Tipps:")
            logger.info("   - Prüfe Verkabelung (VCC->3.3V, GND->GND, Data->GPIO18)")
            logger.info("   - Verwende 10kΩ Pull-up Widerstand zwischen Data und VCC")
            logger.info("   - Warte 2 Sekunden zwischen Messungen")
            logger.info("   - Führe spezifischen DHT22-Test aus: python test_dht22.py")
        
        room_sensor.cleanup()
        return success
        
    except Exception as e:
        logger.error(f"❌ DHT22-Test fehlgeschlagen: {e}")
        logger.error("💡 Installiere fehlende Pakete: pip install adafruit-circuitpython-dht")
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
        logger.info(f"\n{'='*20} {test_name} {'='*20}")
        try:
            results[test_name] = test_func()
        except Exception as e:
            logger.error(f"❌ Test '{test_name}' mit Fehler beendet: {e}")
            results[test_name] = False
    
    # Zusammenfassung
    logger.info("\n" + "="*50)
    logger.info("📋 TEST-ZUSAMMENFASSUNG")
    logger.info("="*50)
    
    passed_tests = 0
    total_tests = len(tests)
    
    for test_name, passed in results.items():
        status = "✅ BESTANDEN" if passed else "❌ FEHLGESCHLAGEN"
        logger.info(f"{test_name:<25}: {status}")
        if passed:
            passed_tests += 1
    
    logger.info(f"\nGesamtergebnis: {passed_tests}/{total_tests} Tests bestanden")
    
    if passed_tests == total_tests:
        logger.info("🎉 Alle Tests erfolgreich! System ist einsatzbereit.")
        return True
    else:
        logger.warning(f"⚠️ {total_tests - passed_tests} Test(s) fehlgeschlagen!")
        
        # Spezifische Empfehlungen
        if not results.get("1-Wire Interface", True):
            logger.info("💡 1-Wire Interface Lösung: sudo reboot (nach install_rpi5.sh)")
        
        if not results.get("DHT22 Raumsensor", True):
            logger.info("💡 DHT22 Lösung: python test_dht22.py für detaillierte Diagnose")
        
        if not results.get("InfluxDB-Verbindung", True):
            logger.info("💡 InfluxDB Lösung: docker-compose up -d")
        
        return False

def run_dht22_only_test():
    """Führt nur den DHT22-Test durch"""
    logger.info("🌡️ DHT22-spezifischer Test")
    logger.info("=" * 30)
    
    # Importiere spezifischen DHT22-Test
    try:
        import subprocess
        import os
        
        script_dir = os.path.dirname(__file__)
        dht22_script = os.path.join(script_dir, "test_dht22.py")
        
        if os.path.exists(dht22_script):
            logger.info("🚀 Führe dedizierten DHT22-Test aus...")
            result = subprocess.run([sys.executable, dht22_script], 
                                  capture_output=True, text=True, cwd=script_dir)
            
            if result.stdout:
                print(result.stdout)
            if result.stderr:
                print(result.stderr)
                
            return result.returncode == 0
        else:
            logger.warning("⚠️ Spezifisches DHT22-Test-Script nicht gefunden")
            return test_room_sensor()
            
    except Exception as e:
        logger.error(f"❌ DHT22-Test Fehler: {e}")
        return test_room_sensor()
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
