"""
InfluxDB Client speziell für Heizungsüberwachung
Optimiert für Heizungskreis-Daten, Effizienz-Metriken und Grafana-Integration
"""

import logging
from datetime import datetime
from typing import Dict, List, Optional, Any
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS
from influxdb_client.client.exceptions import InfluxDBError

logger = logging.getLogger(__name__)

class HeatingInfluxDBClient:
    """InfluxDB Client für Heizungsüberwachung"""
    
    def __init__(self, url: str, token: str, org: str, bucket: str):
        """
        Initialisiert den InfluxDB Client für Heizungsdaten
        
        Args:
            url: InfluxDB Server URL
            token: Authentifizierung Token
            org: Organisation
            bucket: Bucket für Heizungsdaten
        """
        self.url = url
        self.token = token
        self.org = org
        self.bucket = bucket
        self.client: Optional[InfluxDBClient] = None
        self.write_api = None
        self.query_api = None
        
        self._connect()
    
    def _connect(self) -> None:
        """Stellt Verbindung zur InfluxDB her"""
        try:
            self.client = InfluxDBClient(
                url=self.url,
                token=self.token,
                org=self.org,
                timeout=15000,
                enable_gzip=True
            )
            
            self.write_api = self.client.write_api(write_options=SYNCHRONOUS)
            self.query_api = self.client.query_api()
            
            if self.test_connection():
                logger.info(f"InfluxDB Verbindung erfolgreich: {self.url}")
            else:
                raise ConnectionError("InfluxDB Verbindungstest fehlgeschlagen")
                
        except Exception as e:
            logger.error(f"InfluxDB Verbindungsfehler: {e}")
            self.client = None
    
    def test_connection(self) -> bool:
        """Testet die InfluxDB Verbindung"""
        if not self.client:
            return False
        
        try:
            health = self.client.health()
            return health.status == "pass"
        except Exception as e:
            logger.error(f"InfluxDB Verbindungstest fehlgeschlagen: {e}")
            return False
    
    def write_heating_circuit_data(self, circuit_name: str, flow_temp: float, 
                                  return_temp: float, timestamp: Optional[datetime] = None) -> bool:
        """
        Schreibt Heizkreis-Temperaturdaten
        
        Args:
            circuit_name: Name des Heizkreises
            flow_temp: Vorlauftemperatur
            return_temp: Rücklauftemperatur
            timestamp: Zeitstempel
            
        Returns:
            True bei Erfolg
        """
        if not self.write_api:
            return False
        
        if timestamp is None:
            timestamp = datetime.utcnow()
        
        try:
            points = []
            
            # Vorlauftemperatur
            if flow_temp is not None:
                flow_point = Point("heating_temperature") \
                    .tag("circuit", circuit_name) \
                    .tag("type", "flow") \
                    .tag("location", "heating_system") \
                    .field("temperature", float(flow_temp)) \
                    .time(timestamp)
                points.append(flow_point)
            
            # Rücklauftemperatur
            if return_temp is not None:
                return_point = Point("heating_temperature") \
                    .tag("circuit", circuit_name) \
                    .tag("type", "return") \
                    .tag("location", "heating_system") \
                    .field("temperature", float(return_temp)) \
                    .time(timestamp)
                points.append(return_point)
            
            # Temperaturdifferenz berechnen und schreiben
            if flow_temp is not None and return_temp is not None:
                diff = flow_temp - return_temp
                diff_point = Point("heating_efficiency") \
                    .tag("circuit", circuit_name) \
                    .tag("metric", "temperature_difference") \
                    .tag("location", "heating_system") \
                    .field("value", float(diff)) \
                    .field("flow_temperature", float(flow_temp)) \
                    .field("return_temperature", float(return_temp)) \
                    .time(timestamp)
                points.append(diff_point)
                
                # Effizienz-Rating
                efficiency_rating = self._calculate_efficiency_score(diff)
                rating_point = Point("heating_efficiency") \
                    .tag("circuit", circuit_name) \
                    .tag("metric", "efficiency_score") \
                    .tag("location", "heating_system") \
                    .field("score", float(efficiency_rating)) \
                    .field("temperature_difference", float(diff)) \
                    .time(timestamp)
                points.append(rating_point)
            
            if points:
                self.write_api.write(bucket=self.bucket, record=points)
                logger.debug(f"Heizkreis-Daten geschrieben: {circuit_name}")
                return True
            
        except Exception as e:
            logger.error(f"Fehler beim Schreiben der Heizkreis-Daten: {e}")
        
        return False
    
    def write_heating_room_data(self, sensor_name: str, temperature: float, 
                               humidity: float, dew_point: float = None,
                               timestamp: Optional[datetime] = None) -> bool:
        """
        Schreibt Heizungsraum-Umgebungsdaten
        
        Args:
            sensor_name: Name des Sensors
            temperature: Raumtemperatur
            humidity: Luftfeuchtigkeit
            dew_point: Taupunkt
            timestamp: Zeitstempel
            
        Returns:
            True bei Erfolg
        """
        if not self.write_api:
            return False
        
        if timestamp is None:
            timestamp = datetime.utcnow()
        
        try:
            points = []
            
            # Raumtemperatur
            if temperature is not None:
                temp_point = Point("room_climate") \
                    .tag("sensor", sensor_name) \
                    .tag("location", "heating_room") \
                    .tag("type", "temperature") \
                    .field("value", float(temperature)) \
                    .time(timestamp)
                points.append(temp_point)
            
            # Luftfeuchtigkeit
            if humidity is not None:
                humidity_point = Point("room_climate") \
                    .tag("sensor", sensor_name) \
                    .tag("location", "heating_room") \
                    .tag("type", "humidity") \
                    .field("value", float(humidity)) \
                    .time(timestamp)
                points.append(humidity_point)
            
            # Taupunkt
            if dew_point is not None:
                dew_point_point = Point("room_climate") \
                    .tag("sensor", sensor_name) \
                    .tag("location", "heating_room") \
                    .tag("type", "dew_point") \
                    .field("value", float(dew_point)) \
                    .time(timestamp)
                points.append(dew_point_point)
            
            # Kondensationsrisiko bewerten
            if temperature is not None and dew_point is not None:
                # Annahme: Kälteste Rohrleitung ist 5°C unter Raumtemperatur
                pipe_temp = temperature - 5
                condensation_risk = max(0, min(100, (dew_point - pipe_temp + 5) * 20))
                
                risk_point = Point("heating_alerts") \
                    .tag("type", "condensation_risk") \
                    .tag("location", "heating_room") \
                    .field("risk_percentage", float(condensation_risk)) \
                    .field("dew_point", float(dew_point)) \
                    .field("estimated_pipe_temp", float(pipe_temp)) \
                    .time(timestamp)
                points.append(risk_point)
            
            if points:
                self.write_api.write(bucket=self.bucket, record=points)
                logger.debug(f"Heizungsraum-Daten geschrieben: {sensor_name}")
                return True
                
        except Exception as e:
            logger.error(f"Fehler beim Schreiben der Heizungsraum-Daten: {e}")
        
        return False
    
    def write_system_status(self, total_circuits: int, active_circuits: int,
                           system_efficiency: float = None, alerts: List[Dict] = None,
                           timestamp: Optional[datetime] = None) -> bool:
        """
        Schreibt Gesamtsystem-Status
        
        Args:
            total_circuits: Anzahl Heizkreise gesamt
            active_circuits: Anzahl aktive Heizkreise
            system_efficiency: Gesamteffizienz des Systems
            alerts: Liste von Alarmen
            timestamp: Zeitstempel
            
        Returns:
            True bei Erfolg
        """
        if not self.write_api:
            return False
        
        if timestamp is None:
            timestamp = datetime.utcnow()
        
        try:
            points = []
            
            # System-Status
            status_point = Point("heating_system_status") \
                .tag("system", "main") \
                .tag("location", "heating_system") \
                .field("total_circuits", int(total_circuits)) \
                .field("active_circuits", int(active_circuits)) \
                .field("inactive_circuits", int(total_circuits - active_circuits)) \
                .time(timestamp)
            
            if system_efficiency is not None:
                status_point = status_point.field("efficiency", float(system_efficiency))
            
            points.append(status_point)
            
            # Alarm-Status
            if alerts:
                for alert in alerts:
                    alert_point = Point("heating_alerts") \
                        .tag("type", alert.get('type', 'unknown')) \
                        .tag("circuit", alert.get('circuit', 'system')) \
                        .tag("location", "heating_system") \
                        .field("message", alert.get('message', '')) \
                        .field("active", 1) \
                        .time(timestamp)
                    points.append(alert_point)
            else:
                # Keine Alarme aktiv
                no_alert_point = Point("heating_alerts") \
                    .tag("type", "status") \
                    .tag("location", "heating_system") \
                    .field("message", "System läuft normal") \
                    .field("active", 0) \
                    .time(timestamp)
                points.append(no_alert_point)
            
            if points:
                self.write_api.write(bucket=self.bucket, record=points)
                logger.debug("System-Status geschrieben")
                return True
                
        except Exception as e:
            logger.error(f"Fehler beim Schreiben des System-Status: {e}")
        
        return False
    
    def _calculate_efficiency_score(self, temperature_diff: float) -> float:
        """
        Berechnet Effizienz-Score basierend auf Temperaturdifferenz
        
        Args:
            temperature_diff: Temperaturdifferenz in °C
            
        Returns:
            Score zwischen 0-100
        """
        if temperature_diff >= 15:
            return 100.0
        elif temperature_diff >= 10:
            return 80.0
        elif temperature_diff >= 7:
            return 60.0
        elif temperature_diff >= 5:
            return 40.0
        elif temperature_diff >= 3:
            return 20.0
        else:
            return 0.0
    
    def query_recent_temperatures(self, circuit_name: str = None, hours: int = 24) -> List[Dict]:
        """
        Fragt kürzlich aufgezeichnete Temperaturdaten ab
        
        Args:
            circuit_name: Spezifischer Heizkreis (optional)
            hours: Zeitraum in Stunden
            
        Returns:
            Liste von Datenpunkten
        """
        if not self.query_api:
            return []
        
        try:
            circuit_filter = f'|> filter(fn: (r) => r["circuit"] == "{circuit_name}")' if circuit_name else ''
            
            query = f'''
            from(bucket: "{self.bucket}")
              |> range(start: -{hours}h)
              |> filter(fn: (r) => r["_measurement"] == "heating_temperature")
              {circuit_filter}
              |> sort(columns: ["_time"], desc: true)
              |> limit(n: 1000)
            '''
            
            result = self.query_api.query(query)
            
            data_points = []
            for table in result:
                for record in table.records:
                    data_points.append({
                        'time': record.get_time(),
                        'circuit': record.values.get('circuit'),
                        'type': record.values.get('type'),
                        'temperature': record.get_value()
                    })
            
            return data_points
            
        except Exception as e:
            logger.error(f"Fehler bei Temperatur-Abfrage: {e}")
            return []
    
    def query_efficiency_trends(self, circuit_name: str = None, days: int = 7) -> List[Dict]:
        """
        Fragt Effizienz-Trends ab
        
        Args:
            circuit_name: Spezifischer Heizkreis
            days: Zeitraum in Tagen
            
        Returns:
            Liste von Effizienz-Datenpunkten
        """
        if not self.query_api:
            return []
        
        try:
            circuit_filter = f'|> filter(fn: (r) => r["circuit"] == "{circuit_name}")' if circuit_name else ''
            
            query = f'''
            from(bucket: "{self.bucket}")
              |> range(start: -{days}d)
              |> filter(fn: (r) => r["_measurement"] == "heating_efficiency")
              |> filter(fn: (r) => r["metric"] == "efficiency_score")
              {circuit_filter}
              |> aggregateWindow(every: 1h, fn: mean, createEmpty: false)
              |> sort(columns: ["_time"], desc: false)
            '''
            
            result = self.query_api.query(query)
            
            data_points = []
            for table in result:
                for record in table.records:
                    data_points.append({
                        'time': record.get_time(),
                        'circuit': record.values.get('circuit'),
                        'efficiency_score': record.get_value()
                    })
            
            return data_points
            
        except Exception as e:
            logger.error(f"Fehler bei Effizienz-Abfrage: {e}")
            return []
    
    def get_current_alerts(self) -> List[Dict]:
        """
        Gibt aktuelle Alarme zurück
        
        Returns:
            Liste von aktiven Alarmen
        """
        if not self.query_api:
            return []
        
        try:
            query = f'''
            from(bucket: "{self.bucket}")
              |> range(start: -1h)
              |> filter(fn: (r) => r["_measurement"] == "heating_alerts")
              |> filter(fn: (r) => r["active"] == 1)
              |> group(columns: ["type", "circuit"])
              |> last()
            '''
            
            result = self.query_api.query(query)
            
            alerts = []
            for table in result:
                for record in table.records:
                    alerts.append({
                        'type': record.values.get('type'),
                        'circuit': record.values.get('circuit'),
                        'message': record.values.get('message'),
                        'time': record.get_time()
                    })
            
            return alerts
            
        except Exception as e:
            logger.error(f"Fehler bei Alarm-Abfrage: {e}")
            return []
    
    def close(self) -> None:
        """Schließt die InfluxDB Verbindung"""
        if self.client:
            try:
                self.client.close()
                logger.info("InfluxDB Verbindung geschlossen")
            except Exception as e:
                logger.error(f"Fehler beim Schließen der InfluxDB Verbindung: {e}")
