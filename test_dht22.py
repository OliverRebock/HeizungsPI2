#!/usr/bin/env python3
"""
DHT22 Sensor Test für Heizungsüberwachung
Testet den DHT22 Temperatur- und Luftfeuchtigkeitssensor auf GPIO 18
"""

import sys
import time
import os
from pathlib import Path

# Projekt-Root zum Python-Pfad hinzufügen
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

try:
    # Versuche DHT-Bibliotheken zu importieren
    try:
        import board
        import adafruit_dht
        ADAFRUIT_AVAILABLE = True
        print("✅ Adafruit CircuitPython DHT verfügbar")
    except ImportError:
        ADAFRUIT_AVAILABLE = False
        print("⚠️ Adafruit CircuitPython DHT nicht verfügbar")
    
    # Importiere HeatingRoomSensor
    from src.sensors.dht22_sensor import HeatingRoomSensor
    HEATING_SENSOR_AVAILABLE = True
    print("✅ HeatingRoomSensor verfügbar")
    
except ImportError as e:
    print(f"❌ Import-Fehler: {e}")
    print("Installiere fehlende Pakete mit: pip install -r requirements.txt")
    print("Oder verwende Virtual Environment: source venv/bin/activate")
    HEATING_SENSOR_AVAILABLE = False

def test_raw_dht22():
    """Test des DHT22 mit der Adafruit-Bibliothek direkt"""
    print("🌡️ DHT22 Raw-Test (Adafruit Library)")
    print("===================================")
    
    if not ADAFRUIT_AVAILABLE:
        print("⚠️ Adafruit-Bibliothek nicht verfügbar - überspringe Raw-Test")
        return
    
    try:
        # DHT22 an GPIO 18 initialisieren
        dht = adafruit_dht.DHT22(board.D18)
        
        success_count = 0
        total_attempts = 10
        
        for i in range(total_attempts):
            try:
                temperature = dht.temperature
                humidity = dht.humidity
                
                if temperature is not None and humidity is not None:
                    print(f"✅ Versuch {i+1}: {temperature:.1f}°C, {humidity:.1f}%")
                    success_count += 1
                else:
                    print(f"⚠️ Versuch {i+1}: Keine Daten")
                    
            except RuntimeError as e:
                print(f"⚠️ Versuch {i+1}: {e}")
            except Exception as e:
                print(f"❌ Versuch {i+1}: Unerwarteter Fehler: {e}")
                
            time.sleep(2)
        
        print(f"\n📊 Erfolgsrate: {success_count}/{total_attempts} ({success_count/total_attempts*100:.1f}%)")
        
        # Cleanup
        dht.exit()
        return success_count > 0
        
    except Exception as e:
        print(f"❌ DHT22 Initialisierung fehlgeschlagen: {e}")
        return False

def test_sensor_class():
    """Test der HeatingRoomSensor-Klasse"""
    print("\n🔧 DHT22 Sensor-Klassen-Test")
    print("============================")
    
    if not HEATING_SENSOR_AVAILABLE:
        print("⚠️ HeatingRoomSensor nicht verfügbar - überspringe Test")
        return False
    
    try:
        sensor = HeatingRoomSensor(pin=18)
        
        success_count = 0
        total_attempts = 5
        
        for i in range(total_attempts):
            print(f"Versuch {i+1}...")
            try:
                data = sensor.read_sensor_data()
                
                if data['temperature'] is not None and data['humidity'] is not None:
                    print(f"✅ Temperatur: {data['temperature']:.1f}°C")
                    print(f"✅ Luftfeuchtigkeit: {data['humidity']:.1f}%")
                    if data['dew_point'] is not None:
                        print(f"✅ Taupunkt: {data['dew_point']:.1f}°C")
                    success_count += 1
                else:
                    print(f"⚠️ Keine gültigen Daten erhalten")
                    
            except Exception as e:
                print(f"❌ Fehler beim Lesen: {e}")
                
            time.sleep(2)
                success_count += 1
            else:
                print(f"⚠️ Keine gültigen Daten erhalten")
                
            time.sleep(3)
        
        print(f"\n📊 Sensor-Klassen Erfolgsrate: {success_count}/{total_attempts} ({success_count/total_attempts*100:.1f}%)")
        return success_count > 0
        
    except Exception as e:
        print(f"❌ HeatingRoomSensor-Klasse Fehler: {e}")
        return False

def test_gpio_status():
    """Teste GPIO-Status und Berechtigungen"""
    print("\n🔌 GPIO Status-Test")
    print("==================")
    
    try:
        # Prüfe GPIO-Geräte
        gpio_devices = ["/dev/gpiomem", "/dev/gpio"]
        for device in gpio_devices:
            if os.path.exists(device):
                print(f"✅ {device} gefunden")
                # Prüfe Berechtigungen
                if os.access(device, os.R_OK | os.W_OK):
                    print(f"✅ {device} Lese-/Schreibzugriff OK")
                else:
                    print(f"⚠️ {device} Keine Berechtigungen")
            else:
                print(f"❌ {device} nicht gefunden")
        
        # Prüfe BCM2835-Module
        with open("/proc/modules", "r") as f:
            modules = f.read()
            
        bcm_modules = ["bcm2835_gpiomem", "gpio_bcm2835"]
        for module in bcm_modules:
            if module in modules:
                print(f"✅ Kernel-Modul {module} geladen")
            else:
                print(f"⚠️ Kernel-Modul {module} nicht geladen")
                
        return True
        
    except Exception as e:
        print(f"❌ GPIO-Test Fehler: {e}")
        return False

def test_environment():
    """Teste Umgebung und Abhängigkeiten"""
    print("\n🐍 Python-Umgebung Test")
    print("=======================")
    
    # Python-Version
    python_version = sys.version_info
    print(f"Python Version: {python_version.major}.{python_version.minor}.{python_version.micro}")
    
    # Benötigte Module prüfen
    required_modules = [
        ("board", "CircuitPython Board"),
        ("adafruit_dht", "Adafruit DHT"),
        ("digitalio", "DigitalIO"),
        ("busio", "BusIO")
    ]
    
    all_modules_ok = True
    for module_name, description in required_modules:
        try:
            __import__(module_name)
            print(f"✅ {description} ({module_name}) - OK")
        except ImportError:
            print(f"❌ {description} ({module_name}) - FEHLT")
            all_modules_ok = False
    
    # Blinka-Version prüfen
    try:
        import adafruit_blinka
        print(f"✅ Adafruit Blinka Version verfügbar")
    except ImportError:
        print(f"❌ Adafruit Blinka nicht installiert")
        all_modules_ok = False
    
    return all_modules_ok

def print_troubleshooting_tips():
    """Zeige Troubleshooting-Tipps"""
    print("\n🔧 Troubleshooting-Tipps")
    print("========================")
    print("Falls Probleme auftreten:")
    print("")
    print("1. GPIO-Berechtigungen:")
    print("   sudo usermod -a -G gpio pi")
    print("   sudo chmod 666 /dev/gpiomem")
    print("")
    print("2. Python-Pakete neu installieren:")
    print("   pip install --upgrade adafruit-circuitpython-dht")
    print("   pip install --upgrade adafruit-blinka")
    print("")
    print("3. GPIO-Pin prüfen:")
    print("   - DHT22 VCC -> 3.3V (Pin 17)")
    print("   - DHT22 GND -> GND (Pin 20)")
    print("   - DHT22 Data -> GPIO 18 (Pin 12)")
    print("")
    print("4. Pull-up Widerstand:")
    print("   - 10kΩ zwischen Data und VCC (optional)")
    print("")
    print("5. Sensor-Timing:")
    print("   - DHT22 benötigt 2-3 Sekunden zwischen Messungen")
    print("   - Nach dem Einschalten 1-2 Sekunden warten")
    print("")
    print("6. Hardware prüfen:")
    print("   - Verkabelung kontrollieren")
    print("   - Sensor-Kontakte reinigen")
    print("   - Anderen GPIO-Pin testen")

def main():
    """Hauptfunktion für DHT22-Tests"""
    print("🌡️ DHT22 Sensor Diagnose-Tool")
    print("==============================")
    print("GPIO Pin: 18 (Pin 12)")
    print("Sensor: DHT22 (AM2302)")
    print("")
    
    # Tests ausführen
    test_results = {}
    
    # 1. Umgebung testen
    test_results['environment'] = test_environment()
    
    # 2. GPIO-Status prüfen
    test_results['gpio'] = test_gpio_status()
    
    # 3. Raw DHT22-Test
    if test_results['environment'] and test_results['gpio']:
        test_results['raw_sensor'] = test_raw_dht22()
    else:
        print("\n⚠️ Umgebungs- oder GPIO-Tests fehlgeschlagen - überspringe Sensor-Tests")
        test_results['raw_sensor'] = False
    
    # 4. Sensor-Klassen-Test
    if test_results['raw_sensor']:
        test_results['sensor_class'] = test_sensor_class()
    else:
        print("\n⚠️ Raw-Sensor-Test fehlgeschlagen - überspringe Klassen-Test")
        test_results['sensor_class'] = False
    
    # Zusammenfassung
    print("\n📋 Test-Zusammenfassung")
    print("=======================")
    
    for test_name, result in test_results.items():
        status = "✅ BESTANDEN" if result else "❌ FEHLGESCHLAGEN"
        test_display = {
            'environment': 'Python-Umgebung',
            'gpio': 'GPIO-Status',
            'raw_sensor': 'DHT22 Raw-Test',
            'sensor_class': 'Sensor-Klassen-Test'
        }
        print(f"{test_display.get(test_name, test_name)}: {status}")
    
    overall_success = all(test_results.values())
    
    if overall_success:
        print("\n🎉 Alle Tests erfolgreich!")
        print("Der DHT22 Sensor ist einsatzbereit.")
    else:
        print("\n⚠️ Einige Tests fehlgeschlagen!")
        print_troubleshooting_tips()
    
    return overall_success

if __name__ == "__main__":
    try:
        success = main()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n🛑 Test durch Benutzer abgebrochen")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unerwarteter Fehler: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
