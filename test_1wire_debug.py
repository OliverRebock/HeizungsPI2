#!/usr/bin/env python3
"""
DS18B20 1-Wire Sensor Debug Tool
Detaillierte Diagnose für 1-Wire Temperatur-Sensoren
"""

import os
import glob
import time
import sys
from pathlib import Path

def test_1wire_interface():
    """Test 1-Wire Interface und Module"""
    print("🔍 1-Wire Interface Test")
    print("=" * 50)
    
    # 1. Kernel Module prüfen
    print("\n1. Kernel Module:")
    modules_loaded = []
    try:
        with open('/proc/modules', 'r') as f:
            content = f.read()
            if 'w1_gpio' in content:
                modules_loaded.append('w1_gpio')
                print("   ✅ w1_gpio geladen")
            else:
                print("   ❌ w1_gpio NICHT geladen")
                
            if 'w1_therm' in content:
                modules_loaded.append('w1_therm')
                print("   ✅ w1_therm geladen")
            else:
                print("   ❌ w1_therm NICHT geladen")
                
    except Exception as e:
        print(f"   ❌ Fehler beim Lesen der Module: {e}")
    
    # 2. 1-Wire Master prüfen
    print("\n2. 1-Wire Master:")
    w1_master_path = "/sys/bus/w1/devices/w1_bus_master1"
    if os.path.exists(w1_master_path):
        print("   ✅ 1-Wire Master gefunden")
        
        # Slave-Liste anzeigen
        slaves_file = os.path.join(w1_master_path, "w1_master_slaves")
        if os.path.exists(slaves_file):
            try:
                with open(slaves_file, 'r') as f:
                    slaves = f.read().strip().split('\n')
                    if slaves and slaves[0]:
                        print(f"   📡 {len(slaves)} Slave(s) registriert:")
                        for slave in slaves:
                            if slave.strip():
                                print(f"      - {slave.strip()}")
                    else:
                        print("   ⚠️ Keine Slaves registriert")
            except Exception as e:
                print(f"   ❌ Fehler beim Lesen der Slaves: {e}")
        else:
            print("   ❌ w1_master_slaves Datei nicht gefunden")
    else:
        print("   ❌ 1-Wire Master NICHT gefunden")
        print("      Prüfe GPIO-Konfiguration und Module")
    
    return len(modules_loaded) == 2

def test_sensors_detailed():
    """Detaillierte Sensor-Tests"""
    print("\n🌡️ DS18B20 Sensor-Diagnose")
    print("=" * 50)
    
    # Sensor-Verzeichnisse finden
    sensor_dirs = glob.glob("/sys/bus/w1/devices/28-*")
    
    if not sensor_dirs:
        print("❌ Keine DS18B20 Sensoren gefunden!")
        print("\nMögliche Ursachen:")
        print("   - 1-Wire Interface nicht aktiviert")
        print("   - Sensoren nicht angeschlossen")
        print("   - Verkabelung fehlerhaft")
        print("   - Pull-up Widerstand fehlt (4.7kΩ)")
        return False
    
    print(f"✅ {len(sensor_dirs)} DS18B20 Sensor(en) gefunden")
    
    working_sensors = 0
    
    for i, sensor_dir in enumerate(sorted(sensor_dirs), 1):
        sensor_id = os.path.basename(sensor_dir)
        print(f"\n--- Sensor {i}: {sensor_id} ---")
        
        # w1_slave Datei prüfen
        slave_file = os.path.join(sensor_dir, "w1_slave")
        
        if not os.path.exists(slave_file):
            print("   ❌ w1_slave Datei nicht gefunden")
            continue
            
        print("   ✅ w1_slave Datei gefunden")
        
        # Mehrere Leseversuche
        for attempt in range(3):
            try:
                print(f"   🔄 Leseversuch {attempt + 1}/3...")
                
                with open(slave_file, 'r') as f:
                    data = f.read().strip()
                
                if not data:
                    print("   ⚠️ Datei ist leer")
                    time.sleep(1)
                    continue
                
                lines = data.split('\n')
                print(f"   📄 Rohdaten ({len(lines)} Zeilen):")
                for line_num, line in enumerate(lines, 1):
                    print(f"      Zeile {line_num}: {line}")
                
                # CRC Check (erste Zeile)
                if len(lines) >= 1:
                    crc_line = lines[0]
                    if "YES" in crc_line:
                        print("   ✅ CRC Check: OK")
                        crc_ok = True
                    else:
                        print(f"   ❌ CRC Check: FEHLER - {crc_line}")
                        crc_ok = False
                else:
                    print("   ❌ Keine CRC-Zeile gefunden")
                    crc_ok = False
                
                # Temperatur extrahieren (zweite Zeile)
                temp_found = False
                if len(lines) >= 2 and crc_ok:
                    temp_line = lines[1]
                    print(f"   🌡️ Temperatur-Zeile: {temp_line}")
                    
                    if "t=" in temp_line:
                        temp_str = temp_line.split("t=")[1]
                        try:
                            temp_raw = int(temp_str)
                            temp_celsius = temp_raw / 1000.0
                            
                            print(f"   📊 Raw-Wert: {temp_raw}")
                            print(f"   🌡️ Temperatur: {temp_celsius:.1f}°C")
                            
                            # Plausibilitäts-Check
                            if -55 <= temp_celsius <= 125:
                                if temp_celsius != 85.0:  # 85°C = Standard-Fehlerwert
                                    print("   ✅ Temperatur plausibel")
                                    working_sensors += 1
                                    temp_found = True
                                    break
                                else:
                                    print("   ⚠️ Sensor nicht initialisiert (85°C)")
                            else:
                                print(f"   ❌ Temperatur außerhalb gültiger Bereich (-55°C bis 125°C)")
                        except ValueError:
                            print(f"   ❌ Kann Temperatur nicht parsen: {temp_str}")
                    else:
                        print("   ❌ Kein 't=' in Temperatur-Zeile gefunden")
                
                if not temp_found and attempt < 2:
                    print("   ⏳ Warte 2 Sekunden vor nächstem Versuch...")
                    time.sleep(2)
                elif temp_found:
                    break
                    
            except Exception as e:
                print(f"   ❌ Fehler beim Lesen: {e}")
                if attempt < 2:
                    time.sleep(1)
    
    print(f"\n📊 Zusammenfassung:")
    print(f"   Erkannte Sensoren: {len(sensor_dirs)}")
    print(f"   Funktionierende Sensoren: {working_sensors}")
    print(f"   Defekte/Problematische: {len(sensor_dirs) - working_sensors}")
    
    return working_sensors > 0

def show_troubleshooting():
    """Zeige Troubleshooting-Tipps"""
    print("\n🔧 Troubleshooting-Tipps")
    print("=" * 50)
    print("\n1. 1-Wire Interface aktivieren:")
    print("   sudo nano /boot/firmware/config.txt")
    print("   # Zeile hinzufügen: dtoverlay=w1-gpio,gpiopin=4")
    print("   sudo reboot")
    
    print("\n2. Module manuell laden:")
    print("   sudo modprobe w1-gpio")
    print("   sudo modprobe w1-therm")
    
    print("\n3. Verkabelung prüfen:")
    print("   - VDD (rot): 3.3V (Pin 1)")
    print("   - GND (schwarz): GND (Pin 6)")
    print("   - Data (gelb): GPIO 4 (Pin 7)")
    print("   - Pull-up: 4.7kΩ zwischen Data und VDD")
    
    print("\n4. GPIO-Status prüfen:")
    print("   gpio readall  # falls installiert")
    print("   gpioinfo      # alternative")
    
    print("\n5. Kernel-Logs prüfen:")
    print("   dmesg | grep -i w1")
    print("   journalctl | grep -i w1")

def main():
    """Hauptfunktion"""
    print("🧪 DS18B20 1-Wire Debug Tool")
    print("============================")
    
    # Prüfen ob auf Raspberry Pi
    if not os.path.exists("/sys/bus/w1"):
        print("❌ Dieses Tool ist für Raspberry Pi konzipiert")
        print("   /sys/bus/w1 nicht gefunden")
        sys.exit(1)
    
    # Interface testen
    interface_ok = test_1wire_interface()
    
    # Sensoren testen
    sensors_ok = test_sensors_detailed()
    
    # Troubleshooting anzeigen bei Problemen
    if not interface_ok or not sensors_ok:
        show_troubleshooting()
    
    print(f"\n🏁 Test abgeschlossen")
    if interface_ok and sensors_ok:
        print("✅ 1-Wire System funktioniert korrekt")
    else:
        print("❌ 1-Wire System hat Probleme")
        print("   Siehe Troubleshooting-Tipps oben")

if __name__ == "__main__":
    main()
