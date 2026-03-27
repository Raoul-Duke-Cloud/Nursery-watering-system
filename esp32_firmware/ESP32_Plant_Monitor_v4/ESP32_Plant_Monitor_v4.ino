/*
 * ESP32 Plant Monitoring — Multi-Zone Drip/Feed System
 * Version 4.2
 *
 * One ESP32 controls multiple independent zones.
 * Each zone has its own moisture sensor and solenoid valve.
 * Environmental sensors (air temp, humidity, light, leaf temp)
 * are shared across all zones on the same ESP32.
 *
 * ── QUICK START ────────────────────────────────────────────────────────────
 * 1. Set NUM_ZONES to how many zones this ESP32 controls (1–4)
 * 2. Set ZONE_IDS, MOISTURE_PINS, RELAY_PINS to match your wiring
 * 3. Set TEST_MODE true to test standalone, false for live mesh
 * 4. Fill in WiFi + server details (mesh mode only)
 * ──────────────────────────────────────────────────────────────────────────
 *
 * PIN ASSIGNMENTS (see NurseryHub_Overview_and_Setup.md for wiring diagram)
 *
 *   SHARED (one per ESP32):
 *     DHT22       → GPIO27
 *     BH1750      → GPIO21 (SDA), GPIO22 (SCL)
 *     MLX90614    → GPIO21 (SDA), GPIO22 (SCL)  [shares I2C bus]
 *     SD Card     → GPIO5 (CS), GPIO23 (MOSI), GPIO19 (MISO), GPIO18 (SCK)
 *
 *   PER ZONE (4-zone default):
 *     Moisture    → GPIO32, 33, 34, 35
 *     Relay       → GPIO25, 26, 13, 14
 *
 * LIBRARIES REQUIRED (Arduino Library Manager):
 * - BH1750
 * - Adafruit MLX90614
 * - DHT sensor library (Adafruit)
 * - PubSubClient  (mesh mode only)
 * - ArduinoJson   (mesh mode only)
 *
 * ── v4.1 CHANGES ───────────────────────────────────────────────────────────
 * - Boot self-test: checks all sensors and pulses each relay on startup
 * - Dripper performance tracking: monitors moisture rise after each watering
 *   and flags reduced capacity if a zone consistently underperforms baseline
 *
 * ── v4.2 CHANGES ───────────────────────────────────────────────────────────
 * - OTA (over-the-air) firmware updates via HTTP on boot (mesh mode only)
 * - Rollback support: if new firmware fails to start, ESP32 boots previous
 * ──────────────────────────────────────────────────────────────────────────
 */

#include <Wire.h>
#include <BH1750.h>
#include <Adafruit_MLX90614.h>
#include <DHT.h>
#include <SD.h>
#include <SPI.h>

// ═══════════════════════════════════════════════════════════════════
// TEST MODE
// ═══════════════════════════════════════════════════════════════════
//   true  = standalone, no WiFi, verbose serial output
//   false = mesh mode, connects to WiFi + Elixir server

#define TEST_MODE true

#if TEST_MODE
  #define READING_INTERVAL  10000    // 10s between readings (fast for testing)
  #define WATERING_COOLDOWN 60000    // 1 min cooldown (easy to observe)
  #define DRIP_CHECK_DELAY  30000    // 30s post-drip check (fast for testing)
#else
  #define READING_INTERVAL  30000    // 30s between readings
  #define WATERING_COOLDOWN 900000   // 15 min cooldown
  #define DRIP_CHECK_DELAY  120000   // 2 min post-drip moisture check
#endif

#if !TEST_MODE
  #include <WiFi.h>
  #include <PubSubClient.h>
  #include <ArduinoJson.h>
  #include <HTTPClient.h>
  #include <Update.h>
#endif

// ═══════════════════════════════════════════════════════════════════
// ZONE CONFIGURATION — SET THIS FOR EACH ESP32
// ═══════════════════════════════════════════════════════════════════

// How many zones this ESP32 controls (1 to 4)
#define NUM_ZONES 4

// Unique name for each zone — these appear in the dashboard
const char* ZONE_IDS[NUM_ZONES] = {
  "zone_a",
  "zone_b",
  "zone_c",
  "zone_d"
};

// Moisture sensor analog pin for each zone
// ADC1 pins only (required for WiFi compatibility): 32, 33, 34, 35, 36, 39
const int MOISTURE_PINS[NUM_ZONES] = { 32, 33, 34, 35 };

// Relay pin for each zone's solenoid valve
// GPIO25, 26, 13, 14 — chosen to avoid conflicts with shared sensor pins
const int RELAY_PINS[NUM_ZONES] = { 25, 26, 13, 14 };

// ═══════════════════════════════════════════════════════════════════
// SITE + SERVER CONFIG
// ═══════════════════════════════════════════════════════════════════

#define SITE_ID  "site_01"   // e.g. "northcote", "fitzroy"
#define NODE_ID  "ESP-001"   // asset tag on this physical enclosure — must match the label

// Current firmware version — increment this each time you deploy new firmware
// The server compares this to decide whether to push an update
#define FIRMWARE_VERSION 42

#if !TEST_MODE
  #define WIFI_SSID   "YOUR_WIFI_NAME"
  #define WIFI_PASS   "YOUR_WIFI_PASSWORD"
  #define MQTT_SERVER "192.168.1.100"      // IP of your Elixir server (or VPN IP)
  #define MQTT_PORT   1883
  #define MQTT_USER   "esp32_device"       // must match Mosquitto password file
  #define MQTT_PASS   "CHANGE_THIS_MQTT_PASSWORD"  // see SECURITY_SETUP.md Step 1

  // OTA update URLs — served by the NurseryHub Elixir server
  #define OTA_VERSION_URL  "http://" MQTT_SERVER ":4000/firmware/version"
  #define OTA_FIRMWARE_URL "http://" MQTT_SERVER ":4000/firmware/esp32_plant_monitor.bin"
  #define OTA_TIMEOUT_MS   10000   // 10s timeout for version check
#endif

// ═══════════════════════════════════════════════════════════════════
// SHARED SENSOR PINS
// ═══════════════════════════════════════════════════════════════════

#define DHT_PIN   27    // DHT22 — air temp + humidity
#define I2C_SDA   21    // BH1750 + MLX90614 share this I2C bus
#define I2C_SCL   22
#define SD_CS      5
#define SD_MOSI   23
#define SD_MISO   19
#define SD_SCK    18

// ═══════════════════════════════════════════════════════════════════
// WATERING PARAMETERS
// ═══════════════════════════════════════════════════════════════════

const int   MOISTURE_LOW        = 30;
const int   MOISTURE_HIGH       = 65;
const int   MOISTURE_EMERGENCY  = 10;

const unsigned long BASE_DRIP_MS = 15000;
const unsigned long MIN_DRIP_MS  = 8000;
const unsigned long MAX_DRIP_MS  = 30000;

const unsigned long SERVER_TIMEOUT_MS = 1800000;

const int MOISTURE_DRY = 3200;
const int MOISTURE_WET = 1200;

// ═══════════════════════════════════════════════════════════════════
// DRIPPER PERFORMANCE PARAMETERS
// ═══════════════════════════════════════════════════════════════════

// Number of watering events to average for the baseline
#define DRIP_HISTORY_SIZE 5

// Minimum events before fault detection activates (avoids false positives early on)
#define DRIP_MIN_BASELINE 3

// If moisture rise is below this fraction of baseline, flag as reduced capacity
// e.g. 0.5 = fault if rise is less than 50% of the average
const float DRIPPER_FAULT_THRESHOLD = 0.5;

// ═══════════════════════════════════════════════════════════════════
// OPERATING MODES
// ═══════════════════════════════════════════════════════════════════

enum OperatingMode {
  MODE_NORMAL,
  MODE_NO_VPD,
  MODE_NO_MOISTURE,
  MODE_LOCAL
};

const char* modeNames[] = { "normal", "no_vpd", "no_moisture", "local" };

// ═══════════════════════════════════════════════════════════════════
// SENSOR STATUS
// ═══════════════════════════════════════════════════════════════════

struct SharedStatus {
  bool dht_ok   = true;
  bool light_ok = true;
  bool ir_ok    = true;
};

struct ZoneStatus {
  bool moisture_ok = true;
};

// ═══════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════

DHT               dht(DHT_PIN, DHT22);
BH1750            lightMeter;
Adafruit_MLX90614 mlx;

#if !TEST_MODE
WiFiClient   wifiClient;
PubSubClient mqtt(wifiClient);
char TOPIC_DATA[NUM_ZONES][64];
char TOPIC_CMD[NUM_ZONES][64];
#endif

SharedStatus sharedSensors;
ZoneStatus   zoneSensors[NUM_ZONES];
OperatingMode currentMode = MODE_NORMAL;

bool          isWatering[NUM_ZONES];
unsigned long wateringStartTime[NUM_ZONES];
unsigned long lastWateringTime[NUM_ZONES];
unsigned long currentDripDuration[NUM_ZONES];
int           lastMoisture[NUM_ZONES];

float sharedVPD      = 0;
float sharedAirTemp  = 0;
float sharedHumidity = 0;
float sharedLux      = 0;
float sharedLeafTemp = 0;

unsigned long lastReadingTime   = 0;
unsigned long lastServerContact = 0;

bool   sdAvailable = false;
String dataFile    = "/plantdata.csv";

// ── Dripper performance tracking ─────────────────────────────────

int           moistureBeforeDrip[NUM_ZONES];
bool          waitingForDripCheck[NUM_ZONES];
unsigned long dripCheckTime[NUM_ZONES];

float dripHistory[NUM_ZONES][DRIP_HISTORY_SIZE];
int   dripHistoryCount[NUM_ZONES];
int   dripHistoryIdx[NUM_ZONES];
bool  dripperFault[NUM_ZONES];

// ═══════════════════════════════════════════════════════════════════
// VPD CALCULATION
// ═══════════════════════════════════════════════════════════════════

float calculateVPD(float airTemp, float humidity, float leafTemp) {
  float svp_air  = 0.61078 * exp((17.27 * airTemp)  / (airTemp  + 237.3));
  float avp      = svp_air * (humidity / 100.0);
  float svp_leaf = 0.61078 * exp((17.27 * leafTemp) / (leafTemp + 237.3));
  return svp_leaf - avp;
}

unsigned long dripDurationForVPD(float vpd) {
  float mult;
  if      (vpd < 0.4)  mult = 0.6;
  else if (vpd < 0.8)  mult = 0.8;
  else if (vpd <= 1.2) mult = 1.0;
  else if (vpd <= 1.6) mult = 1.3;
  else                 mult = 1.6;
  return constrain((unsigned long)(BASE_DRIP_MS * mult), MIN_DRIP_MS, MAX_DRIP_MS);
}

// ═══════════════════════════════════════════════════════════════════
// SENSOR READS
// ═══════════════════════════════════════════════════════════════════

int readMoisture(int zone) {
  int raw     = analogRead(MOISTURE_PINS[zone]);
  int percent = map(raw, MOISTURE_DRY, MOISTURE_WET, 0, 100);
  percent     = constrain(percent, 0, 100);
  zoneSensors[zone].moisture_ok = (raw >= 100 && raw <= 4000);
  return percent;
}

void readSharedSensors() {
  sharedLux      = lightMeter.readLightLevel();
  sharedLeafTemp = mlx.readObjectTempC();
  sharedSensors.light_ok = (sharedLux >= 0);
  sharedSensors.ir_ok    = (sharedLeafTemp > -20 && sharedLeafTemp < 80);

  float t = dht.readTemperature();
  float h = dht.readHumidity();
  if (isnan(t) || isnan(h)) {
    sharedSensors.dht_ok = false;
  } else {
    sharedSensors.dht_ok = true;
    sharedAirTemp  = t;
    sharedHumidity = h;
    sharedVPD = calculateVPD(sharedAirTemp, sharedHumidity, sharedLeafTemp);
  }
}

// ═══════════════════════════════════════════════════════════════════
// BOOT SELF-TEST
// ═══════════════════════════════════════════════════════════════════

void runBootSelfTest() {
  Serial.println("\n┌─── BOOT SELF-TEST ──────────────────────────────────┐");

  // ── Shared sensors ──────────────────────────────────────────────
  Serial.println("│  Shared sensors:");

  // DHT22
  delay(2000);  // DHT22 needs time to stabilise after power-on
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  if (isnan(t) || isnan(h))
    Serial.println("│    DHT22      FAIL — no reading (check wiring GPIO27)");
  else
    Serial.printf( "│    DHT22      OK   — %.1f°C  %.1f%%RH\n", t, h);

  // BH1750
  float lux = lightMeter.readLightLevel();
  if (lux < 0)
    Serial.println("│    BH1750     FAIL — no reading (check I2C GPIO21/22)");
  else
    Serial.printf( "│    BH1750     OK   — %.0f lux\n", lux);

  // MLX90614
  float leafT = mlx.readObjectTempC();
  if (leafT < -20 || leafT > 80)
    Serial.println("│    MLX90614   FAIL — reading out of range (check I2C GPIO21/22)");
  else
    Serial.printf( "│    MLX90614   OK   — %.1f°C object temp\n", leafT);

  // ── Per-zone moisture sensors ────────────────────────────────────
  Serial.println("│");
  Serial.println("│  Moisture sensors:");
  for (int z = 0; z < NUM_ZONES; z++) {
    int raw = analogRead(MOISTURE_PINS[z]);
    int pct = constrain(map(raw, MOISTURE_DRY, MOISTURE_WET, 0, 100), 0, 100);
    if (raw < 100 || raw > 4000)
      Serial.printf("│    [%s]  FAIL — raw ADC %d (check wiring GPIO%d)\n",
        ZONE_IDS[z], raw, MOISTURE_PINS[z]);
    else
      Serial.printf("│    [%s]  OK   — %d%% moisture (raw %d)\n",
        ZONE_IDS[z], pct, raw);
  }

  // ── Relay / valve pulse test ─────────────────────────────────────
  Serial.println("│");
  Serial.println("│  Relay test (each valve pulses 500ms — listen for click):");
  for (int z = 0; z < NUM_ZONES; z++) {
    Serial.printf("│    [%s]  pulsing...", ZONE_IDS[z]);
    digitalWrite(RELAY_PINS[z], HIGH);
    delay(500);
    digitalWrite(RELAY_PINS[z], LOW);
    Serial.println(" done");
    delay(300);
  }

  // ── SD card ─────────────────────────────────────────────────────
  Serial.println("│");
  Serial.printf( "│  SD card:    %s\n", sdAvailable ? "OK" : "not present (logging to server only)");

  Serial.println("└─────────────────────────────────────────────────────┘\n");
}

// ═══════════════════════════════════════════════════════════════════
// DRIPPER PERFORMANCE TRACKING
// ═══════════════════════════════════════════════════════════════════

float dripBaseline(int zone) {
  if (dripHistoryCount[zone] < DRIP_MIN_BASELINE) return -1;
  float sum = 0;
  int count = min(dripHistoryCount[zone], DRIP_HISTORY_SIZE);
  for (int i = 0; i < count; i++) sum += dripHistory[zone][i];
  return sum / count;
}

void recordDripResult(int zone, int moistureBefore, int moistureAfter) {
  int rise = moistureAfter - moistureBefore;

  // Store in rolling history
  dripHistory[zone][dripHistoryIdx[zone]] = (float)rise;
  dripHistoryIdx[zone] = (dripHistoryIdx[zone] + 1) % DRIP_HISTORY_SIZE;
  if (dripHistoryCount[zone] < DRIP_HISTORY_SIZE) dripHistoryCount[zone]++;

  float baseline = dripBaseline(zone);

  Serial.printf("DRIPPER CHECK [%s] — rise: %d%%", ZONE_IDS[zone], rise);
  if (baseline < 0) {
    Serial.printf("  (baseline building — %d/%d events)\n",
      dripHistoryCount[zone], DRIP_MIN_BASELINE);
    dripperFault[zone] = false;
    return;
  }

  Serial.printf("  baseline: %.1f%%", baseline);

  if (baseline < 1.0) {
    // Baseline is near zero — moisture sensor may not be in soil
    Serial.println("  WARNING: baseline very low, check sensor placement");
    dripperFault[zone] = false;
    return;
  }

  if ((float)rise < baseline * DRIPPER_FAULT_THRESHOLD) {
    dripperFault[zone] = true;
    Serial.printf("  *** FAULT — only %.0f%% of expected rise — check dripper/valve\n",
      ((float)rise / baseline) * 100.0);
  } else {
    dripperFault[zone] = false;
    Serial.println("  OK");
  }
}

void checkDripperPerformance() {
  unsigned long now = millis();
  for (int z = 0; z < NUM_ZONES; z++) {
    if (waitingForDripCheck[z] && now >= dripCheckTime[z]) {
      waitingForDripCheck[z] = false;
      if (zoneSensors[z].moisture_ok) {
        int moistureAfter = readMoisture(z);
        recordDripResult(z, moistureBeforeDrip[z], moistureAfter);
      } else {
        Serial.printf("DRIPPER CHECK [%s] — skipped (moisture sensor fault)\n", ZONE_IDS[z]);
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// OPERATING MODE
// ═══════════════════════════════════════════════════════════════════

OperatingMode determineModeForZone(int zone) {
  if (!zoneSensors[zone].moisture_ok) return MODE_NO_MOISTURE;
  if (!sharedSensors.dht_ok || !sharedSensors.ir_ok) return MODE_NO_VPD;
#if TEST_MODE
  return MODE_NORMAL;
#else
  if (millis() - lastServerContact > SERVER_TIMEOUT_MS) return MODE_LOCAL;
  return MODE_NORMAL;
#endif
}

// ═══════════════════════════════════════════════════════════════════
// TEST MODE — VERBOSE DECISION LOG
// ═══════════════════════════════════════════════════════════════════

#if TEST_MODE
void printDecisionLog(int zone, int moisture, float vpd, float lux,
                      unsigned long duration) {
  Serial.printf("\n┌─── VPD DECISION — %s ──────────────────────\n", ZONE_IDS[zone]);

  Serial.printf("│  VPD:      %.3f kPa  →  ", vpd);
  if      (vpd < 0.4)  Serial.println("too low (mould risk)");
  else if (vpd < 0.8)  Serial.println("low (propagation)");
  else if (vpd <= 1.2) Serial.println("OPTIMAL");
  else if (vpd <= 1.6) Serial.println("high (flowering)");
  else                 Serial.println("TOO HIGH (stress)");

  Serial.printf("│  Moisture: %d%%  →  ", moisture);
  if      (moisture <= MOISTURE_EMERGENCY) Serial.println("EMERGENCY DRY");
  else if (moisture < MOISTURE_LOW)        Serial.println("below threshold — will water");
  else if (moisture < MOISTURE_HIGH)       Serial.println("acceptable");
  else                                     Serial.println("well moistened");

  bool night = (lux < 100 && vpd < 0.5);
  Serial.printf("│  Light:    %.0f lux  →  %s\n", lux, night ? "NIGHT MODE" : "day");

  unsigned long sinceLast = millis() - lastWateringTime[zone];
  bool cooldownOk = (sinceLast >= WATERING_COOLDOWN);
  if (cooldownOk) Serial.println("│  Cooldown: ready");
  else Serial.printf("│  Cooldown: %lus remaining\n",
    ((unsigned long)WATERING_COOLDOWN - sinceLast) / 1000);

  float baseline = dripBaseline(zone);
  if (baseline >= 0)
    Serial.printf("│  Dripper:  baseline %.1f%% rise  %s\n",
      baseline, dripperFault[zone] ? "*** REDUCED CAPACITY ***" : "OK");
  else
    Serial.printf("│  Dripper:  building baseline (%d/%d events)\n",
      dripHistoryCount[zone], DRIP_MIN_BASELINE);

  if (moisture < MOISTURE_LOW && !night && cooldownOk)
    Serial.printf("│  Decision: DRIP for %lus  (%.2fx VPD mult)\n",
      duration / 1000, (float)duration / BASE_DRIP_MS);
  else
    Serial.println("│  Decision: no watering this cycle");

  Serial.println("└────────────────────────────────────────────────");
}
#endif

// ═══════════════════════════════════════════════════════════════════
// WATERING CONTROL
// ═══════════════════════════════════════════════════════════════════

void startDrip(int zone, unsigned long duration, const char* reason) {
  // Record moisture before drip for performance tracking
  moistureBeforeDrip[zone] = lastMoisture[zone];

  currentDripDuration[zone] = duration;
  wateringStartTime[zone]   = millis();
  isWatering[zone]          = true;
  digitalWrite(RELAY_PINS[zone], HIGH);
  Serial.printf("DRIP START [%s] — %s — %lus\n", ZONE_IDS[zone], reason, duration / 1000);
}

void stopDrip(int zone, const char* reason) {
  digitalWrite(RELAY_PINS[zone], LOW);
  isWatering[zone]       = false;
  lastWateringTime[zone] = millis();
  Serial.printf("DRIP STOP  [%s] — %s\n", ZONE_IDS[zone], reason);

  // Schedule post-drip moisture check to assess dripper performance
  if (zoneSensors[zone].moisture_ok) {
    waitingForDripCheck[zone] = true;
    dripCheckTime[zone] = millis() + DRIP_CHECK_DELAY;
    Serial.printf("DRIPPER CHECK [%s] — scheduled in %ds\n",
      ZONE_IDS[zone], DRIP_CHECK_DELAY / 1000);
  }
}

void controlZone(int zone, int moisture, float vpd, float lux) {
  unsigned long now = millis();

  if (isWatering[zone]) {
    if (now - wateringStartTime[zone] >= currentDripDuration[zone])
      { stopDrip(zone, "duration complete"); return; }
    if (zoneSensors[zone].moisture_ok && moisture >= MOISTURE_HIGH)
      { stopDrip(zone, "moisture target reached"); return; }
    if (now - wateringStartTime[zone] > MAX_DRIP_MS * 2)
      stopDrip(zone, "SAFETY TIMEOUT — check valve");
    return;
  }

  bool cooldownOk = (now - lastWateringTime[zone] >= WATERING_COOLDOWN);

  if (zoneSensors[zone].moisture_ok && moisture <= MOISTURE_EMERGENCY) {
    startDrip(zone, MAX_DRIP_MS, "EMERGENCY — critically dry");
    return;
  }

  if (!cooldownOk) return;

  OperatingMode mode = determineModeForZone(zone);
  unsigned long duration = dripDurationForVPD(vpd);

#if TEST_MODE
  printDecisionLog(zone, moisture, vpd, lux, duration);
#endif

  switch (mode) {
    case MODE_NORMAL:
    case MODE_LOCAL:
      if (lux < 100 && vpd < 0.5) { Serial.printf("[%s] Night mode\n", ZONE_IDS[zone]); return; }
      if (moisture < MOISTURE_LOW) startDrip(zone, duration, "moisture low");
      break;
    case MODE_NO_VPD:
      if (moisture < MOISTURE_LOW) startDrip(zone, BASE_DRIP_MS, "no VPD — fixed duration");
      break;
    case MODE_NO_MOISTURE:
      startDrip(zone, BASE_DRIP_MS, "no moisture sensor — scheduled");
      break;
  }
}

// ═══════════════════════════════════════════════════════════════════
// SD CARD
// ═══════════════════════════════════════════════════════════════════

void initSD() {
  if (!SD.begin(SD_CS)) { sdAvailable = false; return; }
  sdAvailable = true;
  if (!SD.exists(dataFile)) {
    File f = SD.open(dataFile, FILE_WRITE);
    if (f) { f.println("ts_s,site,zone,moisture,lux,leaf_temp,air_temp,humidity,vpd,watering,dripper_fault,mode"); f.close(); }
  }
  Serial.println("SD card ready");
}

void logZoneToSD(int zone, int moisture, OperatingMode mode) {
  if (!sdAvailable) return;
  File f = SD.open(dataFile, FILE_APPEND);
  if (!f) return;
  f.print(millis()/1000); f.print(",");
  f.print(SITE_ID);       f.print(",");
  f.print(ZONE_IDS[zone]);f.print(",");
  f.print(moisture);      f.print(",");
  f.print(sharedLux,1);   f.print(",");
  f.print(sharedLeafTemp,2); f.print(",");
  f.print(sharedAirTemp,2);  f.print(",");
  f.print(sharedHumidity,1); f.print(",");
  f.print(sharedVPD,3);   f.print(",");
  f.print(isWatering[zone] ? 1 : 0); f.print(",");
  f.print(dripperFault[zone] ? 1 : 0); f.print(",");
  f.println(modeNames[mode]);
  f.close();
}

// ═══════════════════════════════════════════════════════════════════
// MQTT — mesh mode only
// ═══════════════════════════════════════════════════════════════════

#if !TEST_MODE
void publishZone(int zone, int moisture) {
  if (!mqtt.connected()) return;
  StaticJsonDocument<512> doc;
  doc["site"]          = SITE_ID;      doc["zone"]          = ZONE_IDS[zone];
  doc["node_id"]       = NODE_ID;
  doc["ts"]            = millis()/1000; doc["moisture"]      = moisture;
  doc["lux"]           = sharedLux;    doc["leaf_temp"]      = sharedLeafTemp;
  doc["air_temp"]      = sharedAirTemp; doc["humidity"]      = sharedHumidity;
  doc["vpd"]           = sharedVPD;    doc["watering"]       = isWatering[zone];
  doc["valve"]         = isWatering[zone] ? "open" : "closed";
  doc["mode"]          = modeNames[determineModeForZone(zone)];
  doc["dripper_fault"] = dripperFault[zone];
  doc["dripper_baseline"] = dripBaseline(zone);
  JsonObject ok = doc.createNestedObject("sensor_ok");
  ok["moisture"] = zoneSensors[zone].moisture_ok;
  ok["dht"]      = sharedSensors.dht_ok;
  ok["light"]    = sharedSensors.light_ok;
  ok["ir"]       = sharedSensors.ir_ok;
  char buf[512]; serializeJson(doc, buf);
  mqtt.publish(TOPIC_DATA[zone], buf);
  lastServerContact = millis();
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  StaticJsonDocument<128> doc;
  if (deserializeJson(doc, payload, length)) return;
  const char* cmd = doc["cmd"]; if (!cmd) return;
  for (int z = 0; z < NUM_ZONES; z++) {
    if (strcmp(topic, TOPIC_CMD[z]) == 0) {
      if      (strcmp(cmd,"water")==0)  startDrip(z,(unsigned long)(doc["duration"]|15)*1000,"remote");
      else if (strcmp(cmd,"stop")==0 && isWatering[z]) stopDrip(z,"remote stop");
      else if (strcmp(cmd,"reboot")==0) { delay(500); ESP.restart(); }
      return;
    }
  }
}

void checkForOTAUpdate() {
  Serial.println("OTA: checking for firmware update...");

  HTTPClient http;
  http.setTimeout(OTA_TIMEOUT_MS);
  http.begin(OTA_VERSION_URL);
  int code = http.GET();

  if (code != 200) {
    Serial.printf("OTA: version check failed (HTTP %d) — skipping\n", code);
    http.end();
    return;
  }

  int serverVersion = http.getString().toInt();
  http.end();

  if (serverVersion <= FIRMWARE_VERSION) {
    Serial.printf("OTA: up to date (v%d)\n", FIRMWARE_VERSION);
    return;
  }

  Serial.printf("OTA: new firmware available v%d → v%d\n", FIRMWARE_VERSION, serverVersion);
  Serial.println("OTA: closing valves before update...");

  // Safety — ensure all valves are closed before flashing
  for (int z = 0; z < NUM_ZONES; z++) {
    if (isWatering[z]) stopDrip(z, "OTA update");
    digitalWrite(RELAY_PINS[z], LOW);
  }

  Serial.println("OTA: downloading firmware...");
  http.begin(OTA_FIRMWARE_URL);
  code = http.GET();

  if (code != 200) {
    Serial.printf("OTA: download failed (HTTP %d)\n", code);
    http.end();
    return;
  }

  int contentLength = http.getSize();
  if (contentLength <= 0) {
    Serial.println("OTA: invalid content length — aborting");
    http.end();
    return;
  }

  if (!Update.begin(contentLength)) {
    Serial.printf("OTA: not enough space (need %d bytes)\n", contentLength);
    http.end();
    return;
  }

  Serial.printf("OTA: flashing %d bytes...\n", contentLength);
  WiFiClient* stream = http.getStreamPtr();
  size_t written = Update.writeStream(*stream);
  http.end();

  if (written != (size_t)contentLength) {
    Serial.printf("OTA: write error — %d of %d bytes written\n", written, contentLength);
    Update.abort();
    return;
  }

  if (!Update.end()) {
    Serial.printf("OTA: verification failed (error %d)\n", Update.getError());
    return;
  }

  // Mark new firmware as valid so bootloader won't roll back on first boot
  Update.markAsValid();

  Serial.println("OTA: success — rebooting into new firmware");
  Serial.println("OTA: if new firmware fails, bootloader will automatically restore previous version");
  delay(1000);
  ESP.restart();
}

void connectWiFi() {
  if (WiFi.status()==WL_CONNECTED) return;
  Serial.print("WiFi connecting");
  WiFi.begin(WIFI_SSID,WIFI_PASS);
  int n=0; while(WiFi.status()!=WL_CONNECTED && n<20){delay(500);Serial.print(".");n++;}
  if(WiFi.status()==WL_CONNECTED){Serial.print(" ");Serial.println(WiFi.localIP());}
  else Serial.println(" FAILED — local mode");
}

void connectMQTT() {
  if(mqtt.connected()||WiFi.status()!=WL_CONNECTED) return;
  char id[48]; snprintf(id,sizeof(id),"esp32-%s",SITE_ID);
  if(mqtt.connect(id,MQTT_USER,MQTT_PASS)){
    for(int z=0;z<NUM_ZONES;z++) mqtt.subscribe(TOPIC_CMD[z]);
    Serial.println("MQTT connected");
  }
}
#endif

// ═══════════════════════════════════════════════════════════════════
// SETUP
// ═══════════════════════════════════════════════════════════════════

void setup() {
  Serial.begin(115200); delay(1000);

  Serial.println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
#if TEST_MODE
  Serial.println("ESP32 Plant Monitor v4.1 — TEST MODE");
#else
  Serial.println("ESP32 Plant Monitor v4.1 — Mesh Mode");
#endif
  Serial.printf("Site: %s   Zones: %d\n", SITE_ID, NUM_ZONES);
  for (int z = 0; z < NUM_ZONES; z++)
    Serial.printf("  [%d] %s — moisture GPIO%d, relay GPIO%d\n",
      z, ZONE_IDS[z], MOISTURE_PINS[z], RELAY_PINS[z]);
  Serial.println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

  for (int z = 0; z < NUM_ZONES; z++) {
    pinMode(RELAY_PINS[z], OUTPUT);
    digitalWrite(RELAY_PINS[z], LOW);
    isWatering[z]           = false;
    wateringStartTime[z]    = 0;
    lastWateringTime[z]     = 0;
    currentDripDuration[z]  = BASE_DRIP_MS;
    lastMoisture[z]         = 50;
    moistureBeforeDrip[z]   = 0;
    waitingForDripCheck[z]  = false;
    dripCheckTime[z]        = 0;
    dripHistoryCount[z]     = 0;
    dripHistoryIdx[z]       = 0;
    dripperFault[z]         = false;
    for (int i = 0; i < DRIP_HISTORY_SIZE; i++) dripHistory[z][i] = 0;
  }

  Wire.begin(I2C_SDA, I2C_SCL);
  lightMeter.begin(BH1750::CONTINUOUS_HIGH_RES_MODE);
  mlx.begin(); dht.begin();
  analogReadResolution(12); analogSetAttenuation(ADC_11db);
  initSD();

  runBootSelfTest();

#if !TEST_MODE
  for (int z = 0; z < NUM_ZONES; z++) {
    snprintf(TOPIC_DATA[z],64,"nursery/%s/%s/data",SITE_ID,ZONE_IDS[z]);
    snprintf(TOPIC_CMD[z], 64,"nursery/%s/%s/cmd", SITE_ID,ZONE_IDS[z]);
  }
  connectWiFi();
  mqtt.setServer(MQTT_SERVER,MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  connectMQTT();
  lastServerContact = millis();
  checkForOTAUpdate();  // check for new firmware on every boot
#endif

  Serial.println("Ready\n");
}

// ═══════════════════════════════════════════════════════════════════
// MAIN LOOP
// ═══════════════════════════════════════════════════════════════════

void loop() {
#if !TEST_MODE
  connectWiFi(); connectMQTT(); mqtt.loop();
#endif

  unsigned long now = millis();

  // Check scheduled post-drip moisture readings
  checkDripperPerformance();

  if (now - lastReadingTime >= READING_INTERVAL) {
    lastReadingTime = now;
    readSharedSensors();

    Serial.println("\n──── SHARED SENSORS ──────────────────────────────");
    Serial.printf("Air:  %.1f°C  RH: %.1f%%  (DHT: %s)\n",
      sharedAirTemp, sharedHumidity, sharedSensors.dht_ok ? "ok" : "FAULT");
    Serial.printf("Leaf: %.1f°C  (IR: %s)\n",
      sharedLeafTemp, sharedSensors.ir_ok ? "ok" : "FAULT");
    Serial.printf("Lux:  %.0f  (light: %s)\n",
      sharedLux, sharedSensors.light_ok ? "ok" : "FAULT");
    Serial.printf("VPD:  %.3f kPa\n", sharedVPD);

    Serial.println("──── ZONES ───────────────────────────────────────");
    for (int z = 0; z < NUM_ZONES; z++) {
      int moisture = readMoisture(z);
      lastMoisture[z] = moisture;
      OperatingMode mode = determineModeForZone(z);
      Serial.printf("[%s]  moisture: %d%%  mode: %s  valve: %s  dripper: %s\n",
        ZONE_IDS[z], moisture, modeNames[mode],
        isWatering[z] ? "OPEN" : "closed",
        dripperFault[z] ? "FAULT" : (dripHistoryCount[z] < DRIP_MIN_BASELINE ? "learning" : "ok"));
      logZoneToSD(z, moisture, mode);
#if !TEST_MODE
      publishZone(z, moisture);
#endif
    }
    Serial.println("──────────────────────────────────────────────────");
  }

  for (int z = 0; z < NUM_ZONES; z++)
    controlZone(z, lastMoisture[z], sharedVPD, sharedLux);

  delay(100);
}
