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

from src.sensors.heating_sensors import HeatingSystemManager
from src.sensors.dht22_sensor import HeatingRoomSensor
from src.database.influxdb_client import HeatingInfluxDBClient

# Logging konfigurieren
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/heizung-monitor.log'),
        logging.StreamHandler()
    ]
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
            
            # Heizungskreis-Manager
            self.heating_manager = HeatingSystemManager()
            logger.info(f"✅ {self.heating_manager.get_circuit_count()} Heizkreise geladen")
            
            # DHT22 Raumsensor
            dht_pin = int(os.getenv('DHT22_PIN', 18))
            self.room_sensor = HeatingRoomSensor(pin=dht_pin)
            logger.info("✅ DHT22 Raumsensor initialisiert")
            
            # InfluxDB Client
            self.influx_client = HeatingInfluxDBClient()
            logger.info("✅ InfluxDB-Verbindung hergestellt")
            
            return True
            
        except Exception as e:
            logger.error(f"❌ Initialisierung fehlgeschlagen: {e}")
            return False
    
    def run_monitoring_cycle(self):
        """Führt einen Monitoring-Zyklus aus"""
        try:
            timestamp = datetime.utcnow()
            
            # 1. Heizungskreise überwachen
            logger.debug("Lese Heizungskreis-Daten...")
            all_temps = self.heating_manager.get_all_temperatures()
            system_status = self.heating_manager.get_system_status()
            
            # Daten zu InfluxDB senden
            for circuit_name, temps in all_temps.items():
                circuit = self.heating_manager.get_circuit_by_name(circuit_name)
                if circuit and temps['flow'] is not None and temps['return'] is not None:
                    self.influx_client.write_circuit_data(
                        circuit=circuit,
                        flow_temp=temps['flow'],
                        return_temp=temps['return'],
                        timestamp=timestamp
                    )
            
            # System-Status schreiben
            self.influx_client.write_system_status(
                total_circuits=system_status['total_circuits'],
                active_circuits=system_status['active_circuits'],
                system_efficiency=system_status['system_efficiency'],
                alerts=system_status['alerts'],
                timestamp=timestamp
            )
            
            # 2. Raumsensor überwachen
            logger.debug("Lese Raumsensor-Daten...")
            room_conditions = self.room_sensor.check_heating_room_conditions()
            
            if room_conditions['temperature'] is not None:
                self.influx_client.write_room_conditions(
                    temperature=room_conditions['temperature'],
                    humidity=room_conditions['humidity'],
                    dew_point=room_conditions['dew_point'],
                    timestamp=timestamp
                )
            
            # Status-Log
            active_circuits = system_status['active_circuits']
            total_circuits = system_status['total_circuits']
            efficiency = system_status['system_efficiency']
            room_temp = room_conditions['temperature']
            
            logger.info(f"📊 Status: {active_circuits}/{total_circuits} Kreise aktiv, "
                       f"Effizienz: {efficiency:.1f}%, Raum: {room_temp:.1f}°C")
            
            # Alarme loggen
            if system_status['alerts']:
                for alert in system_status['alerts']:
                    logger.warning(f"⚠️ {alert['type'].upper()}: {alert['message']}")
            
        except Exception as e:
            logger.error(f"❌ Fehler im Monitoring-Zyklus: {e}")
    
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
    # Umgebungsvariablen laden
    from dotenv import load_dotenv
    load_dotenv()
    
    # Monitor starten
    monitor = HeizungsMonitor()
    monitor.run()

if __name__ == "__main__":
    main()
