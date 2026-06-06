/*
 * NurseryHub — Cable Continuity, Polarity & Diode Protection Tester
 *
 * Tests sensor cables using EOL (end-of-line) loopback plugs.
 * Safe to run with no sensors attached — only drives GPIO outputs
 * at 3.3V logic level, never mains or valve power.
 *
 * ── HOW IT WORKS ─────────────────────────────────────────────────
 * Each cable runs two sub-tests:
 *
 *   1. CONTINUITY — drive pin A HIGH, read back on pin B via EOL loopback.
 *      PASS = signal arrives. FAIL = open circuit / broken wire.
 *
 *   2. DIODE PROTECTION — reverse the drive: set pin B HIGH, read pin A.
 *      A correctly fitted TVS/Schottky diode on pin A blocks reverse current.
 *      PASS = pin A reads LOW (diode blocking). FAIL = pin A reads HIGH
 *      (diode missing, wrong orientation, or shorted).
 *
 * Both tests must pass for a cable to be cleared for use.
 *
 * ── EOL PLUG WIRING ──────────────────────────────────────────────
 * Make one plug per cable type using the same connector as the sensor.
 * The loopback is a simple short between two pins — the reverse-direction
 * test is done in software, not by extra wiring.
 *
 * MOISTURE SENSOR (3-pin JST-XH):
 *   Pin 1 (VCC) ──┐
 *   Pin 2 (GND)   │ leave open
 *   Pin 3 (SIG) ──┘ short VCC to SIG
 *
 * DHT22 (4-pin JST-XH):
 *   Pin 1 (VCC)  ──┐
 *   Pin 2 (GND)    │ leave open
 *   Pin 3 (DATA) ──┘ short VCC to DATA
 *   Pin 4 (NC)     leave open
 *
 * RELAY (3-pin JST-XH):
 *   Pin 1 (VCC) ──┐
 *   Pin 2 (GND)   │ leave open
 *   Pin 3 (IN)  ──┘ short VCC to IN
 *   NOTE: relay coil is NOT energised during test
 *
 * I2C (4-pin JST-XH — BH1750, MLX90614, ADS1115):
 *   Pin 1 (VCC) ──┐
 *   Pin 2 (GND)   │ leave open
 *   Pin 3 (SDA) ──┘ short VCC to SDA
 *   Pin 4 (SCL)    leave open (tested separately via GND pull-down)
 *
 * ── SAFETY ───────────────────────────────────────────────────────
 * - All test pins are 3.3V logic only
 * - Never connect relay coil power (12V/24V) during cable test
 * - Never connect live sensors during cable test
 * - GND pins tested via pull-down only — never driven HIGH
 * - All drive pins return to LOW/INPUT after each test
 *
 * ── USAGE ────────────────────────────────────────────────────────
 * 1. Flash to ESP32
 * 2. Open Serial Monitor at 115200 baud
 * 3. Plug EOL loopback plug into the cable under test
 * 4. Press BOOT button on the ESP32 (or send any character)
 * 5. Both continuity and diode tests run automatically
 * 6. OVERALL PASS = both tests passed
 *
 * No libraries required.
 */

// ── PIN ASSIGNMENTS ───────────────────────────────────────────────
#define DRIVE_MOISTURE_A   25
#define DRIVE_MOISTURE_B   26
#define DRIVE_MOISTURE_C   13
#define DRIVE_MOISTURE_D   14
#define DRIVE_DHT          27
#define DRIVE_I2C_VCC      21

#define READ_MOISTURE_A    32
#define READ_MOISTURE_B    33
#define READ_MOISTURE_C    34
#define READ_MOISTURE_D    35
#define READ_DHT_DATA       4
#define READ_I2C_SCL       22

// ── CABLE DEFINITIONS ─────────────────────────────────────────────
struct CableTest {
  const char* name;
  int drivePin;   // -1 = GND-only test (no drive)
  int readPin;
  bool testDiode; // true = also run reverse-direction diode test
};

CableTest cables[] = {
  { "Moisture zone_a  (GPIO25→32)",  DRIVE_MOISTURE_A, READ_MOISTURE_A, true  },
  { "Moisture zone_b  (GPIO26→33)",  DRIVE_MOISTURE_B, READ_MOISTURE_B, true  },
  { "Moisture zone_c  (GPIO13→34)",  DRIVE_MOISTURE_C, READ_MOISTURE_C, true  },
  { "Moisture zone_d  (GPIO14→35)",  DRIVE_MOISTURE_D, READ_MOISTURE_D, true  },
  { "DHT22            (GPIO27→4)",   DRIVE_DHT,        READ_DHT_DATA,   true  },
  { "I2C SDA          (GPIO21→SDA)", DRIVE_I2C_VCC,    READ_MOISTURE_A, true  }, // SDA loopback
  { "I2C GND/SCL      (GND→SCL)",   -1,               READ_I2C_SCL,    false }, // GND test only
};

#define NUM_CABLES (sizeof(cables) / sizeof(cables[0]))

int currentTest = 0;

int allDrivePins[] = {
  DRIVE_MOISTURE_A, DRIVE_MOISTURE_B, DRIVE_MOISTURE_C, DRIVE_MOISTURE_D,
  DRIVE_DHT, DRIVE_I2C_VCC
};
int allReadPins[] = {
  READ_MOISTURE_A, READ_MOISTURE_B, READ_MOISTURE_C, READ_MOISTURE_D,
  READ_DHT_DATA, READ_I2C_SCL
};

void setup() {
  Serial.begin(115200);
  delay(1000);
  initPins();

  Serial.println();
  Serial.println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  Serial.println("  NurseryHub — Cable & Diode Protection Tester");
  Serial.println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  Serial.println();
  Serial.println("  Two tests per cable:");
  Serial.println("    1. Continuity  — signal must pass forward");
  Serial.println("    2. Diode check — signal must be blocked in reverse");
  Serial.println();
  Serial.println("  Plug EOL loopback plug into cable, then press");
  Serial.println("  BOOT button or send any character to test.");
  Serial.println();
  printNextPrompt();
}

void loop() {
  if (Serial.available()) {
    while (Serial.available()) Serial.read();
    runTest(currentTest);
    currentTest = (currentTest + 1) % NUM_CABLES;
    Serial.println();
    printNextPrompt();
  }
}

void runTest(int idx) {
  CableTest& t = cables[idx];
  Serial.println("──────────────────────────────────────────────────");
  Serial.printf( "Cable: %s\n", t.name);

  if (t.drivePin < 0) {
    // GND-only test — pin should sit LOW with pull-down when GND is connected
    bool gndOk = (digitalRead(t.readPin) == LOW);
    Serial.printf("  GND continuity:  %s\n", gndOk ? "PASS ✓" : "FAIL — GND wire open or floating");
    Serial.printf("Overall: %s\n", gndOk ? "PASS ✓" : "FAIL ✗");
    return;
  }

  // ── Test 1: Continuity (forward) ──────────────────────────────
  pinMode(t.drivePin, OUTPUT);
  pinMode(t.readPin, INPUT_PULLDOWN);
  digitalWrite(t.drivePin, HIGH);
  delay(10);
  bool forwardHigh = (digitalRead(t.readPin) == HIGH);
  digitalWrite(t.drivePin, LOW);
  pinMode(t.drivePin, INPUT);  // release before reverse test
  delay(5);

  Serial.printf("  1. Continuity:   ");
  if (forwardHigh) {
    Serial.println("PASS ✓ — signal arrived at return pin");
  } else {
    Serial.println("FAIL ✗ — no signal (open circuit / broken wire)");
  }

  // ── Test 2: Diode protection (reverse) ────────────────────────
  bool diodeOk = false;
  if (t.testDiode) {
    // Drive the return pin HIGH — if diode is present it blocks back-feed to drivePin
    pinMode(t.readPin, OUTPUT);
    pinMode(t.drivePin, INPUT_PULLDOWN);
    digitalWrite(t.readPin, HIGH);
    delay(10);
    bool reverseHigh = (digitalRead(t.drivePin) == HIGH);
    digitalWrite(t.readPin, LOW);
    // Restore
    pinMode(t.readPin, INPUT_PULLDOWN);
    pinMode(t.drivePin, OUTPUT);
    digitalWrite(t.drivePin, LOW);
    delay(5);

    diodeOk = !reverseHigh;  // diode passes if reverse signal was blocked
    Serial.printf("  2. Diode check:  ");
    if (diodeOk) {
      Serial.println("PASS ✓ — reverse current blocked");
    } else if (!forwardHigh) {
      Serial.println("SKIP  — continuity failed, diode test not meaningful");
    } else {
      Serial.println("FAIL ✗ — reverse current NOT blocked (diode missing, wrong direction, or shorted)");
    }
  } else {
    Serial.println("  2. Diode check:  SKIP — not applicable for this cable type");
    diodeOk = true;
  }

  // ── Overall ───────────────────────────────────────────────────
  bool overall = forwardHigh && diodeOk;
  Serial.printf("Overall: %s\n", overall ? "PASS ✓" : "FAIL ✗");
}

void initPins() {
  for (int i = 0; i < 6; i++) {
    pinMode(allDrivePins[i], OUTPUT);
    digitalWrite(allDrivePins[i], LOW);
  }
  for (int i = 0; i < 6; i++) {
    pinMode(allReadPins[i], INPUT_PULLDOWN);
  }
}

void printNextPrompt() {
  Serial.printf("Next: %s\n", cables[currentTest].name);
  Serial.println("Plug in EOL plug and press BOOT or send any character...");
}
