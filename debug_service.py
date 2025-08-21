#!/usr/bin/env python3
"""
Service Debug Script
Testet die grundlegenden Funktionen ohne kompletten Service-Start
"""

import sys
import os
from pathlib import Path

# Projekt-Root hinzufügen
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

def test_imports():
    """Testet alle wichtigen Imports"""
    print("🔍 Teste Python-Imports...")
    
    # Standard-Bibliotheken
    try:
        import time, signal, logging, datetime
        print("✅ Standard-Bibliotheken: OK")
    except ImportError as e:
        print(f"❌ Standard-Bibliotheken: {e}")
        return False
    
    # Dotenv
    try:
        from dotenv import load_dotenv
        print("✅ python-dotenv: OK")
    except ImportError:
        print("⚠️ python-dotenv: Nicht verfügbar (optional)")
    
    # Projekt-Module
    modules_ok = True
    
    try:
        from src.sensors.heating_sensors import HeatingSystemManager
        print("✅ HeatingSystemManager: OK")
    except ImportError as e:
        print(f"❌ HeatingSystemManager: {e}")
        modules_ok = False
    
    try:
        from src.sensors.dht22_sensor import HeatingRoomSensor
        print("✅ HeatingRoomSensor: OK")
    except ImportError as e:
        print(f"⚠️ HeatingRoomSensor: {e} (optional)")
    
    try:
        from src.database.influxdb_client import HeatingInfluxDBClient
        print("✅ HeatingInfluxDBClient: OK")
    except ImportError as e:
        print(f"❌ HeatingInfluxDBClient: {e}")
        modules_ok = False
    
    return modules_ok

def test_environment():
    """Testet Umgebungsvariablen und Konfiguration"""
    print("\n🔍 Teste Umgebung...")
    
    # .env Datei
    env_file = Path(".env")
    if env_file.exists():
        print("✅ .env Datei gefunden")
        
        # Lade .env
        try:
            from dotenv import load_dotenv
            load_dotenv()
            print("✅ .env Datei geladen")
        except ImportError:
            print("⚠️ python-dotenv nicht verfügbar - verwende System-Umgebungsvariablen")
    else:
        print("⚠️ .env Datei nicht gefunden")
    
    # Wichtige Umgebungsvariablen
    required_vars = [
        'INFLUXDB_URL',
        'INFLUXDB_TOKEN', 
        'INFLUXDB_ORG',
        'INFLUXDB_BUCKET'
    ]
    
    for var in required_vars:
        value = os.getenv(var)
        if value:
            print(f"✅ {var}: {value[:20]}...")
        else:
            print(f"⚠️ {var}: Nicht gesetzt")
    
    # Config-Dateien
    config_file = Path("config/heating_circuits.yaml")
    if config_file.exists():
        print("✅ Heizkreis-Konfiguration gefunden")
    else:
        print("⚠️ Heizkreis-Konfiguration fehlt")

def test_hardware():
    """Testet Hardware-Verfügbarkeit"""
    print("\n🔍 Teste Hardware...")
    
    # 1-Wire Interface
    w1_path = Path("/sys/bus/w1/devices")
    if w1_path.exists():
        sensors = list(w1_path.glob("28-*"))
        print(f"✅ 1-Wire Interface: {len(sensors)} DS18B20 Sensoren gefunden")
        
        for sensor in sensors[:3]:  # Zeige nur erste 3
            print(f"   📡 {sensor.name}")
    else:
        print("❌ 1-Wire Interface nicht verfügbar")
    
    # GPIO für DHT22
    try:
        import RPi.GPIO as GPIO
        print("✅ RPi.GPIO verfügbar")
    except ImportError:
        print("⚠️ RPi.GPIO nicht verfügbar (nicht auf Pi?)")

def test_services():
    """Testet externe Services"""
    print("\n🔍 Teste Services...")
    
    # InfluxDB
    try:
        import requests
        response = requests.get("http://localhost:8086/health", timeout=5)
        if response.status_code == 200:
            print("✅ InfluxDB erreichbar")
        else:
            print(f"⚠️ InfluxDB antwortet mit Status {response.status_code}")
    except ImportError:
        print("⚠️ requests nicht verfügbar für InfluxDB-Test")
    except Exception as e:
        print(f"❌ InfluxDB nicht erreichbar: {e}")
    
    # Docker Container
    try:
        import subprocess
        result = subprocess.run(['docker', 'ps'], capture_output=True, text=True)
        if result.returncode == 0:
            lines = result.stdout.strip().split('\n')
            containers = len(lines) - 1  # Header abziehen
            print(f"✅ Docker: {containers} Container laufen")
        else:
            print("❌ Docker nicht verfügbar")
    except FileNotFoundError:
        print("❌ Docker Command nicht gefunden")
    except Exception as e:
        print(f"❌ Docker-Fehler: {e}")

def test_minimal_run():
    """Testet minimalen Programmlauf"""
    print("\n🔍 Teste minimalen Programmlauf...")
    
    try:
        # Teste basic imports
        from src.sensors.heating_sensors import HeatingSystemManager
        
        # Teste Initialisierung
        manager = HeatingSystemManager()
        circuit_count = manager.get_circuit_count()
        print(f"✅ HeatingSystemManager: {circuit_count} Kreise")
        
        # Teste InfluxDB Client
        from src.database.influxdb_client import HeatingInfluxDBClient
        client = HeatingInfluxDBClient()
        print("✅ InfluxDB Client initialisiert")
        
        return True
        
    except Exception as e:
        print(f"❌ Minimaler Test fehlgeschlagen: {e}")
        return False

def main():
    """Hauptfunktion für Service-Debug"""
    print("🔧 Heizungsüberwachung - Service Debug")
    print("=" * 50)
    
    # Arbeitsverzeichnis
    print(f"📂 Arbeitsverzeichnis: {os.getcwd()}")
    print(f"🐍 Python-Version: {sys.version}")
    print()
    
    # Tests ausführen
    tests_passed = 0
    total_tests = 5
    
    if test_imports():
        tests_passed += 1
    
    test_environment()
    tests_passed += 1
    
    test_hardware()
    tests_passed += 1
    
    test_services()
    tests_passed += 1
    
    if test_minimal_run():
        tests_passed += 1
    
    # Ergebnis
    print("\n" + "=" * 50)
    print(f"📊 Ergebnis: {tests_passed}/{total_tests} Tests bestanden")
    
    if tests_passed >= 4:
        print("✅ System sollte funktionsfähig sein")
        return 0
    elif tests_passed >= 2:
        print("⚠️ System teilweise funktionsfähig - prüfe Warnungen")
        return 1
    else:
        print("❌ System nicht funktionsfähig - behebe Fehler")
        return 2

if __name__ == "__main__":
    sys.exit(main())
