#!/usr/bin/env python3
"""
Web-Dashboard für die Heizungsüberwachung
Bietet eine einfache Weboberfläche zur System-Überwachung
"""

from flask import Flask, render_template, jsonify
import sys
from pathlib import Path
import json
from datetime import datetime

# Projekt-Root zum Python-Pfad hinzufügen
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

from src.sensors.heating_sensors import HeatingSystemManager
from src.sensors.dht22_sensor import HeatingRoomSensor

app = Flask(__name__)

# Globale Instanzen
heating_manager = None
room_sensor = None

def initialize_sensors():
    """Initialisiert die Sensoren"""
    global heating_manager, room_sensor
    
    try:
        heating_manager = HeatingSystemManager()
        room_sensor = HeatingRoomSensor()
        return True
    except Exception as e:
        print(f"Fehler bei Sensor-Initialisierung: {e}")
        return False

@app.route('/')
def dashboard():
    """Haupt-Dashboard"""
    return render_template('dashboard.html')

@app.route('/api/status')
def api_status():
    """API-Endpoint für System-Status"""
    try:
        if not heating_manager:
            return jsonify({'error': 'Sensoren nicht initialisiert'}), 500
        
        # System-Status
        system_status = heating_manager.get_system_status()
        
        # Raumdaten
        room_conditions = room_sensor.check_heating_room_conditions()
        
        return jsonify({
            'timestamp': datetime.utcnow().isoformat(),
            'system': system_status,
            'room': room_conditions,
            'status': 'ok'
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/temperatures')
def api_temperatures():
    """API-Endpoint für aktuelle Temperaturen"""
    try:
        if not heating_manager:
            return jsonify({'error': 'Sensoren nicht initialisiert'}), 500
        
        temperatures = heating_manager.get_all_temperatures()
        
        return jsonify({
            'timestamp': datetime.utcnow().isoformat(),
            'temperatures': temperatures
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    if initialize_sensors():
        print("🌐 Starte Web-Dashboard auf http://localhost:5000")
        app.run(host='0.0.0.0', port=5000, debug=False)
    else:
        print("❌ Sensor-Initialisierung fehlgeschlagen")
        sys.exit(1)
