/*
 * NurseryHub — Sensor Test Sketch
 *
 * Tests each sensor independently and prints results to Serial Monitor.
 * No WiFi, MQTT, or watering logic — purely for hardware verification.
 *
 * Pin assignments match ESP32_Plant_Monitor_v5:
 *
 *   DHT22 primary    → GPIO27
 *   DHT22 secondary  → GPIO4
 *   BH1750           → GPIO21 (SDA), GPIO22 (SCL)
 *   MLX90614         → GPIO21 (SDA), GPIO22 (SCL)
 *   ADS1115          → GPIO21 (SDA), GPIO22 (SCL), ADDR pin to GND (0x48)
 *   Moisture primary → GPIO32, 33, 34, 35
 *   Relay            → GPIO25, 26, 13, 14
 *   SD card          → GPIO5 (CS), 23 (MOSI), 19 (MISO), 18 (SCK)
 *
 * Libraries required (Arduino Library Manager):
 *   BH1750
 *   Adafruit MLX90614
 *   DHT sensor library (Adafruit)
 *   Adafruit ADS1X15
 *
 * Usage:
 *   1. Flash to your ESP32
 *   2. Open Serial Monitor at 115200 baud
 *   3. Relay pulse test runs once on boot — listen for clicks
 *   4. Sensor readings repeat every TEST_INTERVAL_MS
 */

#include <Wire.h>
#include <BH1750.h>
#include <Adafruit_MLX90614.h>
#include <DHT.h>
#include <SD.h>
#include <SPI.h>
#include <Adafruit_ADS1X15.h>

// ═══════════════════════════════════════════════════════════════════
// CONFIGURATION — adjust to match your wiring
// ═══════════════════════════════════════════════════════════════════

// How many moisture/relay zones to test (1–4)
#define NUM_ZONES 4

const int MOISTURE_PINS[NUM_ZONES] = { 32, 33, 34, 35 };
const int RELAY_PINS[NUM_ZONES]    = { 25, 26, 13, 14 };
const char* ZONE_LABELS[NUM_ZONES] = { "zone_a", "zone_b", "zone_c", "zone_d" };

#define DHT_PIN    27
#define DHT_PIN_2   4
#define I2C_SDA    21
#define I2C_SCL    22
#define SD_CS       5

// How often to repeat the full sensor read (milliseconds)
#define TEST_INTERVAL_MS 5000

// Relay pulse duration in the boot valve test
#define RELAY_PULSE_MS 500

// Moisture calibration — must match v5 firmware values for comparable readings
#define MOISTURE_DRY 2553 // raw ADC count at dry (0%)
#define MOISTURE_WET 1813   // raw ADC count at saturated (100%)

// ADS1115 secondary moisture: GAIN_ONE (±4.096V) → 0–32767 counts for 0–4.096V
// At 3.3V max sensor output, full-scale ≈ 26367 counts
#define ADS_FULLSCALE 26367

// Enable / disable test sections — set false to skip hardware you don't have
#define TEST_DHT      true
#define TEST_BH1750   true
#define TEST_MLX      true
#define TEST_MOISTURE true
#define TEST_ADS1115  true   // secondary moisture via ADS1115 I2C ADC
#define TEST_RELAYS   true   // pulse each relay once on boot
#define TEST_SD       true

// ═══════════════════════════════════════════════════════════════════
// GLOBALS
// ═══════════════════════════════════════════════════════════════════

DHT               dht(DHT_PIN, DHT22);
DHT               dht2(DHT_PIN_2, DHT22);
BH1750            lightMeter;
Adafruit_MLX90614 mlx;
Adafruit_ADS1115  ads;

bool bh_ok  = false;
bool mlx_ok = false;
bool ads_ok = false;
bool sd_ok  = false;

// ═══════════════════════════════════════════════════════════════════
// OUTPUT HELPERS
// ═══════════════════════════════════════════════════════════════════

void separator() {
  Serial.println("══════════════════════════════════════════════════════");
}

void section(const char* title) {
  Serial.println();
  Serial.print("-- ");
  Serial.print(title);
  Serial.print(" ");
  int pad = 47 - (int)strlen(title);
  for (int i = 0; i < pad && i < 47; i++) Serial.print('-');
  Serial.println();
}

// label is left-padded to 26 chars so columns align
void result(const char* status, const char* label, const char* detail) {
  char lbuf[28];
  snprintf(lbuf, sizeof(lbuf), "%-26s", label);
  Serial.printf("  %s  %s  %s\n", lbuf, status, detail);
}

void pass(const char* label, const char* detail) { result("PASS", label, detail); }
void fail(const char* label, const char* detail) { result("FAIL", label, detail); }
void warn(const char* label, const char* detail) { result("WARN", label, detail); }
void skip(const char* label, const char* detail) { result("----", label, detail); }

// ═══════════════════════════════════════════════════════════════════
// DHT22 — air temperature + humidity
// ═══════════════════════════════════════════════════════════════════

void testDHT() {
  section("DHT22 — air temp + humidity");

#if TEST_DHT
  char buf[80];
  float t1 = dht.readTemperature();
  float h1 = dht.readHumidity();
  bool ok1  = !isnan(t1) && !isnan(h1);

  if (!ok1) {
    fail("DHT22 primary  (GPIO27)", "no reading — check wiring");
  } else if (t1 < -20 || t1 > 60 || h1 < 0 || h1 > 100) {
    snprintf(buf, sizeof(buf), "%.1f°C  %.1f%%RH  (value outside physical range)", t1, h1);
    warn("DHT22 primary  (GPIO27)", buf);
  } else {
    snprintf(buf, sizeof(buf), "%.1f°C   %.1f%% RH", t1, h1);
    pass("DHT22 primary  (GPIO27)", buf);
  }

  float t2 = dht2.readTemperature();
  float h2 = dht2.readHumidity();
  bool ok2  = !isnan(t2) && !isnan(h2);

  if (!ok2) {
    fail("DHT22 secondary (GPIO4)", "no reading — check wiring");
  } else if (t2 < -20 || t2 > 60 || h2 < 0 || h2 > 100) {
    snprintf(buf, sizeof(buf), "%.1f°C  %.1f%%RH  (value outside physical range)", t2, h2);
    warn("DHT22 secondary (GPIO4)", buf);
  } else {
    snprintf(buf, sizeof(buf), "%.1f°C   %.1f%% RH", t2, h2);
    pass("DHT22 secondary (GPIO4)", buf);
  }

  // Cross-check agreement (same thresholds as v5)
  if (ok1 && ok2) {
    float td = abs(t1 - t2);
    float hd = abs(h1 - h2);
    snprintf(buf, sizeof(buf), "temp diff %.1f°C  RH diff %.1f%%  (threshold: 2°C / 5%%)", td, hd);
    if (td <= 2.0 && hd <= 5.0) pass("DHT agreement", buf);
    else                         warn("DHT agreement", buf);
  }
#else
  skip("DHT22", "disabled");
#endif
}

// ═══════════════════════════════════════════════════════════════════
// BH1750 — light level
// ═══════════════════════════════════════════════════════════════════

void testBH1750() {
  section("BH1750 — light level");

#if TEST_BH1750
  char buf[64];
  if (!bh_ok) {
    fail("BH1750 (I2C GPIO21/22)", "not found at init — check I2C wiring/power");
    return;
  }
  float lux = lightMeter.readLightLevel();
  if (lux < 0) {
    fail("BH1750 (I2C GPIO21/22)", "read error");
    return;
  }
  const char* desc;
  if      (lux <    10) desc = "dark / night";
  else if (lux <   500) desc = "indoor / shade";
  else if (lux < 10000) desc = "bright indoor / overcast";
  else                  desc = "direct sunlight";
  snprintf(buf, sizeof(buf), "%.1f lux  (%s)", lux, desc);
  pass("BH1750 (I2C GPIO21/22)", buf);
#else
  skip("BH1750", "disabled");
#endif
}

// ═══════════════════════════════════════════════════════════════════
// MLX90614 — IR leaf temperature
// ═══════════════════════════════════════════════════════════════════

void testMLX() {
  section("MLX90614 — IR leaf temp");

#if TEST_MLX
  char buf[64];
  if (!mlx_ok) {
    fail("MLX90614 (I2C GPIO21/22)", "not found at init — check I2C wiring/power");
    return;
  }
  float obj = mlx.readObjectTempC();
  float amb = mlx.readAmbientTempC();

  if (obj < -40 || obj > 125) {
    snprintf(buf, sizeof(buf), "%.1f°C — outside sensor range", obj);
    fail("MLX90614 object temp", buf);
  } else {
    snprintf(buf, sizeof(buf), "%.1f°C", obj);
    pass("MLX90614 object temp", buf);
  }

  if (amb < -40 || amb > 125) {
    snprintf(buf, sizeof(buf), "%.1f°C — outside sensor range", amb);
    fail("MLX90614 ambient temp", buf);
  } else {
    snprintf(buf, sizeof(buf), "%.1f°C", amb);
    pass("MLX90614 ambient temp", buf);
  }
#else
  skip("MLX90614", "disabled");
#endif
}

// ═══════════════════════════════════════════════════════════════════
// Moisture sensors — primary (ESP32 ADC) + secondary (ADS1115)
// ═══════════════════════════════════════════════════════════════════

void testMoisture() {
  section("Moisture sensors");

#if TEST_MOISTURE
  char label[32];
  char buf[80];

  for (int z = 0; z < NUM_ZONES; z++) {
    // ── Primary sensor — ESP32 ADC ──────────────────────────────
    int rawP = analogRead(MOISTURE_PINS[z]);
    int pctP = constrain(map(rawP, MOISTURE_DRY, MOISTURE_WET, 0, 100), 0, 100);
    bool okP = (rawP >= 100 && rawP <= 4000);

    snprintf(label, sizeof(label), "%s primary", ZONE_LABELS[z]);
    if (!okP) {
      snprintf(buf, sizeof(buf), "raw %d — out of range (check sensor/GPIO%d)", rawP, MOISTURE_PINS[z]);
      fail(label, buf);
    } else {
      snprintf(buf, sizeof(buf), "%d%%   raw %d  GPIO%d", pctP, rawP, MOISTURE_PINS[z]);
      pass(label, buf);
    }

    // ── Secondary sensor — ADS1115 ──────────────────────────────
#if TEST_ADS1115
    snprintf(label, sizeof(label), "%s secondary", ZONE_LABELS[z]);
    if (!ads_ok) {
      fail(label, "ADS1115 not found at init");
    } else {
      int16_t rawS_ads = ads.readADC_SingleEnded(z);
      int rawS = constrain((int)map((long)rawS_ads, 0, ADS_FULLSCALE, 0, 4095), 0, 4095);
      int pctS = constrain(map(rawS, MOISTURE_DRY, MOISTURE_WET, 0, 100), 0, 100);
      bool okS = (rawS >= 100 && rawS <= 4000);

      if (!okS) {
        snprintf(buf, sizeof(buf), "norm %d — out of range (check ADS1115 ch%d)", rawS, z);
        fail(label, buf);
      } else {
        snprintf(buf, sizeof(buf), "%d%%   ADS raw %d  norm %d  ch%d", pctS, rawS_ads, rawS, z);
        pass(label, buf);
      }

      // Agreement check (same 10% threshold as v5)
      if (okP && okS) {
        int diff = abs(pctP - pctS);
        snprintf(label, sizeof(label), "%s agreement", ZONE_LABELS[z]);
        snprintf(buf, sizeof(buf), "primary %d%%  secondary %d%%  diff %d%%  (threshold: 10%%)", pctP, pctS, diff);
        if (diff <= 10) pass(label, buf);
        else             warn(label, buf);
      }
    }
#endif

    // Blank line between zones for readability
    if (z < NUM_ZONES - 1) Serial.println();
  }
#else
  skip("moisture", "disabled");
#endif
}

// ═══════════════════════════════════════════════════════════════════
// Relays — pulse each valve (runs once on boot only)
// ═══════════════════════════════════════════════════════════════════

void testRelays() {
  section("Relays — valve pulse test (boot only)");

#if TEST_RELAYS
  Serial.printf("  Pulsing each relay for %dms — listen for click.\n", RELAY_PULSE_MS);
  char label[32];
  for (int z = 0; z < NUM_ZONES; z++) {
    snprintf(label, sizeof(label), "%s (GPIO%d)", ZONE_LABELS[z], RELAY_PINS[z]);
    Serial.printf("  %-26s  ...  ", label);
    Serial.flush();
    digitalWrite(RELAY_PINS[z], HIGH);
    delay(RELAY_PULSE_MS);
    digitalWrite(RELAY_PINS[z], LOW);
    Serial.println("pulsed");
    delay(300);
  }
#else
  skip("relays", "disabled");
#endif
}

// ═══════════════════════════════════════════════════════════════════
// SD card — write + read-back
// ═══════════════════════════════════════════════════════════════════

void testSD() {
  section("SD card");

#if TEST_SD
  if (!sd_ok) {
    warn("SD card", "not detected (non-fatal — data goes to server only)");
    return;
  }

  // Write a temp file and read it back
  const char* tmpPath = "/sensor_test.tmp";
  File f = SD.open(tmpPath, FILE_WRITE);
  if (!f) { fail("SD write", "could not open file for writing"); return; }
  f.println("sensor_test_ok");
  f.close();

  f = SD.open(tmpPath, FILE_READ);
  if (!f) { fail("SD read-back", "could not re-open file"); return; }
  String line = f.readStringUntil('\n');
  f.close();
  SD.remove(tmpPath);

  if (line.indexOf("sensor_test_ok") >= 0)
    pass("SD card", "write + read-back OK");
  else
    fail("SD card", "read-back mismatch — card may be corrupt");
#else
  skip("SD card", "disabled");
#endif
}

// ═══════════════════════════════════════════════════════════════════
// SETUP
// ═══════════════════════════════════════════════════════════════════

void setup() {
  Serial.begin(115200);
  delay(1000);

  separator();
  Serial.println("NurseryHub — Sensor Test Sketch");
  Serial.printf( "Zones: %d   Read interval: %ds\n", NUM_ZONES, TEST_INTERVAL_MS / 1000);
  separator();

  // All relays off (safe) before anything else
  for (int z = 0; z < NUM_ZONES; z++) {
    pinMode(RELAY_PINS[z], OUTPUT);
    digitalWrite(RELAY_PINS[z], LOW);
  }

  // I2C bus
  Wire.begin(I2C_SDA, I2C_SCL);

  // BH1750
#if TEST_BH1750
  bh_ok = lightMeter.begin(BH1750::CONTINUOUS_HIGH_RES_MODE);
  Serial.printf("BH1750 init:    %s\n", bh_ok ? "OK" : "FAIL (not found on I2C)");
#endif

  // MLX90614
#if TEST_MLX
  mlx_ok = mlx.begin();
  Serial.printf("MLX90614 init:  %s\n", mlx_ok ? "OK" : "FAIL (not found on I2C)");
#endif

  // DHT22 — needs 2s stabilisation time after power-on
#if TEST_DHT
  dht.begin();
  dht2.begin();
  Serial.println("DHT22 init:     waiting 2s for sensor stabilisation...");
  delay(2000);
  Serial.println("DHT22 init:     ready");
#endif

  // ADS1115 — check I2C presence before init to avoid hanging on missing device
#if TEST_ADS1115
  Wire.beginTransmission(0x48);
  ads_ok = (Wire.endTransmission() == 0);
  if (ads_ok) {
    ads.begin(0x48);
    ads.setGain(GAIN_ONE);
    Serial.println("ADS1115 init:   OK");
  } else {
    Serial.println("ADS1115 init:   not found (skipping secondary moisture)");
  }
#endif

  // SD card
#if TEST_SD
  sd_ok = SD.begin(SD_CS);
  Serial.printf("SD card init:   %s\n", sd_ok ? "OK" : "not present");
#endif

  // ADC config (must match v5 for comparable moisture readings)
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  // Relay pulse — runs once at boot only
  testRelays();

  Serial.println();
  Serial.printf("Starting read loop — every %ds. Ctrl+C in IDE to stop.\n",
    TEST_INTERVAL_MS / 1000);
}

// ═══════════════════════════════════════════════════════════════════
// LOOP
// ═══════════════════════════════════════════════════════════════════

void loop() {
  static unsigned long lastTest = 0;
  unsigned long now = millis();

  if (now - lastTest >= (unsigned long)TEST_INTERVAL_MS) {
    lastTest = now;

    separator();
    Serial.printf("Sensor read  @  %lus uptime\n", now / 1000);
    separator();

    testDHT();
    testBH1750();
    testMLX();
    testMoisture();
    testSD();

    Serial.println();
  }
}
