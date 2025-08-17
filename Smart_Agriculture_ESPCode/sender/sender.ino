#include <SPI.h>
#include <LoRa.h>
#include <DHT.h>
#include <OneWire.h>
#include <DallasTemperature.h>

#define DHTPIN 4
#define DHTTYPE DHT11
DHT dht(DHTPIN, DHTTYPE);

#define ONE_WIRE_BUS 32
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature soilTempSensor(&oneWire);

#define RAIN_SENSOR_PIN 34
#define SOIL_MOISTURE_PIN 33

// LoRa pins (adjust if needed)
#define LORA_SS 5
#define LORA_RST 14
#define LORA_DIO0 2

void setup() {
  Serial.begin(115200);

  dht.begin();
  soilTempSensor.begin();

  // LoRa init
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);
  if (!LoRa.begin(433E6)) {   // 433 MHz band
    Serial.println("Starting LoRa failed!");
    while (1);
  }
  Serial.println("LoRa Sender Ready");
}

void loop() {
  float airHumidity = dht.readHumidity();
  float airTemperature = dht.readTemperature();
  soilTempSensor.requestTemperatures();
  float soilTemp = soilTempSensor.getTempCByIndex(0);
  int rainValue = analogRead(RAIN_SENSOR_PIN);
  int soilMoistureValue = analogRead(SOIL_MOISTURE_PIN);

  if (isnan(airHumidity) || isnan(airTemperature) || isnan(soilTemp)) {
    Serial.println("Sensor read failed!");
    delay(5000);
    return;
  }

  // Create payload (comma separated)
  String payload = String(airTemperature) + "," +
                   String(airHumidity) + "," +
                   String(soilTemp) + "," +
                   String(rainValue) + "," +
                   String(soilMoistureValue);

  Serial.println("Sending: " + payload);

  LoRa.beginPacket();
  LoRa.print(payload);
  LoRa.endPacket();

  delay(15000); // send every 15 sec
}