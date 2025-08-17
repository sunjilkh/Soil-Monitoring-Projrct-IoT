#include <WiFi.h>
#include <HTTPClient.h>
#include <SPI.h>
#include <LoRa.h>
#include "time.h"

// ----- WiFi -----
const char* ssid = "SAKIB";
const char* password = "12345678";

// ----- Firebase -----
const char* firebaseHost = "smart-agriculture-system-c8361-default-rtdb.asia-southeast1.firebasedatabase.app";
const char* firebaseAuth = "YVSzOrMmPNSLopG7FOTDpbd0OkIiZsU8B4xcbe7K";

// ----- ThingSpeak -----
const char* thingSpeakApiKey = "718O9YAZA9B6K1EX"; 
const char* thingSpeakServer = "api.thingspeak.com";
unsigned long thingSpeakChannelId = 3036073;

// LoRa pins
#define LORA_SS 5
#define LORA_RST 14
#define LORA_DIO0 2

// NTP
const char* ntpServer = "pool.ntp.org";
const long gmtOffset_sec = 6 * 3600;
const int daylightOffset_sec = 0;

// ---------- Helper Functions ----------
String getTimeStamp() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) return "N/A";
  char timeString[25];
  strftime(timeString, sizeof(timeString), "%Y-%m-%d %H:%M:%S", &timeinfo);
  return String(timeString);
}

void sendToFirebase(float airTemp, float airHumidity, float soilTemp, int rainValue, int soilMoisture, String timestamp) {
  HTTPClient http;
  String url = String("https://") + firebaseHost + "/sensorData.json?auth=" + firebaseAuth;
  String jsonData = "{";
  jsonData += "\"airTemp\":" + String(airTemp) + ",";
  jsonData += "\"airHumidity\":" + String(airHumidity) + ",";
  jsonData += "\"soilTemp\":" + String(soilTemp) + ",";
  jsonData += "\"rain\":" + String(rainValue) + ",";
  jsonData += "\"soilMoisture\":" + String(soilMoisture) + ",";
  jsonData += "\"timestamp\":\"" + timestamp + "\"";
  jsonData += "}";

  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  int code = http.POST(jsonData);

  if (code > 0) Serial.println("Firebase OK: " + String(code));
  else Serial.println("Firebase Error: " + String(code));
  http.end();
}

void sendToThingSpeak(float airTemp, float airHumidity, float soilTemp, int rainValue, int soilMoisture) {
  HTTPClient http;
  String url = String("https://") + thingSpeakServer + "/update?api_key=" + thingSpeakApiKey;
  url += "&field1=" + String(airTemp);
  url += "&field2=" + String(airHumidity);
  url += "&field3=" + String(soilTemp);
  url += "&field4=" + String(rainValue);
  url += "&field5=" + String(soilMoisture);

  http.begin(url);
  int code = http.GET();

  if (code > 0) Serial.println("ThingSpeak OK: " + String(code));
  else Serial.println("ThingSpeak Error: " + String(code));
  http.end();
}

// ---------- Setup ----------
void setup() {
  Serial.begin(115200);

  // WiFi connect
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi Connected");

  // NTP init
  configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);

  // LoRa init
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);
  if (!LoRa.begin(433E6)) {
    Serial.println("LoRa start failed!");
    while (1);
  }
  Serial.println("LoRa Receiver Ready");
}

// ---------- Loop ----------
void loop() {
  int packetSize = LoRa.parsePacket();
  if (packetSize) {
    String received = "";
    while (LoRa.available()) {
      received += (char)LoRa.read();
    }
    Serial.println("Received: " + received);

    // Parse CSV values
    float airTemp, airHumidity, soilTemp;
    int rainValue, soilMoisture;

    int i1 = received.indexOf(',');
    int i2 = received.indexOf(',', i1 + 1);
    int i3 = received.indexOf(',', i2 + 1);
    int i4 = received.indexOf(',', i3 + 1);

    if (i1 > 0 && i2 > i1 && i3 > i2 && i4 > i3) {
      airTemp = received.substring(0, i1).toFloat();
      airHumidity = received.substring(i1 + 1, i2).toFloat();
      soilTemp = received.substring(i2 + 1, i3).toFloat();
      rainValue = received.substring(i3 + 1, i4).toInt();
      soilMoisture = received.substring(i4 + 1).toInt();

      String ts = getTimeStamp();

      // Send to Firebase
      sendToFirebase(airTemp, airHumidity, soilTemp, rainValue, soilMoisture, ts);

      // Send to ThingSpeak
      sendToThingSpeak(airTemp, airHumidity, soilTemp, rainValue, soilMoisture);

    } else {
      Serial.println("Parse error!");
    }
  }
}