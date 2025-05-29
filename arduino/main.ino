#include <WiFi.h>
#include <HTTPClient.h>
#include <DHT.h>
#include <ArduinoJson.h>

#define DHTPIN 4
#define DHTTYPE DHT11
#define RELAY_PIN 5

const char* ssid = "1BB582-Maxis Fibre";
const char* password = "akEmLuMc5h";
const char* serverName = "http://192.168.1.6:5000/api/data";

DHT dht(DHTPIN, DHTTYPE);

float tempThreshold = 26;
float humThreshold = 70;

void fetchThresholds() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin("http://192.168.1.6:5000/api/thresholds");
    int httpCode = http.GET();
    if (httpCode == 200) {
      String payload = http.getString();
      DynamicJsonDocument doc(512);
      deserializeJson(doc, payload);
      tempThreshold = doc["temperature"];
      humThreshold = doc["humidity"];
      Serial.println("Updated thresholds:");
      Serial.print("Temp: "); Serial.println(tempThreshold); Serial.println(" °C");
      Serial.print("Humidity: "); Serial.println(humThreshold); Serial.println(" %");
    }
    http.end();
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);
  dht.begin();

  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("Connected to WiFi");

  fetchThresholds();  // Get initial thresholds from server
}

void loop() {
  float temp = dht.readTemperature();
  float hum = dht.readHumidity();

  fetchThresholds();  // Refresh thresholds before decision

  bool relayState = temp > tempThreshold || hum > humThreshold;
  digitalWrite(RELAY_PIN, relayState ? HIGH : LOW);

  Serial.print("Temp: ");
  Serial.print(temp);
  Serial.print(" °C | Humidity: ");
  Serial.print(hum);
  Serial.println(" %");

  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(serverName);
    http.addHeader("Content-Type", "application/json");

    String payload = "{\"temperature\":" + String(temp) +
                     ",\"humidity\":" + String(hum) +
                     ",\"relay\":" + String(relayState ? 1 : 0) + "}";
    http.POST(payload);
    http.end();
  }

  delay(10000);
}
