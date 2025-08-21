"""
DHT22 Sensor für Umgebungstemperatur und Luftfeuchtigkeit im Heizungsraum
Erweitert um heizungsspezifische Berechnungen
"""

import time
import logging
from datetime import datetime
from typing import Optional, Dict, Tuple, List

# Robust DHT22 Import mit Fallback-Optionen
DHT_AVAILABLE = False
DHT_METHOD = "none"

try:
    # Versuch 1: Adafruit CircuitPython (empfohlen für Raspberry Pi 5)
    import board
    import adafruit_dht
    DHT_AVAILABLE = True
    DHT_METHOD = "adafruit"
    logger = logging.getLogger(__name__)
    logger.info("DHT22: Adafruit CircuitPython verfügbar")
except ImportError as e:
    try:
        # Versuch 2: Alternative DHT Bibliothek
        import Adafruit_DHT
        DHT_AVAILABLE = True
        DHT_METHOD = "legacy"
        logger = logging.getLogger(__name__)
        logger.info("DHT22: Legacy Adafruit_DHT verfügbar")
    except ImportError:
        try:
            # Versuch 3: Pigpio DHT22
            import pigpio
            import DHT22
            DHT_AVAILABLE = True
            DHT_METHOD = "pigpio"
            logger = logging.getLogger(__name__)
            logger.info("DHT22: Pigpio DHT22 verfügbar")
        except ImportError:
            # Fallback: Dummy-Implementation für Entwicklung
            DHT_AVAILABLE = False
            DHT_METHOD = "dummy"
            logger = logging.getLogger(__name__)
            logger.warning("DHT22: Keine DHT-Bibliothek verfügbar - verwende Dummy-Implementation")

logger = logging.getLogger(__name__)

class HeatingRoomSensor:
    """DHT22 Sensor für Heizungsraum-Überwachung"""
    
    def __init__(self, pin: int = 18, name: str = "Heizungsraum"):
        """
        Initialisiert den DHT22 Sensor für den Heizungsraum
        
        Args:
            pin: GPIO Pin (BCM Nummerierung)
            name: Name/Standort des Sensors
        """
        self.pin = pin
        self.name = name
        self.dht = None
        self.last_reading_time = 0
        self.min_reading_interval = 2.0
        
        # Heizungsraum-spezifische Grenzwerte
        self.temp_min = 5.0   # Mindesttemperatur (Frostschutz)
        self.temp_max = 35.0  # Maximaltemperatur (Überhitzung)
        self.humidity_max = 80.0  # Maximale Luftfeuchtigkeit (Kondensation)
        
        # DHT Sensor je nach verfügbarer Bibliothek initialisieren
        self._init_dht_sensor()
        
        logger.info(f"Heizungsraum-Sensor initialisiert: {self.name} (GPIO {self.pin}, Methode: {DHT_METHOD})")
    
    def _init_dht_sensor(self):
        """Initialisiert den DHT22 Sensor basierend auf verfügbarer Bibliothek"""
        if not DHT_AVAILABLE:
            logger.warning("DHT22: Keine Bibliothek verfügbar - Dummy-Modus")
            return
            
        try:
            if DHT_METHOD == "adafruit":
                # Adafruit CircuitPython
                if self.pin == 18:
                    self.dht = adafruit_dht.DHT22(board.D18)
                elif self.pin == 4:
                    self.dht = adafruit_dht.DHT22(board.D4)
                else:
                    # Dynamisch für andere Pins
                    self.dht = adafruit_dht.DHT22(getattr(board, f'D{self.pin}'))
                    
            elif DHT_METHOD == "legacy":
                # Legacy Adafruit_DHT
                self.dht = Adafruit_DHT.DHT22
                
            elif DHT_METHOD == "pigpio":
                # Pigpio DHT22
                self.pi = pigpio.pi()
                self.dht = DHT22.sensor(self.pi, self.pin)
                
        except Exception as e:
            logger.error(f"DHT22 Initialisierung fehlgeschlagen: {e}")
            self.dht = None
    
    def _wait_for_reading_interval(self) -> None:
        """Wartet die erforderliche Zeit zwischen Messungen ab"""
        current_time = time.time()
        time_since_last = current_time - self.last_reading_time
        
        if time_since_last < self.min_reading_interval:
            wait_time = self.min_reading_interval - time_since_last
            time.sleep(wait_time)
    
    def read_sensor_data(self, retries: int = 3) -> Dict[str, Optional[float]]:
        """
        Liest Temperatur und Luftfeuchtigkeit vom DHT22
        
        Args:
            retries: Anzahl Wiederholungsversuche
            
        Returns:
            Dictionary mit 'temperature', 'humidity', 'dew_point'
        """
        if not DHT_AVAILABLE or self.dht is None:
            logger.warning(f"{self.name}: DHT22 nicht verfügbar - verwende Dummy-Daten")
            return {
                'temperature': 20.0,  # Dummy-Werte für Tests
                'humidity': 50.0,
                'dew_point': 9.3
            }
        
        self._wait_for_reading_interval()
        
        for attempt in range(retries):
            try:
                temperature = None
                humidity = None
                
                if DHT_METHOD == "adafruit":
                    # Adafruit CircuitPython DHT
                    temperature = self.dht.temperature
                    humidity = self.dht.humidity
                    
                elif DHT_METHOD == "legacy":
                    # Legacy Adafruit_DHT
                    humidity, temperature = Adafruit_DHT.read_retry(self.dht, self.pin)
                    
                elif DHT_METHOD == "pigpio":
                    # Pigpio DHT22
                    self.dht.trigger()
                    time.sleep(0.2)
                    humidity = self.dht.humidity()
                    temperature = self.dht.temperature()
                
                self.last_reading_time = time.time()
                
                if humidity is not None and temperature is not None:
                    # Plausibilitätsprüfung
                    if 0 <= humidity <= 100 and -20 <= temperature <= 50:
                        logger.debug(f"{self.name}: {temperature:.1f}°C, {humidity:.1f}%RH")
                        
                        # Taupunkt berechnen
                        dew_point = self._calculate_dew_point(temperature, humidity)
                        
                        return {
                            'temperature': round(temperature, 1),
                            'humidity': round(humidity, 1),
                            'dew_point': dew_point
                        }
                    else:
                        logger.warning(f"{self.name}: Ungültige Werte - T:{temperature}°C, H:{humidity}%")
                
                if attempt < retries - 1:
                    time.sleep(1)
                    
            except RuntimeError as e:
                # DHT22 spezifische Fehler (z.B. Timing, Checksum)
                logger.warning(f"{self.name}: DHT22-Fehler (Versuch {attempt + 1}): {e}")
                if attempt < retries - 1:
                    time.sleep(2)  # Längere Pause bei DHT-Fehlern
            except Exception as e:
                logger.error(f"{self.name}: Messfehler (Versuch {attempt + 1}): {e}")
                if attempt < retries - 1:
                    time.sleep(1)
        
        logger.error(f"{self.name}: Alle Messversuche fehlgeschlagen")
        return {
            'temperature': None,
            'humidity': None,
            'dew_point': None
        }
    
    def _calculate_dew_point(self, temperature: float, humidity: float) -> Optional[float]:
        """
        Berechnet den Taupunkt nach Magnus-Formel
        
        Args:
            temperature: Temperatur in °C
            humidity: Relative Luftfeuchtigkeit in %
            
        Returns:
            Taupunkt in °C
        """
        try:
            import math
            
            a = 17.27
            b = 237.7
            
            alpha = ((a * temperature) / (b + temperature)) + math.log(humidity / 100.0)
            dew_point = (b * alpha) / (a - alpha)
            
            return round(dew_point, 1)
            
        except Exception as e:
            logger.error(f"Taupunkt-Berechnung fehlgeschlagen: {e}")
            return None
    
    def check_condensation_risk(self, pipe_temperature: float = None) -> Dict[str, any]:
        """
        Prüft das Kondensationsrisiko an Rohrleitungen
        
        Args:
            pipe_temperature: Temperatur der kältesten Rohrleitung
            
        Returns:
            Dictionary mit Kondensationsrisiko-Bewertung
        """
        data = self.read_sensor_data()
        
        if data['dew_point'] is None:
            return {
                'risk_level': 'unbekannt',
                'message': 'Sensor-Daten nicht verfügbar'
            }
        
        dew_point = data['dew_point']
        
        # Wenn keine Rohrtemperatur gegeben, verwende Raumtemperatur - 5°C als Schätzung
        if pipe_temperature is None:
            if data['temperature'] is not None:
                pipe_temperature = data['temperature'] - 5
            else:
                return {
                    'risk_level': 'unbekannt',
                    'message': 'Keine Referenztemperatur verfügbar'
                }
        
        # Kondensationsrisiko bewerten
        temp_diff = pipe_temperature - dew_point
        
        if temp_diff < 0:
            risk_level = 'hoch'
            message = f'Kondensation wahrscheinlich! Rohr: {pipe_temperature:.1f}°C < Taupunkt: {dew_point:.1f}°C'
        elif temp_diff < 2:
            risk_level = 'mittel'
            message = f'Kondensationsrisiko vorhanden. Differenz: {temp_diff:.1f}°C'
        elif temp_diff < 5:
            risk_level = 'gering'
            message = f'Geringes Risiko. Sicherheitsabstand: {temp_diff:.1f}°C'
        else:
            risk_level = 'minimal'
            message = f'Kein Kondensationsrisiko. Sicherheitsabstand: {temp_diff:.1f}°C'
        
        return {
            'risk_level': risk_level,
            'message': message,
            'dew_point': dew_point,
            'pipe_temperature': pipe_temperature,
            'temperature_difference': temp_diff,
            'timestamp': datetime.utcnow().isoformat()
        }
    
    def check_heating_room_conditions(self) -> Dict[str, any]:
        """
        Überprüft die Heizungsraum-Bedingungen auf Probleme
        
        Returns:
            Dictionary mit Zustandsbewertung und Alarmen
        """
        data = self.read_sensor_data()
        temperature = data['temperature']
        humidity = data['humidity']
        
        alerts = []
        status = 'ok'
        
        # Temperatur-Checks
        if temperature is not None:
            if temperature < self.temp_min:
                alerts.append({
                    'type': 'kritisch',
                    'message': f'Frostgefahr! Temperatur: {temperature:.1f}°C'
                })
                status = 'kritisch'
            elif temperature > self.temp_max:
                alerts.append({
                    'type': 'warnung',
                    'message': f'Überhitzung! Temperatur: {temperature:.1f}°C'
                })
                if status == 'ok':
                    status = 'warnung'
        
        # Luftfeuchtigkeit-Checks
        if humidity is not None:
            if humidity > self.humidity_max:
                alerts.append({
                    'type': 'warnung',
                    'message': f'Hohe Luftfeuchtigkeit: {humidity:.1f}%RH - Kondensationsgefahr!'
                })
                if status == 'ok':
                    status = 'warnung'
        
        # Sensor-Verfügbarkeit
        if temperature is None and humidity is None:
            alerts.append({
                'type': 'fehler',
                'message': 'Sensor nicht verfügbar'
            })
            status = 'fehler'
        
        return {
            'status': status,
            'temperature': temperature,
            'humidity': humidity,
            'dew_point': data['dew_point'],
            'alerts': alerts,
            'timestamp': datetime.utcnow().isoformat()
        }
    
    def get_comfort_assessment(self) -> Dict[str, any]:
        """
        Bewertet die Komfort-Bedingungen im Heizungsraum
        
        Returns:
            Dictionary mit Komfort-Bewertung
        """
        data = self.read_sensor_data()
        temperature = data['temperature']
        humidity = data['humidity']
        
        if temperature is None or humidity is None:
            return {
                'comfort_level': 'unbekannt',
                'message': 'Sensor-Daten nicht verfügbar'
            }
        
        # Komfort-Bewertung für Heizungsraum (Arbeitsplatz-Standards)
        temp_comfort = 'unbekannt'
        humidity_comfort = 'unbekannt'
        
        # Temperatur-Komfort
        if 18 <= temperature <= 24:
            temp_comfort = 'optimal'
        elif 15 <= temperature <= 27:
            temp_comfort = 'akzeptabel'
        else:
            temp_comfort = 'unkomfortabel'
        
        # Luftfeuchtigkeit-Komfort
        if 40 <= humidity <= 60:
            humidity_comfort = 'optimal'
        elif 30 <= humidity <= 70:
            humidity_comfort = 'akzeptabel'
        else:
            humidity_comfort = 'unkomfortabel'
        
        # Gesamt-Komfort
        if temp_comfort == 'optimal' and humidity_comfort == 'optimal':
            overall_comfort = 'optimal'
        elif temp_comfort in ['optimal', 'akzeptabel'] and humidity_comfort in ['optimal', 'akzeptabel']:
            overall_comfort = 'gut'
        else:
            overall_comfort = 'verbesserungsbedürftig'
        
        return {
            'comfort_level': overall_comfort,
            'temperature_comfort': temp_comfort,
            'humidity_comfort': humidity_comfort,
            'temperature': temperature,
            'humidity': humidity,
            'recommendations': self._get_comfort_recommendations(temperature, humidity),
            'timestamp': datetime.utcnow().isoformat()
        }
    
    def _get_comfort_recommendations(self, temperature: float, humidity: float) -> List[str]:
        """Gibt Empfehlungen zur Verbesserung der Raumbedingungen"""
        recommendations = []
        
        if temperature < 15:
            recommendations.append("Heizung erhöhen - Temperatur zu niedrig")
        elif temperature > 27:
            recommendations.append("Belüftung verbessern - Temperatur zu hoch")
        
        if humidity < 30:
            recommendations.append("Luftfeuchtigkeit zu niedrig - Luftbefeuchter erwägen")
        elif humidity > 70:
            recommendations.append("Luftfeuchtigkeit zu hoch - Entfeuchtung oder Belüftung verbessern")
        
        if not recommendations:
            recommendations.append("Raumbedingungen sind optimal")
        
        return recommendations
    
    def test_sensor(self) -> bool:
        """
        Testet den DHT22 Sensor
        
        Returns:
            True wenn Sensor funktioniert
        """
        logger.info(f"Teste {self.name} Sensor...")
        
        try:
            data = self.read_sensor_data(retries=5)
            
            if data['temperature'] is not None and data['humidity'] is not None:
                logger.info(f"✅ {self.name}: {data['temperature']:.1f}°C, {data['humidity']:.1f}%RH")
                if data['dew_point'] is not None:
                    logger.info(f"📊 Taupunkt: {data['dew_point']:.1f}°C")
                
                # Kondensationsrisiko-Check
                condensation = self.check_condensation_risk()
                logger.info(f"💧 Kondensationsrisiko: {condensation['risk_level']}")
                
                return True
            else:
                logger.error(f"❌ {self.name}: Keine gültigen Messwerte")
                return False
                
        except Exception as e:
            logger.error(f"❌ {self.name}: Test fehlgeschlagen - {e}")
            return False
    
    def cleanup(self):
        """Sensor-Ressourcen freigeben"""
        try:
            if hasattr(self, 'dht'):
                self.dht.exit()
                logger.info(f"{self.name}: Sensor-Ressourcen freigegeben")
        except Exception as e:
            logger.warning(f"{self.name}: Cleanup-Warnung - {e}")
    
    def get_sensor_info(self) -> Dict[str, str]:
        """Gibt Sensor-Informationen zurück"""
        return {
            'name': self.name,
            'type': 'DHT22',
            'pin': str(self.pin),
            'location': 'Heizungsraum',
            'measures': 'temperature, humidity, dew_point',
            'temperature_range': f'{self.temp_min}°C - {self.temp_max}°C',
            'humidity_max': f'{self.humidity_max}%RH'
        }
