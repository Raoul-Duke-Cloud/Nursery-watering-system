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
- All 4 zones always populated — DIP switch per zone disables without code changes
- Zone and sensor activity visible via on-board LEDs — no serial monitor needed in the field
- Cables generic and interchangeable within each sensor type
- Cables testable with EOL loopback plugs using the Cable_Tester sketch
- Single 12V input from site rail → all on-board rails derived from it
- Optional Pi co-location header for Nerves site hub deployment

---

## Board overview

```
┌─────────────────────────────────────────────────────────────┐
│  [DC JACK]  [SW1 POWER]  [LED1 12V] [LED2 5V] [LED3 3V3]   │
│                                                             │
│  ┌────────────────┐   ┌──────────────────────────┐          │
│  │  Buck module   │   │   ESP32-DevKitC          │ [USB→]   │
│  │  (on headers)  │   │   (on 2×19 headers)      │          │
│  └────────────────┘   └──────────────────────────┘          │
│                                                             │
│  [DIP SW2: Z-A Z-B Z-C Z-D]   zone enable switches         │
│                                                             │
│  [MST-A] [MST-B] [MST-C] [MST-D]   moisture connectors     │
│  [RLY-A] [RLY-B] [RLY-C] [RLY-D]   relay connectors        │
│  [LED4]  [LED5]  [LED6]  [LED7]     zone active indicators  │
│                                                             │
│  [DHT22]  [I2C-1] [I2C-2] [I2C-3]  shared sensors          │
│                                                             │
│  [MicroSD slot]   [PI-HDR optional]                         │
│                                                             │
│  [TP-GND] [TP-3V3] [TP-5V] [TP-12V]   voltage test points  │
└─────────────────────────────────────────────────────────────┘
```

---

## Modules (socketed)

### ESP32
- **ESP32-DevKitC** (38-pin) on 2 × 19-pin female headers
- Headers raise ESP32 ~8mm above PCB — clearance for USB port access on the side
- USB port faces right board edge for cable access without removing module
- Remove from headers for reflashing if OTA is unavailable

### Buck converter
- **LM2596 module** (or MP2307) on 4-pin headers — 12V in, 5V out, up to 3A
- Pre-built module avoids hand-soldering of switching components
- Header pitch: 2.54mm, 2×2 arrangement (IN+, IN−, OUT+, OUT−)
- 5V output feeds ESP32 VIN, relay module VCC, and AMS1117 input

### 3.3V LDO
- **AMS1117-3.3** SOT-223 — from 5V rail
- Powers all sensors and pull-up resistors
- 100µF + 100nF decoupling on output

---

## Power input and switching

- **DC barrel jack** (DC-005, 2.1mm/5.5mm centre-positive) — replaces screw terminal
  for cleaner cable connection. Rated 5A — sufficient for full board load.
- **SW1 — SPST rocker switch** in series on 12V input line, rated 5A minimum.
  Cuts all power to board including ESP32 and sensors. Place near DC jack.
- Polarity protection: SS14 Schottky on 12V input — prevents reverse connection
  from damaging buck module.

---

## Zone DIP switches (SW2)

- **4-position DIP switch** (SW2) — one position per zone (A/B/C/D)
- Wired in series between ESP32 GPIO and relay IN line (before R1–R4)
- **DIP OFF** = zone IN line pulled LOW via 10kΩ pull-down — relay cannot activate
  regardless of ESP32 state. Safe to use during commissioning.
- **DIP ON** = normal operation, ESP32 controls zone
- Silkscreen labels: Z-A, Z-B, Z-C, Z-D

---

## Zone activity LEDs (LED4–LED7)

One LED per zone, tapped from relay IN line after the DIP switch and series resistor:
- **LED ON** = relay IN is HIGH — zone valve commanded open
- Driven directly from relay IN signal via 1kΩ resistor — no extra GPIO needed
- LEDs labelled by number in silkscreen: LED4 (zone A), LED5 (B), LED6 (C), LED7 (D)

---

## Connectors

All field-side connectors are **JST-XH 2.54mm** — polarised, locking, widely available.

| Ref | Type | Pins | Cable carries | Notes |
|---|---|---|---|---|
| MST-A/B/C/D | JST-XH 3-pin | 4× | VCC / GND / SIG | One per moisture zone |
| RLY-A/B/C/D | JST-XH 3-pin | 4× | VCC / GND / IN | Relay module IN line |
| DHT22 | JST-XH 4-pin | 1× | VCC / GND / DATA / NC | |
| I2C-1/2/3 | JST-XH 4-pin | 3× | VCC / GND / SDA / SCL | Shared bus — BH1750, MLX90614, ADS1115 |
| SD | MicroSD card slot | 1× | SPI (GPIO5/23/19/18) | On-board |
| PWR-IN | DC barrel jack DC-005 | 1× | 12V centre-positive | 2.1mm pin / 5.5mm barrel |
| PI-HDR | 4-pin header 2.54mm | 1× | 5V / GND / TX / RX | Optional Pi UART + power — DNP by default |

---

## Passive components per channel

### Moisture sensors (× 4)
- **SS14 Schottky (SMA)** on VCC line — anode toward connector, cathode toward 3.3V rail
- TVS diode (SMBJ3.3A) on SIG line — clamps transients to 3.3V
- 100nF decoupling cap on VCC pin
- Diode protection verified by Cable_Tester reverse-direction test

### DHT22
- **SS14 Schottky (SMA)** on VCC line — same orientation
- 10kΩ pull-up on DATA to 3.3V (required by 1-wire protocol)
- 100nF decoupling cap on VCC

### I2C bus (shared — all three I2C connectors on same bus)
- **SS14 Schottky (SMA)** on VCC line of each connector
- 4.7kΩ pull-up on SDA to 3.3V — fitted once on bus, not per connector
- 4.7kΩ pull-up on SCL to 3.3V — same
- 100nF decoupling cap on each connector VCC pin

### Relay control lines (× 4)
- DIP switch (SW2) in series — hardware zone disable
- 1kΩ series resistor on IN line (R1–R4) — current limiting
- Zone activity LED (LED4–LED7) tapped from IN line via 1kΩ resistor
- 10kΩ pull-down on IN line to GND — ensures relay off when DIP switch open
- **SS14 flyback diode footprint** on coil side — DNP if using relay modules

### MicroSD card (on-board)
- **Push-push MicroSD slot** — SPI bus (GPIO5 CS, GPIO23 MOSI, GPIO19 MISO, GPIO18 SCK)
- 100nF decoupling cap on VCC (3.3V)
- 10kΩ pull-up on CS line — keeps card deselected during boot
- Place close to ESP32 headers to keep SPI traces short

### 12V input protection
- **SS14 Schottky** on 12V input line (after DC jack, before SW1) — reverse polarity block

---

## Pi / Nerves hub integration (optional)

The Nerves Pi is a site hub — it runs the full NurseryHub app and bridges ESP32 MQTT
to the central server over WAN. The ESP32 connects to the Pi's Mosquitto broker over
**WiFi only** — no physical PCB connection is required.

For installations where Pi and node board share an enclosure:

- **PI-HDR** (4-pin header, DNP by default):
  - Pin 1: 5V from on-board rail (max 500mA available — sufficient for Pi Zero 2W)
  - Pin 2: GND
  - Pin 3: TX → Pi GPIO15 (UART RX) — for debug/local console
  - Pin 4: RX → Pi GPIO14 (UART TX)
- Pi's WiFi connects to same AP as ESP32 — no further PCB integration needed
- If Pi requires more than 500mA (Pi 4 etc.), power separately — do not use PI-HDR 5V

---

## Power architecture

```
DC JACK → SS14 (reverse protect) → SW1 (power switch) → +12V bus
                                                            │
    ┌───────────────────────────────────────────────────────┤
    │                                                       │
    ├── LED1 (12V indicator) via R9                         │
    ├── D14–D17 cathodes (relay flyback DNP)                │
    └── Buck module IN+ ──────────────────── 5V bus         │
                                               │            │
               ┌───────────────────────────────┤            │
               │                               │            │
               ├── ESP32 VIN                   │            │
               ├── RLY-A/B/C/D VCC             │            │
               ├── LED2 (5V indicator) via R10  │            │
               └── AMS1117-3.3 IN ──── 3.3V bus│            │
                                         │      │            │
                    ┌────────────────────┤      │            │
                    ├── All sensor VCC (via Schottky)        │
                    ├── I2C pull-ups                         │
                    ├── DHT22 pull-up                        │
                    └── LED3 (3V3 indicator) via R11         │
                                                             │
GND bus ─────────────────────────────────────────────────────┘
```

Bulk decoupling on each rail: 100µF electrolytic + 100nF ceramic.

---

## Voltage test points

Four **2mm through-hole test point pads** (Keystone 5001 or equivalent), placed in a row
and clearly labelled in silkscreen. Large enough to probe without slipping.

| Ref | Net | Label |
|---|---|---|
| TP1 | GND | GND |
| TP2 | +3V3 | 3V3 |
| TP3 | +5V | 5V |
| TP4 | +12V | 12V |

---

## Status LEDs

All LEDs numbered in silkscreen.

| Ref | Colour | Location | Indicates |
|---|---|---|---|
| LED1 | Red | Near DC jack | 12V power present |
| LED2 | Yellow | Near buck module | 5V rail good |
| LED3 | Green | Near AMS1117 | 3.3V rail good |
| LED4 | Blue | Zone A | Zone A relay IN active |
| LED5 | Blue | Zone B | Zone B relay IN active |
| LED6 | Blue | Zone C | Zone C relay IN active |
| LED7 | Blue | Zone D | Zone D relay IN active |

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

## Bill of Materials

Packages chosen for JLCPCB PCBA compatibility — all SMD except connectors and socketed modules.
Search LCSC for part numbers when setting up the KiCad BOM; verify availability before routing.

| Ref | Component | Value / Part | Package | Qty | Notes |
|---|---|---|---|---|---|
| U1 | ESP32 module | ESP32-DevKitC-32E | 2×19 female headers (2.54mm) | 1 | Socketed — hand-fit after PCBA |
| U2 | Buck converter module | LM2596S-5.0 module | 4-pin female headers (2.54mm) | 1 | Socketed — hand-fit after PCBA |
| U3 | 3.3V LDO | AMS1117-3.3 | SOT-223 | 1 | LCSC: C6186 |
| D1 | Input reverse protect | SS14 | SMA (DO-214AC) | 1 | 12V input line |
| D2–D9 | Schottky diode | SS14 | SMA (DO-214AC) | 8 | Sensor VCC reverse polarity (4× moisture, 1× DHT, 3× I2C) |
| D10–D13 | TVS diode | SMBJ3.3A | SMB (DO-214AA) | 4 | SIG line clamp per moisture zone |
| D14–D17 | Flyback diode | SS14 | SMA (DO-214AC) | 4 | Relay coil side — DNP if using relay modules |
| R1–R4 | Resistor | 1kΩ 1% 125mW | 0402 | 4 | Relay IN series resistors |
| R5, R8 | Resistor | 10kΩ 1% 125mW | 0402 | 2 | DHT22 pull-up, SD CS pull-up |
| R6–R7 | Resistor | 4.7kΩ 1% 125mW | 0402 | 2 | I2C SDA + SCL pull-ups |
| R9–R12 | Resistor | 1kΩ 1% 125mW | 0402 | 4 | Relay IN → zone LED (LED4–LED7) |
| R13 | Resistor | 1kΩ 1% 125mW | 0402 | 1 | LED1 (12V) current limit |
| R14 | Resistor | 1kΩ 1% 125mW | 0402 | 1 | LED2 (5V) current limit |
| R15 | Resistor | 1kΩ 1% 125mW | 0402 | 1 | LED3 (3V3) current limit |
| R16–R19 | Resistor | 10kΩ 1% 125mW | 0402 | 4 | Zone IN pull-downs (DIP switch open = relay off) |
| C1–C3 | Electrolytic cap | 100µF 25V | SMD 6.3×7.7mm | 3 | Bulk decoupling per rail |
| C4–C13 | Ceramic cap | 100nF 25V X7R | 0402 | 10 | Decoupling per sensor VCC + SD |
| LED1 | LED | Red 0805 | 0805 | 1 | 12V power good |
| LED2 | LED | Yellow 0805 | 0805 | 1 | 5V power good |
| LED3 | LED | Green 0805 | 0805 | 1 | 3.3V power good |
| LED4–LED7 | LED | Blue 0805 | 0805 | 4 | Zone A/B/C/D active |
| SW1 | Rocker switch | SPST 5A 250V | Panel mount | 1 | Power on/off — mounts on enclosure |
| SW2 | DIP switch | 4-position | DIP-8 through-hole | 1 | Zone enable/disable |
| J_MST_A–D | JST-XH 3-pin socket | B3B-XH-A | Through-hole | 4 | Moisture zone connectors |
| J_RLY_A–D | JST-XH 3-pin socket | B3B-XH-A | Through-hole | 4 | Relay connectors |
| J_DHT | JST-XH 4-pin socket | B4B-XH-A | Through-hole | 1 | DHT22 |
| J_I2C_1–3 | JST-XH 4-pin socket | B4B-XH-A | Through-hole | 3 | I2C connectors |
| J_PWR | DC barrel jack | DC-005 2.1mm/5.5mm | Through-hole | 1 | 12V input |
| J_PI | 4-pin header 2.54mm | — | Through-hole | 1 | Pi UART + 5V — DNP by default |
| SD1 | MicroSD card slot | DM3AT-SF-PEJM5 | SMD push-push | 1 | LCSC: C114218 or equiv |
| TP1–TP4 | Test point | Keystone 5001 | 2mm through-hole | 4 | GND / 3V3 / 5V / 12V |
| — | Female pin header 19-pin | — | 2.54mm through-hole | 2 | ESP32 sockets |
| — | Female pin header 4-pin | — | 2.54mm through-hole | 1 | Buck module socket |
| — | M3 brass standoff 5mm | — | — | 4 | Board-to-enclosure mounting |
| — | M3 screw + nut | — | — | 8 | — |

> 0402 passives are standard JLCPCB basic parts — cheapest and fastest to assemble.
> Through-hole connectors, socketed modules, SW1, and SW2 are hand-soldered after PCBA.
> Mark all through-hole parts as "do not place" in the PCBA order.

### Cable-side plugs and crimps

| Component | Part | Qty per node | Notes |
|---|---|---|---|
| JST-XH 3-pin housing (cable plug) | XHP-3 | 8 | 4× moisture + 4× relay cables |
| JST-XH 4-pin housing (cable plug) | XHP-4 | 4 | 1× DHT22 + 3× I2C cables |
| JST-XH female crimp contacts | SXH-001T-P0.6 | ~40 | ~3–4 per cable — order extra |
| EOL loopback plug housings | XHP-3 + XHP-4 | 2 of each | One per cable type for Cable_Tester |
| EOL loopback bridge wire | solid core 0.6mm | — | Short loop inside the plug |

> JST-XH crimps require a ratchet crimp tool (PA-09 or Engineer PA-21). Dupont housings
> are a cheaper substitute for prototyping but are not polarised — not recommended for
> permanent installation.

---

## Netlist — complete pin-to-pin connections

Organised by net. Use this to draw the schematic in KiCad or EasyEDA.
See also `Hardware/generate_schematic.py` which generates a KiCad-importable netlist.

| Net | From | Pin | To | Pin | Notes |
|---|---|---|---|---|---|
| **+12V** | J_PWR | 1 | D1 | A | Input via reverse-protect Schottky |
| +12V | D1 | K | SW1 | 1 | Power switch in |
| +12V | SW1 | 2 | U2 | IN+ | Buck module input |
| +12V | SW1 | 2 | C1 | + | Bulk decoupling |
| +12V | SW1 | 2 | R13 | 1 | LED1 current limit |
| +12V | SW1 | 2 | D14 | K | Relay A flyback (DNP) |
| +12V | SW1 | 2 | D15 | K | Relay B flyback (DNP) |
| +12V | SW1 | 2 | D16 | K | Relay C flyback (DNP) |
| +12V | SW1 | 2 | D17 | K | Relay D flyback (DNP) |
| **+5V** | U2 | OUT+ | C2 | + | Bulk decoupling |
| +5V | U2 | OUT+ | U3 | IN | LDO input |
| +5V | U2 | OUT+ | U1 | VIN | ESP32 power |
| +5V | U2 | OUT+ | J_RLY_A | 1 | Relay A module VCC |
| +5V | U2 | OUT+ | J_RLY_B | 1 | Relay B module VCC |
| +5V | U2 | OUT+ | J_RLY_C | 1 | Relay C module VCC |
| +5V | U2 | OUT+ | J_RLY_D | 1 | Relay D module VCC |
| +5V | U2 | OUT+ | R14 | 1 | LED2 current limit |
| +5V | U2 | OUT+ | J_PI | 1 | Pi 5V (DNP) |
| **+3V3** | U3 | OUT | C3 | + | Bulk decoupling |
| +3V3 | U3 | OUT | D2 | K | MST-A VCC Schottky cathode |
| +3V3 | U3 | OUT | D3 | K | MST-B VCC Schottky cathode |
| +3V3 | U3 | OUT | D4 | K | MST-C VCC Schottky cathode |
| +3V3 | U3 | OUT | D5 | K | MST-D VCC Schottky cathode |
| +3V3 | U3 | OUT | D6 | K | DHT VCC Schottky cathode |
| +3V3 | U3 | OUT | D7 | K | I2C-1 VCC Schottky cathode |
| +3V3 | U3 | OUT | D8 | K | I2C-2 VCC Schottky cathode |
| +3V3 | U3 | OUT | D9 | K | I2C-3 VCC Schottky cathode |
| +3V3 | U3 | OUT | R5 | 1 | DHT22 DATA pull-up |
| +3V3 | U3 | OUT | R6 | 1 | SDA pull-up |
| +3V3 | U3 | OUT | R7 | 1 | SCL pull-up |
| +3V3 | U3 | OUT | R8 | 1 | SD CS pull-up |
| +3V3 | U3 | OUT | SD1 | VCC | MicroSD power |
| +3V3 | U3 | OUT | R15 | 1 | LED3 current limit |
| **GND** | J_PWR | 2 | U2 | IN− | Common GND |
| GND | U2 | OUT− | U3 | GND | |
| GND | U2 | OUT− | U1 | GND | ESP32 GND |
| GND | C1 | − | GND | — | |
| GND | C2 | − | GND | — | |
| GND | C3 | − | GND | — | |
| GND | C4–C13 | 2 | GND | — | All decoupling caps |
| GND | J_MST_A–D | 2 | GND | — | All sensor connector GNDs |
| GND | J_RLY_A–D | 2 | GND | — | |
| GND | J_DHT | 2 | GND | — | |
| GND | J_I2C_1–3 | 2 | GND | — | |
| GND | SD1 | GND | GND | — | |
| GND | D10–D13 | A | GND | — | TVS anode to GND |
| GND | D14–D17 | A | GND | — | Flyback anode to GND |
| GND | R16–R19 | 2 | GND | — | Zone IN pull-downs |
| GND | LED1–LED7 | K | GND | — | All LED cathodes |
| GND | J_PI | 2 | GND | — | Pi GND (DNP) |
| GND | TP1 | 1 | GND | — | Test point |
| **MST_A_VCC** | D2 | A | J_MST_A | 1 | Protected 3V3 to moisture sensor A |
| MST_A_VCC | J_MST_A | 1 | C4 | 1 | Decoupling |
| **MST_B_VCC** | D3 | A | J_MST_B | 1 | |
| MST_B_VCC | J_MST_B | 1 | C5 | 1 | |
| **MST_C_VCC** | D4 | A | J_MST_C | 1 | |
| MST_C_VCC | J_MST_C | 1 | C6 | 1 | |
| **MST_D_VCC** | D5 | A | J_MST_D | 1 | |
| MST_D_VCC | J_MST_D | 1 | C7 | 1 | |
| **MST_A_SIG** | J_MST_A | 3 | U1 | GPIO32 | |
| MST_A_SIG | J_MST_A | 3 | D10 | K | TVS cathode to signal line |
| **MST_B_SIG** | J_MST_B | 3 | U1 | GPIO33 | |
| MST_B_SIG | J_MST_B | 3 | D11 | K | |
| **MST_C_SIG** | J_MST_C | 3 | U1 | GPIO34 | |
| MST_C_SIG | J_MST_C | 3 | D12 | K | |
| **MST_D_SIG** | J_MST_D | 3 | U1 | GPIO35 | |
| MST_D_SIG | J_MST_D | 3 | D13 | K | |
| **RLY_A_IN** | U1 | GPIO25 | SW2 | Z-A in | DIP switch zone A |
| RLY_A_IN | SW2 | Z-A out | R1 | 1 | Series resistor |
| RLY_A_IN | R1 | 2 | J_RLY_A | 3 | Relay A IN |
| RLY_A_IN | R1 | 2 | R9 | 1 | Zone A LED tap |
| RLY_A_IN | R1 | 2 | R16 | 1 | Pull-down (other end to GND) |
| **RLY_B_IN** | U1 | GPIO26 | SW2 | Z-B in | |
| RLY_B_IN | SW2 | Z-B out | R2 | 1 | |
| RLY_B_IN | R2 | 2 | J_RLY_B | 3 | |
| RLY_B_IN | R2 | 2 | R10 | 1 | |
| RLY_B_IN | R2 | 2 | R17 | 1 | |
| **RLY_C_IN** | U1 | GPIO13 | SW2 | Z-C in | |
| RLY_C_IN | SW2 | Z-C out | R3 | 1 | |
| RLY_C_IN | R3 | 2 | J_RLY_C | 3 | |
| RLY_C_IN | R3 | 2 | R11 | 1 | |
| RLY_C_IN | R3 | 2 | R18 | 1 | |
| **RLY_D_IN** | U1 | GPIO14 | SW2 | Z-D in | |
| RLY_D_IN | SW2 | Z-D out | R4 | 1 | |
| RLY_D_IN | R4 | 2 | J_RLY_D | 3 | |
| RLY_D_IN | R4 | 2 | R12 | 1 | |
| RLY_D_IN | R4 | 2 | R19 | 1 | |
| **ZONE_A_LED** | R9 | 2 | LED4 | A | Zone A active indicator |
| **ZONE_B_LED** | R10 | 2 | LED5 | A | |
| **ZONE_C_LED** | R11 | 2 | LED6 | A | |
| **ZONE_D_LED** | R12 | 2 | LED7 | A | |
| **DHT_VCC** | D6 | A | J_DHT | 1 | Protected 3V3 |
| DHT_VCC | J_DHT | 1 | C8 | 1 | Decoupling |
| **DHT_DATA** | J_DHT | 3 | U1 | GPIO27 | |
| DHT_DATA | R5 | 2 | U1 | GPIO27 | Pull-up |
| **I2C_1_VCC** | D7 | A | J_I2C_1 | 1 | Protected 3V3 |
| I2C_1_VCC | J_I2C_1 | 1 | C9 | 1 | |
| **I2C_2_VCC** | D8 | A | J_I2C_2 | 1 | |
| I2C_2_VCC | J_I2C_2 | 1 | C10 | 1 | |
| **I2C_3_VCC** | D9 | A | J_I2C_3 | 1 | |
| I2C_3_VCC | J_I2C_3 | 1 | C11 | 1 | |
| **SDA** | U1 | GPIO21 | R6 | 2 | Pull-up other end to +3V3 |
| SDA | U1 | GPIO21 | J_I2C_1 | 3 | |
| SDA | U1 | GPIO21 | J_I2C_2 | 3 | |
| SDA | U1 | GPIO21 | J_I2C_3 | 3 | |
| **SCL** | U1 | GPIO22 | R7 | 2 | Pull-up other end to +3V3 |
| SCL | U1 | GPIO22 | J_I2C_1 | 4 | |
| SCL | U1 | GPIO22 | J_I2C_2 | 4 | |
| SCL | U1 | GPIO22 | J_I2C_3 | 4 | |
| **SD_CS** | U1 | GPIO5 | SD1 | CS | |
| SD_CS | R8 | 2 | SD1 | CS | Pull-up other end to +3V3 |
| **SD_MOSI** | U1 | GPIO23 | SD1 | MOSI | |
| **SD_MISO** | U1 | GPIO19 | SD1 | MISO | |
| **SD_SCK** | U1 | GPIO18 | SD1 | SCK | |
| **LED1_NET** | R13 | 2 | LED1 | A | 12V → R13 → LED1 → GND |
| **LED2_NET** | R14 | 2 | LED2 | A | 5V → R14 → LED2 → GND |
| **LED3_NET** | R15 | 2 | LED3 | A | 3V3 → R15 → LED3 → GND |
| **TP2** | TP2 | 1 | +3V3 | — | Test point |
| **TP3** | TP3 | 1 | +5V | — | Test point |
| **TP4** | TP4 | 1 | +12V | — | Test point |
| **PI_TX** | J_PI | 3 | U1 | GPIO1 | ESP32 TX → Pi RX (DNP) |
| **PI_RX** | J_PI | 4 | U1 | GPIO3 | ESP32 RX → Pi TX (DNP) |

---

## Board layout notes

- **Size: 120 × 100mm**
- DC jack and power switch top-left, power LEDs (LED1–LED3) alongside
- Buck module top-left quadrant — away from I2C and ADC traces to minimise switching noise
- ESP32 headers centred — USB edge faces right board edge, accessible without opening enclosure
- DIP switch (SW2) below ESP32, clearly silkscreened Z-A through Z-D
- Zone connectors (MST + RLY pairs) along bottom edge, zone LEDs (LED4–LED7) between them
- Shared sensor connectors (DHT, I2C × 3) along right edge
- MicroSD slot bottom-right, close to ESP32 SPI pins
- Test points in a row, bottom-centre, large 2mm pads
- Mounting holes: 4× M3 at corners, 3mm from edge

---

## Enclosure

- **IP65 ABS enclosure** ~130 × 110 × 60mm
- Cable glands: 4× PG7 for sensor clusters, 1× PG9 for 12V power in
- SW1 rocker switch mounts through enclosure front panel
- ESP32 USB port aligns with removable panel or cutout on enclosure side
- Board mounts on 5mm brass standoffs from enclosure base

---

## JLCPCB PCBA ordering

Boards are ordered **fully assembled** (PCBA) — all SMD components placed and soldered by JLCPCB.
Through-hole parts (connectors, socketed modules, SW1, SW2, test points) are hand-soldered after delivery.

### What to export from KiCad

1. **Gerbers + drill files** — File > Plot (Gerber format), then File > Drill Files
2. **BOM (bill of materials)** — a CSV with: Comment, Designator, Footprint, LCSC Part #
3. **CPL (component placement list)** — File > Fabrication Outputs > Component Placement (`.csv`)
   KiCad calls this "Footprint Position File"

Upload all three to JLCPCB's online order form under "SMT Assembly".

### PCBA checklist

- [ ] All SMD parts (R, C, D, LED, U3, SD1) included in BOM with LCSC part numbers
- [ ] Through-hole parts (J_MST, J_RLY, J_DHT, J_I2C, J_PWR, J_PI, SW2, TP1–4) marked **DNP** in BOM
- [ ] SW1 (panel-mount rocker) marked **DNP** — fit to enclosure separately
- [ ] ESP32 socket headers (female 2×19) marked **DNP** — hand-solder after PCBA
- [ ] Buck module socket headers (female 1×4) marked **DNP** — hand-solder after PCBA
- [ ] D14–D17 (relay flyback) marked **DNP** — only fit if driving coils directly
- [ ] J_PI (Pi header) marked **DNP** — only fit if co-locating Pi

### Hand-soldering order after PCBA delivery

1. Female headers for ESP32 and buck module sockets
2. All JST-XH connectors (J_MST, J_RLY, J_DHT, J_I2C)
3. DC barrel jack (J_PWR)
4. DIP switch (SW2)
5. Test point pads (TP1–TP4)
6. Pi header (J_PI) — if needed
7. Fit ESP32 and buck module into sockets
8. Wire SW1 rocker switch via short cable to PCB pads or screw terminal

---

## Next steps

1. Open KiCad — run `Hardware/generate_schematic.py` to import the netlist as a starting point
2. Assign footprints to any unresolved symbols
3. Route PCB — keep switching node of buck away from I2C and ADC traces
4. DRC and verify Schottky diode orientations before ordering
5. Export Gerbers, BOM (with LCSC part numbers), and CPL from KiCad
6. Order from JLCPCB with PCBA — 5× boards fully assembled
7. Hand-solder through-hole parts after delivery (see checklist above)
8. Validate all cables with Cable_Tester sketch before first sensor connection
9. Calibrate moisture sensors with Moisture_Calibration sketch after installation
