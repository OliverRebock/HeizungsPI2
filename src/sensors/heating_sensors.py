"""
Heizungskreis-spezifische Sensor-Logik
Verwaltet DS18B20 Sensoren für Vor- und Rückläufe der Heizungskreise
"""

import time
import logging
import yaml
from datetime import datetime
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from w1thermsensor import W1ThermSensor, Sensor

logger = logging.getLogger(__name__)

@dataclass
class HeatingCircuit:
    """Repräsentiert einen Heizungskreis mit Vor- und Rücklauf"""
    name: str
    flow_sensor_id: str
    return_sensor_id: str
    target_temp: float
    flow_sensor: Optional[W1ThermSensor] = None
    return_sensor: Optional[W1ThermSensor] = None
    
    def __post_init__(self):
        """Initialisiert die Sensoren nach der Erstellung"""
        self._initialize_sensors()
    
    def _initialize_sensors(self) -> None:
        """Initialisiert die DS18B20 Sensoren für diesen Heizkreis"""
        try:
            available_sensors = W1ThermSensor.get_available_sensors([Sensor.DS18B20])
            
            # Vorlauf-Sensor finden
            for sensor in available_sensors:
                if sensor.id == self.flow_sensor_id:
                    self.flow_sensor = sensor
                    logger.info(f"Vorlauf-Sensor für {self.name} gefunden: {self.flow_sensor_id}")
                    break
            else:
                logger.warning(f"Vorlauf-Sensor {self.flow_sensor_id} für {self.name} nicht gefunden")
            
            # Rücklauf-Sensor finden
            for sensor in available_sensors:
                if sensor.id == self.return_sensor_id:
                    self.return_sensor = sensor
                    logger.info(f"Rücklauf-Sensor für {self.name} gefunden: {self.return_sensor_id}")
                    break
            else:
                logger.warning(f"Rücklauf-Sensor {self.return_sensor_id} für {self.name} nicht gefunden")
                
        except Exception as e:
            logger.error(f"Fehler beim Initialisieren der Sensoren für {self.name}: {e}")
    
    def read_temperatures(self) -> Tuple[Optional[float], Optional[float]]:
        """
        Liest Vor- und Rücklauf-Temperaturen
        
        Returns:
            Tuple (Vorlauf-Temperatur, Rücklauf-Temperatur)
        """
        flow_temp = None
        return_temp = None
        
        # Vorlauf-Temperatur lesen
        if self.flow_sensor:
            try:
                flow_temp = round(self.flow_sensor.get_temperature(), 2)
                logger.debug(f"{self.name} Vorlauf: {flow_temp}°C")
            except Exception as e:
                logger.error(f"Fehler beim Lesen des Vorlauf-Sensors {self.name}: {e}")
        
        # Kurze Pause zwischen Sensoren
        time.sleep(0.1)
        
        # Rücklauf-Temperatur lesen
        if self.return_sensor:
            try:
                return_temp = round(self.return_sensor.get_temperature(), 2)
                logger.debug(f"{self.name} Rücklauf: {return_temp}°C")
            except Exception as e:
                logger.error(f"Fehler beim Lesen des Rücklauf-Sensors {self.name}: {e}")
        
        return flow_temp, return_temp
    
    def calculate_temperature_difference(self) -> Optional[float]:
        """
        Berechnet die Temperaturdifferenz zwischen Vor- und Rücklauf
        
        Returns:
            Temperaturdifferenz in °C oder None bei Fehlern
        """
        flow_temp, return_temp = self.read_temperatures()
        
        if flow_temp is not None and return_temp is not None:
            diff = round(flow_temp - return_temp, 2)
            logger.debug(f"{self.name} Temperaturdifferenz: {diff}°C")
            return diff
        
        return None
    
    def is_active(self) -> bool:
        """
        Prüft ob der Heizkreis aktiv ist (Temperaturdifferenz > 2°C)
        
        Returns:
            True wenn Heizkreis aktiv ist
        """
        diff = self.calculate_temperature_difference()
        return diff is not None and diff > 2.0
    
    def get_efficiency_rating(self) -> Optional[str]:
        """
        Bewertet die Effizienz des Heizkreises basierend auf der Temperaturdifferenz
        
        Returns:
            Effizienz-Rating: "sehr_gut", "gut", "befriedigend", "schlecht"
        """
        diff = self.calculate_temperature_difference()
        
        if diff is None:
            return None
        
        if diff >= 15:
            return "sehr_gut"
        elif diff >= 10:
            return "gut"
        elif diff >= 5:
            return "befriedigend"
        else:
            return "schlecht"
    
    def is_available(self) -> bool:
        """Prüft ob beide Sensoren verfügbar sind"""
        return self.flow_sensor is not None and self.return_sensor is not None
    
    def get_status(self) -> Dict[str, any]:
        """Gibt den aktuellen Status des Heizkreises zurück"""
        flow_temp, return_temp = self.read_temperatures()
        diff = self.calculate_temperature_difference()
        
        return {
            'name': self.name,
            'flow_temperature': flow_temp,
            'return_temperature': return_temp,
            'temperature_difference': diff,
            'is_active': self.is_active(),
            'efficiency_rating': self.get_efficiency_rating(),
            'target_temperature': self.target_temp,
            'sensors_available': self.is_available(),
            'timestamp': datetime.utcnow().isoformat()
        }


class HeatingSystemManager:
    """Verwaltet alle Heizungskreise des Systems"""
    
    def __init__(self, config_file: str = 'config/heating_circuits.yaml'):
        """
        Initialisiert den Heizungsmanager
        
        Args:
            config_file: Pfad zur Konfigurationsdatei
        """
        self.config_file = config_file
        self.heating_circuits: List[HeatingCircuit] = []
        self._load_configuration()
    
    def _load_configuration(self) -> None:
        """Lädt die Heizungskreis-Konfiguration aus YAML-Datei"""
        try:
            with open(self.config_file, 'r', encoding='utf-8') as file:
                config = yaml.safe_load(file)
            
            circuits_config = config.get('heating_circuits', {})
            
            for circuit_id, circuit_config in circuits_config.items():
                heating_circuit = HeatingCircuit(
                    name=circuit_config['name'],
                    flow_sensor_id=circuit_config['flow_sensor'],
                    return_sensor_id=circuit_config['return_sensor'],
                    target_temp=circuit_config['target_temp']
                )
                
                self.heating_circuits.append(heating_circuit)
                logger.info(f"Heizkreis geladen: {heating_circuit.name}")
            
            logger.info(f"{len(self.heating_circuits)} Heizungskreise konfiguriert")
            
        except FileNotFoundError:
            logger.error(f"Konfigurationsdatei nicht gefunden: {self.config_file}")
            logger.info("Erstelle Beispiel-Konfiguration...")
            self._create_example_config()
        except Exception as e:
            logger.error(f"Fehler beim Laden der Konfiguration: {e}")
    
    def _create_example_config(self) -> None:
        """Erstellt eine Beispiel-Konfigurationsdatei"""
        example_config = {
            'heating_circuits': {
                'erdgeschoss': {
                    'name': 'Erdgeschoss',
                    'flow_sensor': '28-0000000001',
                    'return_sensor': '28-0000000002',
                    'target_temp': 21.0
                },
                'obergeschoss': {
                    'name': 'Obergeschoss',
                    'flow_sensor': '28-0000000003',
                    'return_sensor': '28-0000000004',
                    'target_temp': 20.0
                },
                'warmwasser': {
                    'name': 'Warmwasser',
                    'flow_sensor': '28-0000000005',
                    'return_sensor': '28-0000000006',
                    'target_temp': 45.0
                }
            }
        }
        
        try:
            import os
            os.makedirs(os.path.dirname(self.config_file), exist_ok=True)
            
            with open(self.config_file, 'w', encoding='utf-8') as file:
                yaml.dump(example_config, file, default_flow_style=False, allow_unicode=True)
            
            logger.info(f"Beispiel-Konfiguration erstellt: {self.config_file}")
            logger.info("Bitte passe die Sensor-IDs an deine Hardware an!")
            
        except Exception as e:
            logger.error(f"Fehler beim Erstellen der Beispiel-Konfiguration: {e}")
    
    def get_all_temperatures(self) -> Dict[str, Dict[str, Optional[float]]]:
        """
        Liest alle Temperaturen aller Heizungskreise
        
        Returns:
            Dictionary mit Temperaturdaten aller Kreise
        """
        all_temperatures = {}
        
        for circuit in self.heating_circuits:
            flow_temp, return_temp = circuit.read_temperatures()
            
            all_temperatures[circuit.name] = {
                'flow': flow_temp,
                'return': return_temp,
                'difference': circuit.calculate_temperature_difference()
            }
            
            # Kurze Pause zwischen Heizkreisen
            time.sleep(0.2)
        
        return all_temperatures
    
    def get_system_status(self) -> Dict[str, any]:
        """Gibt den Status des gesamten Heizungssystems zurück"""
        circuit_statuses = []
        active_circuits = 0
        total_circuits = len(self.heating_circuits)
        available_circuits = 0
        
        for circuit in self.heating_circuits:
            status = circuit.get_status()
            circuit_statuses.append(status)
            
            if status['is_active']:
                active_circuits += 1
            
            if status['sensors_available']:
                available_circuits += 1
        
        return {
            'timestamp': datetime.utcnow().isoformat(),
            'total_circuits': total_circuits,
            'available_circuits': available_circuits,
            'active_circuits': active_circuits,
            'circuits': circuit_statuses,
            'system_efficiency': self._calculate_system_efficiency(),
            'alerts': self._check_alerts()
        }
    
    def _calculate_system_efficiency(self) -> Optional[float]:
        """
        Berechnet die Gesamteffizienz des Heizungssystems
        
        Returns:
            Effizienz-Wert zwischen 0 und 100
        """
        total_diff = 0
        active_circuits = 0
        
        for circuit in self.heating_circuits:
            diff = circuit.calculate_temperature_difference()
            if diff is not None and diff > 2:  # Nur aktive Kreise
                total_diff += diff
                active_circuits += 1
        
        if active_circuits == 0:
            return None
        
        avg_diff = total_diff / active_circuits
        
        # Effizienz basierend auf durchschnittlicher Temperaturdifferenz
        # 15°C+ = 100%, 5°C = 33%, linear interpoliert
        efficiency = min(100, max(0, (avg_diff - 5) / 10 * 67 + 33))
        
        return round(efficiency, 1)
    
    def _check_alerts(self) -> List[Dict[str, str]]:
        """
        Prüft auf Alarm-Bedingungen im Heizungssystem
        
        Returns:
            Liste von Alarmen
        """
        alerts = []
        
        for circuit in self.heating_circuits:
            flow_temp, return_temp = circuit.read_temperatures()
            diff = circuit.calculate_temperature_difference()
            
            # Überhitzung prüfen
            if flow_temp is not None and flow_temp > 80:
                alerts.append({
                    'type': 'kritisch',
                    'circuit': circuit.name,
                    'message': f'Überhitzung: Vorlauf {flow_temp}°C',
                    'timestamp': datetime.utcnow().isoformat()
                })
            
            # Schlechte Effizienz prüfen
            if diff is not None and diff < 3 and flow_temp is not None and flow_temp > 30:
                alerts.append({
                    'type': 'warnung',
                    'circuit': circuit.name,
                    'message': f'Geringe Effizienz: nur {diff}°C Temperaturdifferenz',
                    'timestamp': datetime.utcnow().isoformat()
                })
            
            # Sensor-Ausfall prüfen
            if not circuit.is_available():
                alerts.append({
                    'type': 'fehler',
                    'circuit': circuit.name,
                    'message': 'Sensor-Ausfall erkannt',
                    'timestamp': datetime.utcnow().isoformat()
                })
        
        return alerts
    
    def test_all_circuits(self) -> bool:
        """
        Testet alle Heizungskreise
        
        Returns:
            True wenn alle Tests erfolgreich
        """
        logger.info("Teste alle Heizungskreise...")
        
        overall_success = True
        
        for circuit in self.heating_circuits:
            logger.info(f"\nTeste {circuit.name}:")
            
            if not circuit.is_available():
                logger.error(f"❌ Sensoren nicht verfügbar für {circuit.name}")
                overall_success = False
                continue
            
            flow_temp, return_temp = circuit.read_temperatures()
            
            if flow_temp is not None:
                logger.info(f"✅ Vorlauf: {flow_temp}°C")
            else:
                logger.error(f"❌ Vorlauf-Sensor defekt")
                overall_success = False
            
            if return_temp is not None:
                logger.info(f"✅ Rücklauf: {return_temp}°C")
            else:
                logger.error(f"❌ Rücklauf-Sensor defekt")
                overall_success = False
            
            diff = circuit.calculate_temperature_difference()
            if diff is not None:
                logger.info(f"📊 Temperaturdifferenz: {diff}°C")
                logger.info(f"🏆 Effizienz: {circuit.get_efficiency_rating()}")
            
            # Kurze Pause zwischen Tests
            time.sleep(1)
        
        if overall_success:
            logger.info("\n✅ Alle Heizungskreise funktionieren korrekt!")
        else:
            logger.error("\n❌ Einige Heizungskreise haben Probleme!")
        
        return overall_success
    
    def get_circuit_by_name(self, name: str) -> Optional[HeatingCircuit]:
        """Gibt einen Heizkreis anhand des Namens zurück"""
        for circuit in self.heating_circuits:
            if circuit.name.lower() == name.lower():
                return circuit
        return None
    
    def get_circuit_count(self) -> int:
        """Gibt die Anzahl der konfigurierten Heizkreise zurück"""
        return len(self.heating_circuits)
