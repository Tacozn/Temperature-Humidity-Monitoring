from flask import Flask, request, jsonify
from flask_cors import CORS
from datetime import datetime
import json
import os

app = Flask(__name__)
CORS(app)

# File to store the data and configuration
DATA_FILE = 'sensor_data.json'
CONFIG_FILE = 'config.json'

# Initialize config file if it doesn't exist
if not os.path.exists(CONFIG_FILE):
    with open(CONFIG_FILE, 'w') as f:
        json.dump({
            'temp_threshold': 26.0,
            'hum_threshold': 70.0
        }, f)

# Initialize data file if it doesn't exist
if not os.path.exists(DATA_FILE):
    with open(DATA_FILE, 'w') as f:
        json.dump([], f)

def load_data():
    with open(DATA_FILE, 'r') as f:
        return json.load(f)

def save_data(data):
    with open(DATA_FILE, 'w') as f:
        json.dump(data, f)

def load_config():
    with open(CONFIG_FILE, 'r') as f:
        return json.load(f)

def save_config(config):
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f)

@app.route('/api/data', methods=['GET', 'POST'])
def handle_data():
    if request.method == 'POST':
        data = request.get_json()
        data['timestamp'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        all_data = load_data()
        all_data.append(data)
        
        # Keep only the last 100 readings
        if len(all_data) > 100:
            all_data = all_data[-100:]
        
        save_data(all_data)
        return jsonify({'status': 'success'})
    
    return jsonify(load_data())

@app.route('/api/config', methods=['GET', 'POST'])
def handle_config():
    if request.method == 'POST':
        config = request.get_json()
        save_config(config)
        return jsonify({'status': 'success'})
    
    return jsonify(load_config())

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True) 