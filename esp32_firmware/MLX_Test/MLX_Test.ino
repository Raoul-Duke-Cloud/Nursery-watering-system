/*
 * NurseryHub — MLX90614 Test Sketch
 *
 * Tests the MLX90614 IR leaf-temperature sensor only, no other hardware
 * required. Same idea as DHT_Test.ino — isolated so you can verify one
 * sensor at a time without needing the DHT/BH1750/ADS1115/SD libraries
 * installed.
 *
 * Wiring (shared I2C bus):
 *   VCC → 1N5819 diode → 3.3V rail
 *   GND → GND rail
 *   SDA → GPIO21
 *   SCL → GPIO22
 *
 * Fixed I2C address: 0x5A (no ADDR pin on MLX90614 breakouts).
 *
 * Libraries required (Arduino Library Manager):
 *   Adafruit MLX90614
 *
 * Usage:
 *   1. Flash to your ESP32
 *   2. Open Serial Monitor at 115200 baud
 *   3. Readings repeat every TEST_INTERVAL_MS
 */

#include <Wire.h>
#include <Adafruit_MLX90614.h>

#define I2C_SDA 21
#define I2C_SCL 22
#define TEST_INTERVAL_MS 5000

Adafruit_MLX90614 mlx;
bool mlx_ok = false;

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("══════════════════════════════════════");
  Serial.println("NurseryHub — MLX90614 Test Sketch");
  Serial.println("══════════════════════════════════════");

  Wire.begin(I2C_SDA, I2C_SCL);

  mlx_ok = mlx.begin();
  Serial.printf("MLX90614 init: %s\n", mlx_ok ? "OK (found at 0x5A)" : "FAIL — not found on I2C bus");
  if (!mlx_ok) {
    Serial.println("Check: SDA->GPIO21, SCL->GPIO22, VCC/GND, and that nothing else on the");
    Serial.println("I2C bus is holding the address low.");
  }
}

void loop() {
  static unsigned long lastTest = 0;
  unsigned long now = millis();

  if (now - lastTest >= (unsigned long)TEST_INTERVAL_MS) {
    lastTest = now;
    Serial.println();
    Serial.printf("Read @ %lus uptime\n", now / 1000);

    if (!mlx_ok) {
      Serial.println("  MLX90614   FAIL   not initialised — see setup message above");
      return;
    }

    float obj = mlx.readObjectTempC();
    float amb = mlx.readAmbientTempC();

    if (obj < -40 || obj > 125) {
      Serial.printf("  MLX90614 object temp    FAIL   %.1f°C — outside sensor range\n", obj);
    } else {
      Serial.printf("  MLX90614 object temp    PASS   %.1f°C\n", obj);
    }

    if (amb < -40 || amb > 125) {
      Serial.printf("  MLX90614 ambient temp   FAIL   %.1f°C — outside sensor range\n", amb);
    } else {
      Serial.printf("  MLX90614 ambient temp   PASS   %.1f°C\n", amb);
    }
  }
}
