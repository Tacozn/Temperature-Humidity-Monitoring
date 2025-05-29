from flask import Flask, request, jsonify
from flask_cors import CORS
import mysql.connector
from datetime import datetime

app = Flask(__name__)
CORS(app)

conn = mysql.connector.connect(
    host="localhost",
    port=3307,
    user="root",
    password="",
    database="sensor_db"
)
cursor = conn.cursor()

@app.route('/api/data', methods=['POST'])
def insert_data():
    data = request.get_json()
    temp = data['temperature']
    hum = data['humidity']
    relay = data['relay']
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cursor.execute("INSERT INTO readings (temperature, humidity, relay, timestamp) VALUES (%s, %s, %s, %s)", (temp, hum, relay, now))
    conn.commit()
    return jsonify({"status": "ok"})

@app.route('/api/data', methods=['GET'])
def get_data():
    cursor.execute("SELECT * FROM readings ORDER BY id DESC LIMIT 20")
    rows = cursor.fetchall()
    result = [{"id": r[0], "temperature": r[1], "humidity": r[2], "relay": r[3], "timestamp": r[4].strftime("%H:%M:%S")} for r in rows]
    return jsonify(result)

# Add this above your `if __name__ == '__main__':` line

# Default thresholds if none set
default_temp = 26
default_hum = 70

# Create a table for thresholds
cursor.execute("""
CREATE TABLE IF NOT EXISTS thresholds (
    id INT PRIMARY KEY,
    temp_threshold FLOAT,
    hum_threshold FLOAT
)
""")
conn.commit()

# Ensure default threshold exists
cursor.execute("SELECT * FROM thresholds WHERE id = 1")
if cursor.fetchone() is None:
    cursor.execute("INSERT INTO thresholds (id, temp_threshold, hum_threshold) VALUES (1, %s, %s)", (default_temp, default_hum))
    conn.commit()

@app.route('/api/thresholds', methods=['GET'])
def get_thresholds():
    cursor.execute("SELECT temp_threshold, hum_threshold FROM thresholds WHERE id = 1")
    row = cursor.fetchone()
    return jsonify({
        "temperature": row[0],
        "humidity": row[1]
    })

@app.route('/api/thresholds', methods=['POST'])
def set_thresholds():
    data = request.get_json()
    temp = data.get('temperature', default_temp)
    hum = data.get('humidity', default_hum)
    cursor.execute("UPDATE thresholds SET temp_threshold = %s, hum_threshold = %s WHERE id = 1", (temp, hum))
    conn.commit()
    return jsonify({"status": "thresholds updated"})
if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')
