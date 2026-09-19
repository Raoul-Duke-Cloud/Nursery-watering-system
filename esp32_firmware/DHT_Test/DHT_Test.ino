/*
 * NurseryHub — DHT22 Test Sketch
 *
 * Tests the DHT22 air temp/humidity sensor(s) only, no other hardware
 * required. Split out of Sensor_Test.ino so you can verify the DHT22
 * wiring without needing the BH1750/MLX90614/ADS1115/SD libraries
 * installed.
 *
 * Pin assignments match ESP32_Plant_Monitor_v5:
 *   DHT22 primary    → GPIO27
 *   DHT22 secondary  → GPIO4 (optional — leave unwired if you only have one)
 *
 * Libraries required (Arduino Library Manager):
 *   DHT sensor library (Adafruit)
 *
 * Usage:
 *   1. Flash to your ESP32
 *   2. Open Serial Monitor at 115200 baud
 *   3. Readings repeat every TEST_INTERVAL_MS
 */

#include <DHT.h>

#define DHT_PIN     27
#define DHT_PIN_2    4
#define TEST_INTERVAL_MS 5000

DHT dht(DHT_PIN, DHT22);
DHT dht2(DHT_PIN_2, DHT22);

void readOne(const char* label, DHT& sensor) {
  float t = sensor.readTemperature();
  float h = sensor.readHumidity();

  if (isnan(t) || isnan(h)) {
    Serial.printf("  %-24s FAIL   no reading — check wiring\n", label);
    return;
  }
  if (t < -20 || t > 60 || h < 0 || h > 100) {
    Serial.printf("  %-24s WARN   %.1f°C  %.1f%%RH  (outside physical range)\n", label, t, h);
    return;
  }
  Serial.printf("  %-24s PASS   %.1f°C   %.1f%% RH\n", label, t, h);
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("══════════════════════════════════════");
  Serial.println("NurseryHub — DHT22 Test Sketch");
  Serial.println("══════════════════════════════════════");

  dht.begin();
  dht2.begin();
  Serial.println("Waiting 2s for sensor stabilisation...");
  delay(2000);
}

void loop() {
  static unsigned long lastTest = 0;
  unsigned long now = millis();

  if (now - lastTest >= (unsigned long)TEST_INTERVAL_MS) {
    lastTest = now;
    Serial.println();
    Serial.printf("Read @ %lus uptime\n", now / 1000);
    readOne("DHT22 primary  (GPIO27)", dht);
    readOne("DHT22 secondary (GPIO4)", dht2);
  }
}
