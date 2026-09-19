/*
 * NurseryHub — I2C Scanner
 *
 * Sweeps all I2C addresses and reports anything that responds.
 * Use this to tell apart "nothing on the bus" (wiring/power/pull-up
 * problem) from "something's there but not at the address the library
 * expects" (wrong sensor / address jumper / library mismatch).
 *
 * Expected addresses in this project:
 *   0x23  BH1750 (lux)
 *   0x48  ADS1115 (secondary moisture, ADDR pin -> GND)
 *   0x5A  MLX90614 (IR leaf temp)
 *
 * No other libraries required — just Wire.
 *
 * Usage:
 *   1. Flash to your ESP32
 *   2. Open Serial Monitor at 115200 baud
 *   3. Scans repeat every SCAN_INTERVAL_MS
 */

#include <Wire.h>

#define I2C_SDA 21
#define I2C_SCL 22
#define SCAN_INTERVAL_MS 5000

void scan() {
  Serial.println();
  Serial.println("Scanning I2C bus...");
  int found = 0;

  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    uint8_t err = Wire.endTransmission();

    if (err == 0) {
      found++;
      const char* known = "";
      if      (addr == 0x23) known = "  (BH1750 default)";
      else if (addr == 0x48) known = "  (ADS1115, ADDR->GND)";
      else if (addr == 0x5A) known = "  (MLX90614)";
      Serial.printf("  Found device at 0x%02X%s\n", addr, known);
    }
  }

  if (found == 0) {
    Serial.println("  No devices found — check VCC/GND, SDA/SCL wiring, and pull-ups.");
  } else {
    Serial.printf("Done — %d device(s) found.\n", found);
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("══════════════════════════════════════");
  Serial.println("NurseryHub — I2C Scanner");
  Serial.println("══════════════════════════════════════");

  Wire.begin(I2C_SDA, I2C_SCL);
}

void loop() {
  static unsigned long lastScan = 0;
  unsigned long now = millis();

  if (now - lastScan >= (unsigned long)SCAN_INTERVAL_MS) {
    lastScan = now;
    scan();
  }
}
