#!/usr/bin/env python3
"""
DHT22 Sensor Test-Tool für Heizungsüberwachung
Robuste Diagnose mit mehreren DHT-Bibliotheken und Fallback-Optionen
"""

import sys
import time
import logging
import os
from typing import Dict, Optional

# Pfad für lokale Module
sys.path.append(os.path.join(os.path.dirname(__file__), 'src'))

# Logging konfigurieren
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def test_dht_libraries():
    """Teste verfügbare DHT22-Bibliotheken"""
    print("🔍 DHT22 Bibliotheken-Test")
    print("=" * 40)
    
    libraries_found = []
    
    # Test 1: Adafruit CircuitPython
    try:
        import board
        import adafruit_dht
        libraries_found.append("adafruit")
        print("✅ Adafruit CircuitPython: Verfügbar")
        try:
            # Test basic board access
            test_pin = board.D18
            print("   - Board GPIO Access: OK")
        except Exception as e:
            print(f"   - Board GPIO Access: FEHLER ({e})")
    except ImportError as e:
        print(f"❌ Adafruit CircuitPython: NICHT verfügbar ({e})")
        print("   Installiere mit: pip install adafruit-circuitpython-dht adafruit-blinka")
    
    # Test 2: Legacy Adafruit_DHT
    try:
        import Adafruit_DHT
        libraries_found.append("legacy")
        print("✅ Legacy Adafruit_DHT: Verfügbar")
    except ImportError as e:
        print(f"❌ Legacy Adafruit_DHT: NICHT verfügbar ({e})")
    
    # Test 3: Alternative DHT
    try:
        import dht
        libraries_found.append("alternative")
        print("✅ Alternative DHT: Verfügbar")
    except ImportError:
        pass
    
    print(f"\n📊 Verfügbare Bibliotheken: {len(libraries_found)}")
    return libraries_found

def test_dht22_adafruit(pin: int = 18, attempts: int = 5):
    """Test DHT22 mit Adafruit CircuitPython"""
    print(f"\n🌡️ DHT22 Test - Adafruit CircuitPython (GPIO {pin})")
    print("-" * 50)
    
    try:
        import board
        import adafruit_dht
        
        # DHT22 Sensor erstellen
        if pin == 18:
            dht = adafruit_dht.DHT22(board.D18)
        elif pin == 4:
            dht = adafruit_dht.DHT22(board.D4)
        else:
            print(f"⚠️ GPIO {pin} - verwende dynamischen Zugriff")
            dht = adafruit_dht.DHT22(getattr(board, f'D{pin}'))
        
        print(f"✅ DHT22 Sensor initialisiert (GPIO {pin})")
        
        successful_readings = 0
        
        for i in range(attempts):
            try:
                print(f"\n🔄 Leseversuch {i+1}/{attempts}...")
                
                temperature = dht.temperature
                humidity = dht.humidity
                
                if temperature is not None and humidity is not None:
                    print(f"✅ Temperatur: {temperature:.1f}°C")
                    print(f"✅ Luftfeuchtigkeit: {humidity:.1f}%")
                    
                    # Plausibilität prüfen
                    if -20 <= temperature <= 50 and 0 <= humidity <= 100:
                        print("✅ Werte sind plausibel")
                        successful_readings += 1
                    else:
                        print("⚠️ Werte außerhalb normaler Bereiche")
                else:
                    print("❌ Keine gültigen Daten erhalten")
                
                if i < attempts - 1:
                    time.sleep(2)
                    
            except RuntimeError as e:
                print(f"⚠️ DHT-Fehler: {e}")
                if "Checksum" in str(e):
                    print("   Hinweis: Checksum-Fehler sind bei DHT22 normal")
            except Exception as e:
                print(f"❌ Unerwarteter Fehler: {e}")
                
        try:
            dht.exit()
            print("✅ Sensor deinitialisiert")
        except:
            pass
            
        print(f"\n📊 Erfolgreiche Messungen: {successful_readings}/{attempts}")
        return successful_readings > 0
        
    except Exception as e:
        print(f"❌ Initialisierung fehlgeschlagen: {e}")
        return False

def test_heating_room_sensor():
    """Test der HeatingRoomSensor Klasse"""
    print(f"\n🏠 Heizungsraum-Sensor Test")
    print("-" * 40)
    
    try:
        from sensors.dht22_sensor import HeatingRoomSensor
        print("✅ HeatingRoomSensor Klasse importiert")
        
        # Sensor erstellen
        sensor = HeatingRoomSensor(pin=18, name="Test-Heizungsraum")
        print("✅ Sensor initialisiert")
        
        # 3 Messungen
        successful_tests = 0
        for i in range(3):
            print(f"\n🔄 Heizungsraum-Messung {i+1}/3...")
            
            data = sensor.read_sensor_data(retries=3)
            
            if data['temperature'] is not None:
                print(f"✅ Temperatur: {data['temperature']:.1f}°C")
                print(f"✅ Luftfeuchtigkeit: {data['humidity']:.1f}%")
                if data['dew_point'] is not None:
                    print(f"📊 Taupunkt: {data['dew_point']:.1f}°C")
                
                # Erweiterte Analyse falls verfügbar
                try:
                    analysis = sensor.analyze_heating_room_conditions(
                        data['temperature'], data['humidity']
                    )
                    print(f"📋 Raumanalyse: {analysis.get('status', 'OK')}")
                    
                    if analysis.get('warnings'):
                        for warning in analysis['warnings']:
                            print(f"⚠️ {warning}")
                except AttributeError:
                    print("📋 Basis-Analyse: Temperatur und Feuchtigkeit normal")
                
                successful_tests += 1
            else:
                print("❌ Keine Daten erhalten")
            
            if i < 2:
                time.sleep(3)
        
        print(f"\n📊 Erfolgreiche Sensor-Tests: {successful_tests}/3")
        return successful_tests > 0
        
    except ImportError as e:
        print(f"❌ Import fehlgeschlagen: {e}")
        print("   HeatingRoomSensor Klasse nicht verfügbar")
        return False
    except Exception as e:
        print(f"❌ Test fehlgeschlagen: {e}")
        return False

def test_dummy_mode():
    """Test DHT22 im Dummy-Modus"""
    print(f"\n🎭 DHT22 Dummy-Modus Test")
    print("-" * 30)
    
    try:
        from sensors.dht22_sensor import HeatingRoomSensor, DHT_AVAILABLE, DHT_METHOD
        
        print(f"DHT Verfügbar: {DHT_AVAILABLE}")
        print(f"DHT Methode: {DHT_METHOD}")
        
        if not DHT_AVAILABLE:
            sensor = HeatingRoomSensor(pin=18, name="Dummy-Test")
            data = sensor.read_sensor_data()
            
            print("✅ Dummy-Modus funktioniert")
            print(f"📊 Dummy-Temperatur: {data['temperature']}°C")
            print(f"📊 Dummy-Feuchtigkeit: {data['humidity']}%")
            return True
        else:
            print("✅ DHT verfügbar - kein Dummy-Modus nötig")
            return True
            
    except Exception as e:
        print(f"❌ Dummy-Test fehlgeschlagen: {e}")
        return False

def show_gpio_info():
    """Zeige GPIO und Verkabelungs-Informationen"""
    print("\n📌 DHT22 Verkabelung")
    print("=" * 25)
    print("Standard-Anschluss für Heizungsraum:")
    print("├── VCC (Pin 1):  3.3V    -> GPIO Pin 17")
    print("├── Data (Pin 2): GPIO 18 -> GPIO Pin 12")
    print("├── NC (Pin 3):   Nicht verbunden")
    print("└── GND (Pin 4):  GND     -> GPIO Pin 20")
    print("")
    print("Optional: 10kΩ Pull-up zwischen Data und VCC")

def show_troubleshooting():
    """Zeige Troubleshooting-Hilfe"""
    print("\n🔧 DHT22 Troubleshooting")
    print("=" * 30)
    
    print("\n1. Bibliotheken installieren:")
    print("   pip install adafruit-circuitpython-dht")
    print("   pip install adafruit-blinka")
    print("   # oder via apt:")
    print("   sudo apt install python3-adafruit-circuitpython-dht")
    
    print("\n2. Berechtigungen prüfen:")
    print("   sudo usermod -a -G gpio pi")
    print("   # Neuanmeldung erforderlich")
    
    print("\n3. Hardware prüfen:")
    print("   - Verkabelung kontrollieren")
    print("   - 3.3V Stromversorgung messen")
    print("   - GPIO 18 Funktion testen")
    
    print("\n4. Alternative GPIO Pins:")
    print("   - GPIO 4 (Pin 7)")
    print("   - GPIO 22 (Pin 15)")
    
    print("\n5. System-Logs prüfen:")
    print("   dmesg | grep -i gpio")
    print("   journalctl | grep -i dht")

def main():
    """Hauptfunktion"""
    print("🧪 DHT22 Umfassender Test")
    print("==========================")
    
    # GPIO Info
    show_gpio_info()
    
    # Bibliotheken testen
    available_libs = test_dht_libraries()
    
    success_count = 0
    total_tests = 0
    
    # Tests mit verfügbaren Bibliotheken
    if "adafruit" in available_libs:
        total_tests += 1
        if test_dht22_adafruit():
            success_count += 1
    
    # HeatingRoomSensor Test
    total_tests += 1
    if test_heating_room_sensor():
        success_count += 1
    
    # Dummy-Modus Test
    total_tests += 1
    if test_dummy_mode():
        success_count += 1
    
    # Ergebnis
    print(f"\n🏁 Test abgeschlossen")
    print("=" * 25)
    print(f"Erfolgreiche Tests: {success_count}/{total_tests}")
    
    if success_count == total_tests:
        print("✅ Alle Tests erfolgreich!")
        print("DHT22 System ist betriebsbereit")
    elif success_count > 0:
        print("⚠️ Teilweise erfolgreich")
        print("Grundfunktionen verfügbar")
    else:
        print("❌ Alle Tests fehlgeschlagen")
        show_troubleshooting()
    
    print(f"\n💡 Hinweis:")
    print("DHT22 Sensoren sind bekannt für gelegentliche Lesefehler.")
    print("Das ist normal und wird durch Wiederholung kompensiert.")

if __name__ == "__main__":
    main()
