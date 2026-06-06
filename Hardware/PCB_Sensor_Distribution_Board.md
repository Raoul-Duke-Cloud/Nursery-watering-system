# NurseryHub Node Board — Design Spec

One PCB per field node. Integrates the ESP32, power supply, and all sensor
interfacing onto a single board. ESP32 and buck converter are socketed modules —
removable for reflashing or replacement without desoldering.

---

## Goals

- Single board per node — one enclosure, one power cable, no loose wiring
- ESP32 on 2×19 pin headers — removable for reflashing, replaceable if damaged
- Buck converter as a drop-in module on headers — easy to source and swap
- All passives (pull-ups, protection diodes, decoupling caps) on-board
- Every sensor plugs into a labelled JST-XH connector — no bare wire terminations
- Cables generic and interchangeable within each sensor type
- Cables testable with EOL loopback plugs using the Cable_Tester sketch
- Single 12V input from site rail → all on-board rails derived from it

---

## Board overview

```
┌──────────────────────────────────────────────────────┐
│  [12V IN]  [STATUS LEDs]                             │
│                                                      │
│  ┌────────────────┐   ┌──────────────────────────┐   │
│  │  Buck module   │   │   ESP32-DevKitC          │   │
│  │  (on headers)  │   │   (on 2×19 headers)      │   │
│  └────────────────┘   └──────────────────────────┘   │
│                                                      │
│  [MST-A] [MST-B] [MST-C] [MST-D]   (moisture)       │
│  [RLY-A] [RLY-B] [RLY-C] [RLY-D]   (relays)         │
│  [DHT22]  [I2C-1] [I2C-2] [I2C-3]  (shared sensors) │
│                                                      │
│  [MicroSD slot]                                      │
│  [GND test point] [3V3 TP] [5V TP] [12V TP]         │
└──────────────────────────────────────────────────────┘
```

---

## Modules (socketed)

### ESP32
- **ESP32-DevKitC** (38-pin) on 2 × 19-pin female headers
- Headers raise ESP32 ~8mm above PCB — clearance for USB port access on the side
- USB port faces board edge for cable access without removing module
- Remove from headers for reflashing if OTA is unavailable

### Buck converter
- **LM2596 module** (or MP2307) on 4-pin headers — 12V in, 5V out, up to 3A
- Pre-built module avoids hand-soldering of switching components
- Header pitch: 2.54mm, 2×2 arrangement (IN+, IN−, OUT+, OUT−)
- 5V output feeds ESP32 VIN and relay module VCC

### 3.3V LDO
- **AMS1117-3.3** — discrete, SOT-223 footprint, from 5V rail
- Powers all sensors and pull-up resistors
- 100µF + 100nF decoupling on output

---

## Connectors

All field-side connectors are **JST-XH 2.54mm** — polarised, locking, widely available.

| Ref | Type | Pins | Cable carries | Notes |
|---|---|---|---|---|
| MST-A/B/C/D | JST-XH 3-pin | 4× | VCC / GND / SIG | One per moisture zone |
| RLY-A/B/C/D | JST-XH 3-pin | 4× | VCC / GND / IN | Relay module IN line |
| DHT22 | JST-XH 4-pin | 1× | VCC / GND / DATA / NC | |
| I2C-1/2/3 | JST-XH 4-pin | 3× | VCC / GND / SDA / SCL | Shared bus — BH1750, MLX90614, ADS1115 |
| SD | MicroSD card slot | 1× | SPI (GPIO5/23/19/18) | On-board — local data logging |
| PWR-IN | Screw terminal 2-pin | 1× | 12V / GND | From site rail, with polarity marking |

---

## Passive components per channel

### Moisture sensors (× 4)
- **1N5819 Schottky** on VCC line — anode toward connector, cathode toward 3.3V rail
  — blocks reverse polarity from mis-wired cable
- TVS diode (SMBJ3.3A) on SIG line — clamps transients to 3.3V
- 100nF decoupling cap on VCC pin
- Diode protection verified by Cable_Tester reverse-direction test

### DHT22
- **1N5819 Schottky** on VCC line — same orientation
- 10kΩ pull-up on DATA to 3.3V (required by 1-wire protocol)
- 100nF decoupling cap on VCC

### I2C bus (shared — all three I2C connectors on same bus)
- **1N5819 Schottky** on VCC line of each connector
- 4.7kΩ pull-up on SDA to 3.3V — fitted once on bus, not per connector
- 4.7kΩ pull-up on SCL to 3.3V — same
- 100nF decoupling cap on each connector VCC pin

### Relay control lines (× 4)
- 1kΩ series resistor on IN line — current limiting in case relay module lacks it

### MicroSD card (on-board)
- **Push-push MicroSD slot** — SPI bus (GPIO5 CS, GPIO23 MOSI, GPIO19 MISO, GPIO18 SCK)
- 100nF decoupling cap on VCC (3.3V)
- 10kΩ pull-up on CS line — keeps card deselected during boot
- Place close to ESP32 headers to keep SPI traces short

---

## Power architecture

```
12V IN ──┬── Relay coil VCC (direct — via RLY connectors)
         │
         └── Buck module (LM2596) ──── 5V ──┬── ESP32 VIN
                                             ├── Relay module VCC
                                             └── AMS1117-3.3 ──── 3.3V ──── All sensors
                                                                              Pull-ups
```

Decoupling on each rail at the board:
- 12V: 100µF electrolytic + 100nF ceramic
- 5V: 100µF electrolytic + 100nF ceramic
- 3.3V: 100µF electrolytic + 100nF ceramic (AMS1117 output caps)

---

## Cable pinout standard

| Pin | Colour | Signal |
|---|---|---|
| 1 | Red | VCC (3.3V) |
| 2 | Black | GND |
| 3 | Yellow | SIG / DATA / SDA |
| 4 | White | SCL (I2C only) |

---

## EOL test plug wiring

One plug per cable type — used with the Cable_Tester sketch.

| Cable type | Loopback wiring | Tests |
|---|---|---|
| Moisture (3-pin) | Pin 1 (VCC) → Pin 3 (SIG) | Continuity + diode block |
| DHT22 (4-pin) | Pin 1 (VCC) → Pin 3 (DATA) | Continuity + diode block |
| Relay (3-pin) | Pin 1 (VCC) → Pin 3 (IN) | Continuity + diode block |
| I2C (4-pin) | Pin 1 (VCC) → Pin 3 (SDA) | Continuity + diode block |

---

## Status LEDs

| LED | Colour | Indicates |
|---|---|---|
| PWR-12V | Red | 12V present |
| PWR-5V | Yellow | 5V rail good |
| PWR-3V3 | Green | 3.3V rail good |

Simple resistor + LED on each rail — no driver IC needed.

---

## Board layout notes

- **Size: 120 × 100mm** — fits standard enclosures, allows comfortable component spacing
- ESP32 headers centred top half — USB edge faces right board edge
- Buck module top-left — away from I2C lines to minimise switching noise coupling
- Sensor connectors along bottom and right edges, grouped and labelled in silkscreen
- Power screw terminal bottom-left with +/− polarity marking
- Test points on all four rails, accessible without removing modules
- Mounting holes: 4× M3 at corners, 3mm from edge
- Consider panel of 2 on 250 × 100mm for cheaper per-unit fab cost

---

## Enclosure

- **IP65 ABS enclosure** ~130 × 110 × 60mm — allows board + cable glands
- Cable glands: 4× PG7 for sensor clusters, 1× PG9 for 12V power in
- Board mounts on 5mm brass standoffs from enclosure base
- ESP32 USB port aligns with a cutout or removable panel for field reflashing

---

## Next steps

1. Schematic in KiCad — start with power section, then ESP32 headers, then sensor channels
2. Route PCB — keep switching node of buck away from I2C and ADC traces
3. DRC and review Schottky diode orientations before ordering
4. Order prototype from JLCPCB or PCBWay (5× boards ~$10–15 + shipping)
5. Validate all cables with Cable_Tester sketch before first sensor connection
6. Calibrate moisture sensors with Moisture_Calibration sketch after installation
