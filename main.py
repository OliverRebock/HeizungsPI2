#!/usr/bin/env python3
"""
Hauptprogramm für die Heizungsüberwachung
Startet das kontinuierliche Monitoring-System
"""

import os
import sys
import time
import signal
import logging
from datetime import datetime
from typing import Optional
from pathlib import Path

# Projekt-Root zum Python-Pfad hinzufügen
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

# Robuste Imports mit Fehlerbehandlung
try:
    from src.sensors.heating_sensors import HeatingSystemManager
    HEATING_AVAILABLE = True
except ImportError as e:
    print(f"⚠️ Heizungssensoren nicht verfügbar: {e}")
    HEATING_AVAILABLE = False

try:
    from src.sensors.dht22_sensor import HeatingRoomSensor
    DHT22_AVAILABLE = True
except ImportError as e:
    print(f"⚠️ DHT22 Sensor nicht verfügbar: {e}")
    DHT22_AVAILABLE = False

try:
    from src.database.influxdb_client import HeatingInfluxDBClient
    INFLUXDB_AVAILABLE = True
except ImportError as e:
    print(f"⚠️ InfluxDB Client nicht verfügbar: {e}")
    INFLUXDB_AVAILABLE = False

# Python-Bibliotheken prüfen
try:
    from dotenv import load_dotenv
    DOTENV_AVAILABLE = True
except ImportError:
    print("⚠️ python-dotenv nicht verfügbar - verwende Umgebungsvariablen")
    DOTENV_AVAILABLE = False

# Logging konfigurieren
log_file = os.getenv('LOG_FILE', '/var/log/heizung-monitor.log')
log_level = os.getenv('LOG_LEVEL', 'INFO')

# Robuste Log-Datei Konfiguration
log_handlers = []

# Console Handler (immer verfügbar)
log_handlers.append(logging.StreamHandler())

# File Handler (mit Fallback)
try:
    # Prüfe ob Log-Directory existiert und schreibbar ist
    log_dir = os.path.dirname(log_file)
    if log_dir and not os.path.exists(log_dir):
        try:
            os.makedirs(log_dir, exist_ok=True)
        except PermissionError:
            log_file = 'heizung-monitor.log'  # Fallback auf lokales Log
    
    # Teste Schreibberechtigung
    test_file = log_file + '.test'
    try:
        with open(test_file, 'w') as f:
            f.write('test')
        os.remove(test_file)
        # Log-Datei ist schreibbar
        log_handlers.append(logging.FileHandler(log_file))
    except (PermissionError, OSError):
        # Fallback auf lokales Log im Arbeitsverzeichnis
        local_log = 'heizung-monitor.log'
        try:
            log_handlers.append(logging.FileHandler(local_log))
            print(f"⚠️ Verwende lokale Log-Datei: {local_log}")
        except Exception:
            print("⚠️ Nur Console-Logging verfügbar")

except Exception as e:
    print(f"⚠️ Log-Konfiguration Fehler: {e}")

logging.basicConfig(
    level=getattr(logging, log_level.upper(), logging.INFO),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=log_handlers
)

logger = logging.getLogger(__name__)

class HeizungsMonitor:
    """Hauptklasse für die Heizungsüberwachung"""
    
    def __init__(self):
        self.running = False
        self.heating_manager = None
        self.room_sensor = None
        self.influx_client = None
        self.monitoring_interval = int(os.getenv('MONITORING_INTERVAL', 30))
        
        # Signal-Handler für sauberes Beenden
        signal.signal(signal.SIGTERM, self.signal_handler)
        signal.signal(signal.SIGINT, self.signal_handler)
    
    def signal_handler(self, signum, frame):
        """Handler für Shutdown-Signale"""
        logger.info(f"Signal {signum} empfangen - beende Monitor...")
        self.running = False
    
    def initialize(self) -> bool:
        """Initialisiert alle Komponenten"""
        try:
            logger.info("🏠 Heizungsüberwachung wird initialisiert...")
            
            # Verfügbarkeit prüfen
            if not HEATING_AVAILABLE:
                logger.error("❌ Heizungssensoren nicht verfügbar")
                return False
                
            if not INFLUXDB_AVAILABLE:
                logger.error("❌ InfluxDB Client nicht verfügbar")
                return False
            
            # Heizungskreis-Manager
            try:
                self.heating_manager = HeatingSystemManager()
                circuit_count = self.heating_manager.get_circuit_count()
                logger.info(f"✅ {circuit_count} Heizkreise geladen")
            except Exception as e:
                logger.error(f"❌ Fehler beim Laden der Heizkreise: {e}")
                return False
            
            # DHT22 Raumsensor (optional)
            if DHT22_AVAILABLE:
                try:
                    dht_pin = int(os.getenv('DHT22_PIN', 18))
                    self.room_sensor = HeatingRoomSensor(pin=dht_pin)
                    logger.info("✅ DHT22 Raumsensor initialisiert")
                except Exception as e:
                    logger.warning(f"⚠️ DHT22 Sensor Fehler (wird übersprungen): {e}")
                    self.room_sensor = None
            else:
                logger.warning("⚠️ DHT22 nicht verfügbar - wird übersprungen")
                self.room_sensor = None
            
            # InfluxDB Client
            try:
                self.influx_client = HeatingInfluxDBClient()
                logger.info("✅ InfluxDB-Verbindung hergestellt")
            except Exception as e:
                logger.error(f"❌ InfluxDB-Verbindung fehlgeschlagen: {e}")
                return False
            
            return True
            
        except Exception as e:
            logger.error(f"❌ Unerwarteter Fehler bei Initialisierung: {e}")
            return False
    
    def run_monitoring_cycle(self):
        """Führt einen Monitoring-Zyklus aus"""
        try:
            timestamp = datetime.utcnow()
            
            # 1. Heizungskreise überwachen
            logger.debug("Lese Heizungskreis-Daten...")
            
            try:
                all_temps = self.heating_manager.get_all_temperatures()
                system_status = self.heating_manager.get_system_status()
                
                # Daten zu InfluxDB senden
                for circuit_name, temps in all_temps.items():
                    circuit = self.heating_manager.get_circuit_by_name(circuit_name)
                    if circuit and temps['flow'] is not None and temps['return'] is not None:
                        try:
                            self.influx_client.write_circuit_data(
                                circuit=circuit,
                                flow_temp=temps['flow'],
                                return_temp=temps['return'],
                                timestamp=timestamp
                            )
                        except Exception as e:
                            logger.error(f"❌ Fehler beim Schreiben der Kreisdaten {circuit_name}: {e}")
                
                # System-Status schreiben
                try:
                    self.influx_client.write_system_status(
                        total_circuits=system_status['total_circuits'],
                        active_circuits=system_status['active_circuits'],
                        system_efficiency=system_status['system_efficiency'],
                        alerts=system_status['alerts'],
                        timestamp=timestamp
                    )
                except Exception as e:
                    logger.error(f"❌ Fehler beim Schreiben des System-Status: {e}")
                    
            except Exception as e:
                logger.error(f"❌ Fehler beim Lesen der Heizungskreise: {e}")
                # Dummy-Status für Debugging
                system_status = {
                    'total_circuits': 0,
                    'active_circuits': 0,
                    'system_efficiency': 0.0,
                    'alerts': [{'type': 'error', 'message': f'Sensor-Fehler: {e}'}]
                }
            
            # 2. Raumsensor überwachen (optional)
            room_conditions = {'temperature': None, 'humidity': None, 'dew_point': None}
            
            if self.room_sensor:
                try:
                    logger.debug("Lese Raumsensor-Daten...")
                    room_conditions = self.room_sensor.check_heating_room_conditions()
                    
                    if room_conditions['temperature'] is not None:
                        self.influx_client.write_room_conditions(
                            temperature=room_conditions['temperature'],
                            humidity=room_conditions['humidity'],
                            dew_point=room_conditions['dew_point'],
                            timestamp=timestamp
                        )
                except Exception as e:
                    logger.warning(f"⚠️ Raumsensor-Fehler (wird übersprungen): {e}")
            
            # Status-Log
            active_circuits = system_status.get('active_circuits', 0)
            total_circuits = system_status.get('total_circuits', 0)
            efficiency = system_status.get('system_efficiency', 0.0)
            room_temp = room_conditions.get('temperature', 'N/A')
            
            logger.info(f"📊 Status: {active_circuits}/{total_circuits} Kreise aktiv, "
                       f"Effizienz: {efficiency:.1f}%, Raum: {room_temp}°C")
            
            # Alarme loggen
            if system_status.get('alerts'):
                for alert in system_status['alerts']:
                    logger.warning(f"⚠️ {alert['type'].upper()}: {alert['message']}")
            
        except Exception as e:
            logger.error(f"❌ Kritischer Fehler im Monitoring-Zyklus: {e}")
            # Nicht beenden - versuche weiter
    
    def run(self):
        """Startet das kontinuierliche Monitoring"""
        if not self.initialize():
            sys.exit(1)
        
        logger.info(f"🚀 Monitoring gestartet (Intervall: {self.monitoring_interval}s)")
        self.running = True
        
        try:
            while self.running:
                cycle_start = time.time()
                
                self.run_monitoring_cycle()
                
                # Warten bis zum nächsten Zyklus
                cycle_duration = time.time() - cycle_start
                sleep_time = max(0, self.monitoring_interval - cycle_duration)
                
                if sleep_time > 0:
                    time.sleep(sleep_time)
                else:
                    logger.warning(f"⚠️ Monitoring-Zyklus dauerte {cycle_duration:.1f}s "
                                 f"(länger als Intervall {self.monitoring_interval}s)")
        
        except KeyboardInterrupt:
            logger.info("Monitoring durch Benutzer beendet")
        
        finally:
            self.cleanup()
    
    def cleanup(self):
        """Cleanup-Ressourcen"""
        logger.info("🧹 Cleanup-Ressourcen...")
        
        if self.room_sensor:
            self.room_sensor.cleanup()
        
        if self.influx_client:
            self.influx_client.close()
        
        logger.info("✅ Heizungsüberwachung beendet")

def main():
    """Hauptfunktion"""
    try:
        # Umgebungsvariablen laden
        if DOTENV_AVAILABLE:
            load_dotenv()
        
        # Grundlegende Systemprüfungen
        logger.info("🔍 Systemprüfungen...")
        
        # Python-Version prüfen
        python_version = sys.version_info
        logger.info(f"🐍 Python {python_version.major}.{python_version.minor}.{python_version.micro}")
        
        # Verfügbarkeit der Module loggen
        logger.info(f"📦 Module - Heizung: {HEATING_AVAILABLE}, DHT22: {DHT22_AVAILABLE}, InfluxDB: {INFLUXDB_AVAILABLE}")
        
        # Mindestanforderungen prüfen
        if not HEATING_AVAILABLE or not INFLUXDB_AVAILABLE:
            logger.error("❌ Kritische Module fehlen - System kann nicht gestartet werden")
            logger.error("💡 Versuche: pip install -r requirements.txt")
            sys.exit(1)
        
        # Monitor starten
        monitor = HeizungsMonitor()
        monitor.run()
        
    except KeyboardInterrupt:
        logger.info("👋 Programm durch Benutzer beendet")
        sys.exit(0)
    except Exception as e:
        logger.error(f"💥 Kritischer Fehler in main(): {e}")
        logger.error("📝 Prüfe Logs und Konfiguration")
        sys.exit(1)

if __name__ == "__main__":
    main()
