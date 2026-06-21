# NurseryHub Node Board v2 — Full Design Specification

Version: 2.0  
Status: SIGNED OFF 2026-06-20  
Previous version (v0.1) had: reversed D1, wrong U3 pinout, reversed LEDs, reversed TVS diodes, wrong ESP32 footprint and net assignments, floating SD card shield.

---

## Guiding rules for this revision

1. All active components through-hole or socketed modules — no bare SMD ICs except U3 (AMS1117 SOT-223)
2. Every polarised component has its polarity explicitly called out in this spec, in the schematic, and in silkscreen
3. Every net connection is listed in the netlist table below — no assumptions
4. Test protocol runs at three gates: KiCad checks, bare board, post-assembly
5. Nothing gets sent to fab until all three gates are passed and documented

---

## Board overview

Single node board per field installation. Accepts 12V from site rail. Drives 4 irrigation zones via relay modules. Reads 4 capacitive moisture sensors, DHT22, and up to 3 I2C sensors. ESP32-DevKitC socketed on female headers — removable for reflashing.

**Board size:** 120 × 100mm  
**Layer count:** 2  
**All components:** through-hole or socketed modules except U3 (AMS1117 SOT-223)

---

## Component list

| Ref | Component | Value / Part | Package | Qty | Notes |
|---|---|---|---|---|---|
| U1 | ESP32-DevKitC | ESP32-DevKitC-32E | 2×19 female headers 2.54mm | 1 | Socketed — remove for reflashing |
| U2 | Buck converter module | LM2596 5V module | 1×4 female header 2.54mm tall (15mm riser) | 1 | Socketed on elevated female headers — module sits ~15mm above board. If module has mounting holes, add M3 brass standoffs at same height for mechanical support. Measure your specific module before ordering headers. |
| U3 | 3.3V LDO | AMS1117-3.3 | SOT-223 (SMD — only SMD component) | 1 | Pin 1=GND, Pin 2=OUTPUT, Pin 3=INPUT, Tab=OUTPUT |
| SD_MOD | MicroSD breakout module | Any standard 6-pin SPI breakout | 1×6 female header 2.54mm | 1 | Socketed |
| D1 | Input reverse protect | 1N5819 | DO-41 axial through-hole | 1 | Anode toward DC jack, Cathode toward SW1 |
| D2–D5 | Moisture sensor VCC protect | 1N5819 | DO-41 axial through-hole | 4 | Anode toward +3V3, Cathode toward connector |
| D6 | DHT22 VCC protect | 1N5819 | DO-41 axial through-hole | 1 | Anode toward +3V3, Cathode toward connector |
| D7–D9 | I2C sensor VCC protect | 1N5819 | DO-41 axial through-hole | 3 | Anode toward +3V3, Cathode toward connector |
| D10–D13 | Moisture SIG TVS clamp | P6KE3.3A | DO-15 axial through-hole | 4 | Cathode toward signal line, Anode toward GND |
| D14–D17 | Relay flyback | 1N4007 | DO-41 axial through-hole | 4 | DNP if using relay modules with onboard flyback |
| R1–R4 | Relay IN series | 1kΩ | 1/4W axial through-hole | 4 | No polarity |
| R5 | DHT22 DATA pull-up | 10kΩ | 1/4W axial through-hole | 1 | No polarity |
| R6 | I2C SDA pull-up | 4.7kΩ | 1/4W axial through-hole | 1 | No polarity |
| R7 | I2C SCL pull-up | 4.7kΩ | 1/4W axial through-hole | 1 | No polarity |
| R8 | SD CS pull-up | 10kΩ | 1/4W axial through-hole | 1 | No polarity |
| R9–R12 | Zone LED | 1kΩ | 1/4W axial through-hole | 4 | No polarity |
| R13 | LED1 current limit | 1kΩ | 1/4W axial through-hole | 1 | No polarity |
| R14 | LED2 current limit | 1kΩ | 1/4W axial through-hole | 1 | No polarity |
| R15 | LED3 current limit | 1kΩ | 1/4W axial through-hole | 1 | No polarity |
| R16–R19 | Zone IN pull-down | 10kΩ | 1/4W axial through-hole | 4 | No polarity |
| C1 | 12V bulk decoupling | 100µF 25V | Electrolytic radial 5mm pitch | 1 | +lead to +12V, −lead to GND |
| C2 | 5V bulk decoupling | 100µF 25V | Electrolytic radial 5mm pitch | 1 | +lead to +5V, −lead to GND |
| C3 | 3.3V bulk decoupling | 100µF 16V | Electrolytic radial 5mm pitch | 1 | +lead to +3V3, −lead to GND |
| C4–C13 | Sensor VCC decoupling | 100nF 25V | Ceramic disc through-hole | 10 | No polarity |
| LED1 | 12V power indicator | Red 5mm | Through-hole 5mm | 1 | Anode toward R13, Cathode to GND |
| LED2 | 5V power indicator | Yellow 5mm | Through-hole 5mm | 1 | Anode toward R14, Cathode to GND |
| LED3 | 3.3V power indicator | Green 5mm | Through-hole 5mm | 1 | Anode toward R15, Cathode to GND |
| LED4–LED7 | Zone A/B/C/D active | Blue 3mm | Through-hole 3mm | 4 | Anode toward R9–R12, Cathode to GND |
| SW1 | Power switch | SPST rocker 5A | Panel mount | 1 | In series on 12V line — wired via cable to PCB terminals |
| SW2 | Zone enable | 4-position DIP | DIP-8 through-hole | 1 | No polarity |
| J_PWR | 12V power input | Screw terminal 2-pin 5.08mm pitch | Through-hole | 1 | Pin 1=12V+, Pin 2=GND — labelled on silkscreen. Phoenix MC 1,5/2-ST-3.81 or equivalent — NOT 2.54mm pitch |
| J_SW1 | Power switch header | Screw terminal 2-pin 5.08mm pitch | Through-hole | 1 | Connects to panel-mount SW1 via cable. Same 5.08mm pitch as J_PWR |
| J_ZONE_A–D | Zone connectors (moisture + relay combined) | RJ45 jack 8P8C | Through-hole vertical | 4 | See zone RJ45 pinout table |
| J_I2C_1–3 | I2C sensor connectors | RJ45 jack 8P8C | Through-hole vertical | 3 | See I2C RJ45 pinout table |
| J_DHT | DHT22 connector | RJ45 jack 8P8C | Through-hole vertical | 1 | See DHT22 RJ45 pinout table |
| J_PI | Pi UART header | 4-pin header 2.54mm | Through-hole | 1 | DNP by default. Pin 1=5V, Pin 2=GND, Pin 3=TX, Pin 4=RX |
| TP1–TP33 | Test points | 2mm through-hole pad | Through-hole | 33 | See Test Points section for full list |

---

## RJ45 pinouts

All connectors use standard 8P8C (RJ45) jacks. Signals are assigned to twisted pairs for noise rejection. Pin numbering follows T568B standard (pin 1 = tab latch facing down, left to right).

### Zone jack (×4) — J_ZONE_A, J_ZONE_B, J_ZONE_C, J_ZONE_D

One cable per zone carries both moisture sensor and relay signals.

| Pin | T568B wire | Twisted pair | Signal |
|---|---|---|---|
| 1 | White/Orange | Pair 2 | MST_SIG (ADC signal) |
| 2 | Orange | Pair 2 | GND |
| 3 | White/Green | Pair 3 | MST_VCC (3.3V) |
| 4 | Blue | Pair 1 | RLY_IN (relay control) |
| 5 | White/Blue | Pair 1 | GND |
| 6 | Green | Pair 3 | GND |
| 7 | White/Brown | Pair 4 | RLY_5V |
| 8 | Brown | Pair 4 | GND |

At the sensor/relay end: terminate to Zone Satellite Board (see Satellite Boards section). Cat5e patch cable runs between main board RJ45 jack and satellite board RJ45 jack.

### I2C jack (×3) — J_I2C_1, J_I2C_2, J_I2C_3

| Pin | T568B wire | Twisted pair | Signal |
|---|---|---|---|
| 1 | White/Orange | Pair 2 | SDA |
| 2 | Orange | Pair 2 | GND |
| 3 | White/Green | Pair 3 | VCC (3.3V) |
| 4 | Blue | Pair 1 | SCL |
| 5 | White/Blue | Pair 1 | GND |
| 6 | Green | Pair 3 | GND |
| 7 | White/Brown | Pair 4 | NC |
| 8 | Brown | Pair 4 | NC |

### DHT22 jack (×1) — J_DHT

| Pin | T568B wire | Twisted pair | Signal |
|---|---|---|---|
| 1 | White/Orange | Pair 2 | DATA |
| 2 | Orange | Pair 2 | GND |
| 3 | White/Green | Pair 3 | VCC (3.3V) |
| 4 | Blue | Pair 1 | NC |
| 5 | White/Blue | Pair 1 | GND |
| 6 | Green | Pair 3 | GND |
| 7 | White/Brown | Pair 4 | NC |
| 8 | Brown | Pair 4 | NC |

---

## Power architecture

```
J_PWR pin1 (+12V) → D1 (Anode) → D1 (Cathode) → J_SW1 → SW1 → J_SW1 → +12V bus
J_PWR pin2 (GND) → GND bus

+12V bus → C1 (+) [bulk decoupling, − to GND]
+12V bus → R13 → LED1 (Anode) → LED1 (Cathode) → GND  [12V indicator]
+12V bus → U2 (Buck IN+)
U2 (Buck IN−) → GND bus
U2 (Buck OUT+) → +5V bus
U2 (Buck OUT−) → GND bus

+5V bus → C2 (+) [bulk decoupling, − to GND]
+5V bus → U1 VIN  [ESP32 DevKitC — onboard regulator handles 5V→3.3V]
+5V bus → J_ZONE_A–D pin7 (RLY_5V)  [relay module VCC via RJ45]
+5V bus → R14 → LED2 (Anode) → LED2 (Cathode) → GND  [5V indicator]
+5V bus → U3 pin3 (INPUT)
+5V bus → J_PI pin1  [Pi 5V, DNP]

U3 pin1 (GND/ADJ) → GND bus
U3 pin2 (OUTPUT) → +3V3 bus  [Tab also OUTPUT — connects to +3V3 bus]
U3 pin3 (INPUT) → +5V bus

+3V3 bus → C3 (+) [bulk decoupling, − to GND]
+3V3 bus → R15 → LED3 (Anode) → LED3 (Cathode) → GND  [3.3V indicator]
+3V3 bus → D2–D9 (Anode of each)  [sensor VCC supply through protection diodes]
+3V3 bus → R5 pin1  [DHT22 pull-up]
+3V3 bus → R6 pin1  [SDA pull-up]
+3V3 bus → R7 pin1  [SCL pull-up]
+3V3 bus → R8 pin1  [SD CS pull-up]
+3V3 bus → SD_MOD VCC
```

**D1 orientation check:** Band (Cathode) faces AWAY from J_PWR, toward SW1/+12V bus.  
**D2–D9 orientation check:** Band (Cathode) faces AWAY from +3V3 rail, toward sensor connector.  
**U3 orientation check:** Viewing SOT-223 from front with tab at back — pin 1 (left) to GND, pin 2 (middle) to +3V3, pin 3 (right) to +5V. Tab to +3V3 copper pour.

---

## ESP32 GPIO assignments

| GPIO | Net | Connected to |
|---|---|---|
| VIN | +5V | Buck output |
| GND | GND | GND bus (connect all GND pins on both headers) |
| GPIO32 | MST_A_SIG | Moisture zone A ADC |
| GPIO33 | MST_B_SIG | Moisture zone B ADC |
| GPIO34 | MST_C_SIG | Moisture zone C ADC |
| GPIO35 | MST_D_SIG | Moisture zone D ADC |
| GPIO25 | RLY_A_SW | Zone A relay DIP input |
| GPIO26 | RLY_B_SW | Zone B relay DIP input |
| GPIO13 | RLY_C_SW | Zone C relay DIP input |
| GPIO14 | RLY_D_SW | Zone D relay DIP input |
| GPIO27 | DHT_DATA | DHT22 data |
| GPIO21 | SDA | I2C SDA bus |
| GPIO22 | SCL | I2C SCL bus |
| GPIO5 | SD_CS | SD card chip select |
| GPIO23 | SD_MOSI | SD card MOSI |
| GPIO19 | SD_MISO | SD card MISO |
| GPIO18 | SD_SCK | SD card SCK |
| GPIO1 (TXD) | PI_TX | Pi UART RX (DNP) |
| GPIO3 (RXD) | PI_RX | Pi UART TX (DNP) |
| 3V3 | +3V3_ESP | ESP32 3.3V output — do NOT connect to main 3V3 bus |
| EN | NC | Leave unconnected on PCB (DevKitC has onboard pull-up) |

**Note:** The DevKitC has multiple GND pins on both headers. ALL of them must be connected to the board GND bus — not just one.

---

## Zone circuit (repeated ×4 for A/B/C/D)

All zone signals exit via the single RJ45 zone jack (J_ZONE_X). See RJ45 pinout table above.

```
ESP32 GPIO → RLY_X_SW
RLY_X_SW → SW2 (DIP switch input side)
SW2 (DIP switch output side) → RLY_X_IN
RLY_X_IN → R_series (1kΩ) → RLY_X_OUT
RLY_X_IN → R_pulldown (10kΩ) → GND
RLY_X_OUT → J_ZONE_X pin4 (RLY_IN)
RLY_X_OUT → R_led (1kΩ) → LED_zone (Anode) → LED_zone (Cathode) → GND
J_ZONE_X pin7 → +5V (RLY_5V)
J_ZONE_X pin2 → GND
J_ZONE_X pin5 → GND
J_ZONE_X pin6 → GND
J_ZONE_X pin8 → GND

+3V3 → D_moisture (Anode) → D_moisture (Cathode) → MST_X_VCC
MST_X_VCC → J_ZONE_X pin3 (MST_VCC)
MST_X_VCC → C_decoupling (100nF) → GND
J_ZONE_X pin1 → MST_X_SIG → D_TVS (Cathode) [Anode to GND] → ESP32 GPIO ADC
```

**D_moisture (1N5819) orientation:** Anode to +3V3 rail, Cathode (banded end) toward RJ45 jack.  
**D_TVS (P6KE3.3A) orientation:** Cathode (banded end) to signal line (pin 1), Anode to GND.

---

## DHT22 circuit

```
+3V3 → D6 (Anode) → D6 (Cathode) → DHT_VCC
DHT_VCC → J_DHT pin3 (VCC)
DHT_VCC → C8 (100nF) → GND
J_DHT pin2 → GND
J_DHT pin5 → GND
J_DHT pin6 → GND
J_DHT pin1 → DHT_DATA
DHT_DATA → R5 (10kΩ) → +3V3  [pull-up]
DHT_DATA → ESP32 GPIO27
```

---

## I2C bus circuit

```
+3V3 → R6 (4.7kΩ) → SDA
+3V3 → R7 (4.7kΩ) → SCL
SDA → ESP32 GPIO21
SCL → ESP32 GPIO22
SDA → J_I2C_1 pin1, J_I2C_2 pin1, J_I2C_3 pin1
SCL → J_I2C_1 pin4, J_I2C_2 pin4, J_I2C_3 pin4

For each I2C connector (1/2/3):
+3V3 → D_i2c (Anode) → D_i2c (Cathode) → I2C_X_VCC
I2C_X_VCC → J_I2C_X pin3 (VCC)
I2C_X_VCC → C_decoupling (100nF) → GND
J_I2C_X pin2 → GND
J_I2C_X pin5 → GND
J_I2C_X pin6 → GND
```

---

## SD card module circuit

```
+3V3 → SD_MOD VCC
GND → SD_MOD GND  [all GND pins on module]
GND → SD_MOD shell/shield  [explicit GND connection]
SD_MOD CS → SD_CS → ESP32 GPIO5
SD_MOD MOSI → SD_MOSI → ESP32 GPIO23
SD_MOD MISO → SD_MISO → ESP32 GPIO19
SD_MOD SCK → SD_SCK → ESP32 GPIO18
+3V3 → R8 (10kΩ) → SD_CS  [CS pull-up]
```

---

## Silkscreen requirements

Every polarised component must have polarity marked. Every connector must have pin 1 marked. Every named net must have a track label at each junction and at each end of long runs.

### Component polarity and labels

| Component | Required silkscreen marking |
|---|---|
| D1 | Ref, cathode bar, "12V PROTECT" label |
| D2–D5 | Ref, cathode bar, "VCC→" arrow |
| D6 | Ref, cathode bar, "DHT VCC" label |
| D7–D9 | Ref, cathode bar, "I2C VCC" label |
| D10–D13 | Ref, cathode bar, "K→SIG" label, zone letter (A/B/C/D) |
| D14–D17 | Ref, cathode bar, "DNP FLYBACK" label |
| LED1–LED3 | Ref, "+" on anode hole, colour label (RED 12V / YEL 5V / GRN 3V3) |
| LED4–LED7 | Ref, "+" on anode hole, zone label (ZA/ZB/ZC/ZD) |
| C1–C3 | Ref, "+" on positive hole, rail label (12V / 5V / 3V3) |
| U3 | Ref, pin numbers 1/2/3, "GND" on pin 1, "OUT" on pin 2, "IN" on pin 3, "TAB=OUT" on tab pad |
| U1 socket | "ESP32-DEVKITC", "USB→" arrow, pin 1 corner marked, GPIO number next to every connected pin |
| U2 socket | "BUCK 5V", IN+/IN−/OUT+/OUT− on each pin |
| SD_MOD socket | "SD CARD", VCC/GND/CS/MOSI/MISO/SCK on each pin |
| J_PWR | "12V+" and "GND" |
| J_SW1 | "POWER SWITCH" |
| J_ZONE_A–D | Zone letter (A/B/C/D), "pin1" marked, pin labels: 1=MST-SIG / 2=GND / 3=MST-VCC / 4=RLY-IN / 5=GND / 6=GND / 7=RLY-5V / 8=GND |
| J_I2C_1–3 | "I2C" and connector number, "pin1" marked, pin labels: SDA/GND/VCC/SCL/GND/GND |
| J_DHT | "DHT22", "pin1" marked, pin labels: DATA/GND/VCC |
| J_PI | "PI UART DNP", 5V/GND/TX/RX |
| SW2 | "ZONE ENABLE", position labels: A / B / C / D |
| TP1–TP4 | Ref and rail name (GND / 3V3 / 5V / 12V) |

### Track net labels

Print net name on silkscreen layer adjacent to track at every junction, branch point, and at both ends of any run longer than 20mm.

| Net | Label text |
|---|---|
| +12V (post D1, post SW1) | `+12V` |
| +5V | `+5V` |
| +3V3 | `+3V3` |
| GND | `GND` (at major junctions only — not every via) |
| MST_A_SIG through MST_D_SIG | `MST-A` / `MST-B` / `MST-C` / `MST-D` |
| MST_A_VCC through MST_D_VCC | `MST-A-VCC` / etc. |
| RLY_A_SW through RLY_D_SW | `RLY-A-SW` / etc. (GPIO output side) |
| RLY_A_IN through RLY_D_IN | `RLY-A-IN` / etc. (after DIP switch) |
| SDA | `SDA` |
| SCL | `SCL` |
| DHT_DATA | `DHT-DATA` |
| DHT_VCC | `DHT-VCC` |
| SD_CS | `SD-CS` |
| SD_MOSI | `SD-MOSI` |
| SD_MISO | `SD-MISO` |
| SD_SCK | `SD-SCK` |
| I2C_1_VCC / I2C_2_VCC / I2C_3_VCC | `I2C1-VCC` / `I2C2-VCC` / `I2C3-VCC` |

---

## Test points

All test points are 2mm through-hole pads. Silkscreen on each pad includes ref, signal name, and expected value.

### Power chain

| Ref | Net | Silkscreen label | Expected value |
|---|---|---|---|
| TP1 | GND | GND | 0V |
| TP2 | +3V3 | 3V3 | 3.3V |
| TP3 | +5V | 5V | 5.0V |
| TP4 | +12V | 12V | 12.0V |
| TP5 | +12V after SW1 | 12V-SW | 12V when SW1 on, 0V when off |
| TP6 | +3V3_ESP | 3V3-ESP | 3.3V when ESP32 running |

### Zone A (TP7–TP10) — repeat pattern: Zone B TP11–TP14, Zone C TP15–TP18, Zone D TP19–TP22

| Ref | Net | Silkscreen label | Expected value |
|---|---|---|---|
| TP7 | MST_A_VCC | MST-A-VCC | ~3.0V (3V3 minus diode drop) |
| TP8 | MST_A_SIG | MST-A-SIG | 0.5–3.0V with sensor connected |
| TP9 | RLY_A_SW | RLY-A-SW | 0V idle, 3.3V when watering |
| TP10 | RLY_A_IN | RLY-A-IN | 0V when DIP off, follows SW when DIP on |

### I2C bus

| Ref | Net | Silkscreen label | Expected value |
|---|---|---|---|
| TP23 | SDA | SDA | 3.3V idle, pulses during comms |
| TP24 | SCL | SCL | 3.3V idle, pulses during comms |
| TP25 | I2C_1_VCC | I2C1-VCC | ~3.0V |
| TP26 | I2C_2_VCC | I2C2-VCC | ~3.0V |
| TP27 | I2C_3_VCC | I2C3-VCC | ~3.0V |

### DHT22

| Ref | Net | Silkscreen label | Expected value |
|---|---|---|---|
| TP28 | DHT_VCC | DHT-VCC | ~3.0V |
| TP29 | DHT_DATA | DHT-DATA | 3.3V idle, pulses every 2s |

### SD card

| Ref | Net | Silkscreen label | Expected value |
|---|---|---|---|
| TP30 | SD_CS | SD-CS | 3.3V idle (pulled high), 0V during access |
| TP31 | SD_MOSI | SD-MOSI | pulses during access |
| TP32 | SD_MISO | SD-MISO | pulses during access |
| TP33 | SD_SCK | SD-SCK | pulses during access |

---

## Test protocol

### Gate 1 — KiCad checks (before ordering PCB)

Run these in KiCad before generating Gerbers. All must pass with zero errors.

- [ ] **ERC (Electrical Rules Check)** — zero errors, zero warnings
- [ ] **DRC (Design Rules Check)** — zero errors
- [ ] **Net inspector** — verify these nets exist and have the right number of pins connected:
  - `+12V` — J_PWR, D1, C1, R13, U2, SW1
  - `+5V` — U2, C2, U3, U1-VIN, J_ZONE×4 pin7, R14, J_PI
  - `+3V3` — U3, C3, D2–D9, R5, R6, R7, R8, SD_MOD, R15
  - `GND` — large fan-out, check count is >30 connections
  - `SDA` — R6, U1-GPIO21, J_I2C×3
  - `SCL` — R7, U1-GPIO22, J_I2C×3
  - `SD_CS` — U1-GPIO5, R8, SD_MOD
- [ ] **Footprint review** — open 3D viewer, visually confirm:
  - U1 socket matches DevKitC board outline
  - All diodes oriented with cathode band matching silkscreen
  - All electrolytic caps oriented with + matching silkscreen
  - U3 tab faces correct direction
- [ ] **Gerber review** — open in Gerber viewer (KiCad built-in or gerbv):
  - Silkscreen polarity marks visible on all diodes and LEDs
  - Pin 1 markers visible on all connectors
  - Test point labels visible
  - No silkscreen text overlapping pads

---

### Gate 2 — Bare board checks (PCB received, before soldering anything)

Do these with a multimeter before touching a soldering iron.

- [ ] **Visual inspection** — no shorts visible between pads, no damaged traces
- [ ] **Continuity — GND bus** — probe TP1 (GND) to every GND pad visible. All should beep.
- [ ] **Isolation — power rails** — with board unpowered, probe between:
  - TP4 (+12V pad) and TP1 (GND) — should be open circuit (no beep)
  - TP3 (+5V pad) and TP1 (GND) — should be open circuit
  - TP2 (+3V3 pad) and TP1 (GND) — should be open circuit
  - If any beep: trace short before proceeding
- [ ] **Diode check — D1** — probe with diode setting: Anode pad to Cathode pad should read ~0.45V (forward). Reverse should read OL.
- [ ] **Diode check — D2–D9** — same check, each one individually

---

### Gate 3 — Post-assembly power-up sequence

Solder components in this order. Test at each stage before continuing.

#### Stage 1 — Power chain only (no ESP32, no sensors)

Solder: J_PWR, D1, J_SW1, SW1 cable, U2 (buck module), U3, C1, C2, C3, R13–R15, LED1–LED3.  
Do NOT solder: U1 socket, sensor connectors, relay connectors, anything else.

1. Set bench PSU to 12V current-limited at 200mA
2. Connect to J_PWR with SW1 open
3. Verify no current draw
4. Close SW1
5. **Measure TP4** — must read 12.0V ±0.5V
6. **Measure TP3** — must read 5.0V ±0.25V (adjust buck trimmer if needed)
7. **Measure TP2** — must read 3.3V ±0.1V
8. **Verify LED1** — red LED lit
9. **Verify LED2** — yellow LED lit
10. **Verify LED3** — green LED lit
11. If any LED not lit — stop. Check LED orientation before continuing.
12. Measure current draw — should be <50mA with no load

#### Stage 2 — Relay zone circuits

Solder: SW2, R1–R4, R9–R12, R16–R19, LED4–LED7, J_ZONE_A–D.

1. Power up (SW1 on)
2. **Verify LED4–LED7 all OFF** (DIP switches all OFF, pull-downs holding low)
3. Set SW2 position A to ON
4. **Probe TP9 (RLY-A-SW)** — should read ~0V (no ESP32 driving it, pull-down holds low)
5. **Probe J_ZONE_A pin7 (RLY_5V)** — should read 5V
6. Set SW2 back to OFF

#### Stage 3 — Sensor VCC rails

Solder: D2–D9, C4–C13, J_ZONE_A–D, J_DHT, J_I2C_1–3.

1. Power up
2. **Probe TP7 (MST-A-VCC)** — should read ~3.0V (3.3V minus 1N5819 forward drop ~0.3V)
3. Repeat TP11, TP15, TP19 for zones B/C/D
4. **Probe TP25, TP26, TP27** — I2C VCC rails, each ~3.0V
5. **Probe TP28 (DHT-VCC)** — ~3.0V
6. **Probe J_ZONE_A pin2 (GND)** — should read 0V
7. If any VCC reads 0V — check diode orientation

#### Stage 4 — TVS and signal lines

Solder: D10–D13, R5–R8.

1. Power up
2. **Probe TP8 (MST-A-SIG)** with no sensor connected — should float or read noise, NOT be clamped to 0.7V
3. If SIG reads ~0.7V constantly — D10–D13 orientation is wrong (forward biased). Stop.
4. **Probe TP23 (SDA)** — should read 3.3V (pulled up)
5. **Probe TP24 (SCL)** — should read 3.3V (pulled up)
6. **Probe TP29 (DHT-DATA)** — should read 3.3V (pulled up, no sensor connected)

#### Stage 5 — SD card module

Solder: SD_MOD socket. Insert SD module.

1. Power up
2. Probe SD_MOD VCC — should read 3.3V
3. Probe SD_MOD GND — should read 0V
4. Probe SD_MOD CS — should read 3.3V (pulled high by R8 — card deselected)
5. Probe SD_MOD shell — should read 0V (GND)

#### Stage 6 — ESP32

Solder: U1 socket (2×19 female headers). Insert ESP32-DevKitC.

1. **Before inserting ESP32** — power up and re-verify TP2=3.3V, TP3=5V, TP4=12V
2. Power down
3. Insert ESP32-DevKitC into socket
4. Power up — current draw will increase
5. **Verify ESP32 boots** — check USB serial output for boot message
6. Verify LED1–LED3 still lit (power rails stable under load)
7. Flash firmware
8. Verify MQTT connection established

#### Stage 7 — Full functional test

With firmware running and MQTT connected:

1. **Moisture sensors** — plug in one sensor per zone:
   - Dashboard should show moisture reading 0–100% for each zone
   - If reading stuck at ~20% (0.7V/3.3V): TVS diode D10–D13 may be backwards
   - If reading 0%: check sensor VCC diode D2–D5 orientation
2. **DHT22** — plug in sensor:
   - Dashboard should show temperature and humidity
   - If no reading: check D6 orientation, check GPIO27 pull-up R5
3. **I2C sensors** — plug in BH1750 and MLX90614:
   - Dashboard should show lux and leaf temp values
4. **Relay zones** — for each zone:
   - Set DIP switch position to ON
   - Send water command from dashboard
   - Relay should click and zone LED should light
   - Zone LED not lighting does NOT mean relay is broken — check LED orientation separately
5. **SD card** — verify firmware logs sensor readings to card
6. **OTA** — verify firmware update from dashboard works

---

## Known risks and checks to double-verify before sign-off

| Risk | Check |
|---|---|
| AMS1117 U3 pinout wrong again | Verify: SOT-223 pin 1 (left notch end) = GND. Pin 3 (right) = INPUT. Tab = OUTPUT. Cross-check datasheet before placing in KiCad. Some clone parts have reversed pin 1/3 — measure with multimeter on the actual component before soldering. |
| Sensor diodes backwards again | Verify: for all D2–D9, current must flow FROM +3V3 rail TO sensor connector. Anode=3V3 side, Cathode=connector side. Test with diode meter before soldering. |
| TVS diodes backwards again | Verify: P6KE3.3A Cathode (banded end) toward signal, Anode toward GND. In normal operation diode is REVERSE biased. If signal reads 0.7V with sensor connected — it is forward biased and backwards. |
| LED polarity wrong again | Verify: all LEDs have Anode (longer lead) toward resistor/supply. Cathode (shorter lead, flat on base) toward GND. Check with LED tester before soldering. |
| ESP32 wrong GPIO | Verify: open DevKitC pinout diagram from Espressif datasheet during schematic entry. Check each GPIO individually against table above before routing PCB. |
| GND floating | Verify: GND net in KiCad net inspector must include ALL of: J_PWR-2, U2-IN−, U2-OUT−, U3-pin1, all electrolytic cap −, all pull-down R other ends, all LED cathodes, all TVS anodes, SD_MOD GND, SD_MOD shell, all sensor connector pin2s, all relay connector pin2s, all ESP32 GND pins. |
| SD card shield floating | Verify: SD_MOD shell pin explicitly connected to GND net in schematic. |
| SW2 DIP pad numbering | Standard DIP-8: pad 1 (top-left) is ACROSS from pad 8 (top-right), not pad 5 (bottom-right). Pad 5 is the output for position 4, not position 1. The NETLIST was wrong on first pass and corrected 2026-06-21. Re-verify in KiCad that pad 8 → RLY_A_IN, pad 7 → RLY_B_IN, pad 6 → RLY_C_IN, pad 5 → RLY_D_IN. |
| Relay module control signal marginal | R1–R4 are 1kΩ. At 3.3V with a typical relay module's 1kΩ series resistor, drive current ≈ 1mA — marginal for most optocouplers. Use active-LOW relay modules only (see Relay Module Requirements section). If using active-HIGH modules, reduce R1–R4 to 330Ω. |

---

## Relay module requirements

The NodeBoard carries no relay coils. Each zone's relay module mounts remotely near the valve and connects via Cat5e cable (RJ45 pin4=control, pin7=5V, pins2/5/6/8=GND).

**Required specification:**

| Property | Requirement | Reason |
|---|---|---|
| Trigger logic | Active-LOW (low level trigger) | ESP32 3.3V output sinks to GND; module's 5V drives the optocoupler LED internally — no dependency on ESP32 source current |
| Coil voltage | 5V | Powered from RLY_5V (pin 7) on board's +5V bus |
| Isolation | Optocoupler isolated | Protects ESP32 from solenoid coil transients over the cable |
| Flyback diode | Built-in on module | D14–D17 on NodeBoard are DNP — relay modules have onboard flyback |
| Contact rating | ≥5A at operating voltage | Typical 12V solenoid draws 200–500mA; 5A contacts give adequate margin |

**Firmware note:** Active-LOW logic is inverted. GPIO HIGH = relay OFF, GPIO LOW = relay ON. Confirm firmware uses the correct polarity.

**Typical compatible modules:** SRD-05VDC-SL-C based relay boards sold as "low level trigger" or "active low" — the most common inexpensive type. Avoid bare NPN transistor modules without optocoupler isolation.

---

## Power delivery to remote relay modules — voltage drop analysis

Relay modules are powered over Cat5e cable (AWG24 ≈ 8.4Ω/100m per conductor).

| Cable length | Round-trip resistance | Drop at 100mA coil | Relay module voltage |
|---|---|---|---|
| 5m | 0.84Ω | 84mV | 4.92V |
| 10m | 1.68Ω | 168mV | 4.83V |
| 20m | 3.36Ω | 336mV | 4.66V |

All values are well within the 4.5–5.5V tolerance of standard 5V relay modules. Power delivery is not a concern at realistic cable lengths.

**Adjusting LM2596 output:** The LM2596 module has a trim pot. Raising it to 5.5V increases headroom for long cable runs. This does NOT affect the 3.3V rail — the AMS1117-3.3 is a fixed-output LDO; its output is always 3.3V regardless of input voltage (as long as input ≥ 4.6V). So +5V bus → 5.5V is safe and does not propagate to +3V3.

---

## PCB status as of 2026-06-21

- Routed with FreeRouting v2.2.4 — 213 connections, 5 vias, 6.14 seconds
- DRC: 0 unconnected pads, 7 silkscreen overlap warnings (cosmetic only)
- SW2 pad net assignments corrected manually in KiCad editor before FreeRouting run
- Wiring diagram generated: `NodeBoard_v2/node_board_v2_diagram.html`
- Outstanding before fab: silkscreen cleanup, AMS1117 clone pinout verification, relay module selection confirmed

---

## Layout requirements

Rules learned from v0.1 board errors — must be checked in KiCad before sending to fab.

| Requirement | Detail |
|---|---|
| J_PI clearance from U2 | Pi UART header and LM2596 buck module were too close on v0.1. Minimum 10mm clearance between J_PI and U2 socket edges. |
| J_PWR and J_SW1 pitch | Must use 5.08mm pitch screw terminals — NOT 2.54mm. Verify footprint pitch before routing. |
| U2 riser height | LM2596 module sits 15mm above board on riser headers. No components taller than 10mm directly underneath the module footprint. |
| RJ45 jack spacing | 8 RJ45 jacks on one board — group by function (4× zone, 3× I2C, 1× DHT). Allow enough edge clearance for cable plug/unplug without adjacent cables fouling. Minimum 5mm between jack bodies. |
| ESP32 socket orientation | USB port must face board edge for access without removing module. Mark with "USB→" arrow on silkscreen. |
| Test point placement | All 33 test points must be accessible with standard multimeter probe when all modules are inserted. Do not place under U1, U2, or SD_MOD footprints. |

---

## Satellite boards

Three small PCBs that mount at the field end of each Cat5e cable. They carry no power regulation — all power comes from the main node board over the cable. The satellite connects via a standard Cat5e patch cable: RJ45 plug on the cable, RJ45 jack on the satellite.

Each satellite is all through-hole, ~2-layer, cheaply ordered in multiples. They are passive from a power perspective — solder components, plug in cable, plug in sensors.

---

### Zone Satellite Board (×4)

One per zone. Mounts near the moisture probe and relay module at the plant. Receives power and relay control from main board; breaks out moisture sensor and relay connections to screw terminals.

**Board size:** 50 × 30mm  
**Power source:** Main board via Cat5e — 3.3V on pin 3 (MST_VCC), 5V on pin 7 (RLY_5V), GND on pins 2/5/6/8

| Ref | Component | Value | Package | Notes |
|---|---|---|---|---|
| J1 | RJ45 jack | 8P8C | Through-hole vertical | Same footprint as main board zone jacks — verify match |
| J_MST | Moisture probe terminal | Screw terminal 3-pin 3.5mm | Through-hole | Pin 1=VCC, Pin 2=SIG, Pin 3=GND |
| J_RLY | Relay module terminal | Screw terminal 3-pin 3.5mm | Through-hole | Pin 1=GND, Pin 2=IN, Pin 3=5V |
| C1 | MST_VCC decoupling | 100nF ceramic | Disc through-hole | Across MST_VCC (pin 3) and GND (pin 2) |
| C2 | RLY_5V decoupling | 100nF ceramic | Disc through-hole | Across RLY_5V (pin 7) and GND (pin 8) |
| TP1 | MST_VCC test point | 2mm THT pad | — | Expected ~3.0V |
| TP2 | MST_SIG test point | 2mm THT pad | — | Expected 0.5–3.0V with sensor |
| TP3 | RLY_IN test point | 2mm THT pad | — | 0V idle, follows GPIO when DIP on |

**Netlist:**

```
J1 pin 1 (MST_SIG)  → J_MST pin 2, TP2
J1 pin 2 (GND)      → GND bus, C1−, C2−, J_MST pin 3, J_RLY pin 1
J1 pin 3 (MST_VCC)  → C1+, J_MST pin 1, TP1
J1 pin 4 (RLY_IN)   → J_RLY pin 2, TP3
J1 pin 5 (GND)      → GND bus
J1 pin 6 (GND)      → GND bus
J1 pin 7 (RLY_5V)   → C2+, J_RLY pin 3
J1 pin 8 (GND)      → GND bus
J1 shield (S)       → GND bus
```

**Silkscreen requirements:**
- J1: "FROM NODE BOARD", pin 1 marker
- J_MST: "MOISTURE", pin labels VCC/SIG/GND
- J_RLY: "RELAY MODULE", pin labels GND/IN/5V
- C1, C2: "+" marked on positive hole
- TP1/TP2/TP3: ref and signal name

**No TVS diodes on satellite.** TVS clamping is handled at the main board (receiver end) — this is the correct location for ADC protection.

---

### I2C Satellite Board (×3)

One per I2C connector. Mounts near the sensor cluster (BH1750 + MLX90614 typically share one satellite on the same I2C bus). Power from main board. Breaks out SDA/SCL/VCC/GND to two 4-pin headers so two I2C devices can co-exist.

**Board size:** 50 × 25mm  
**Power source:** Main board via Cat5e — 3.3V on pin 3 (VCC), GND on pins 2/5/6

| Ref | Component | Value | Package | Notes |
|---|---|---|---|---|
| J1 | RJ45 jack | 8P8C | Through-hole vertical | Same footprint as main board I2C jacks |
| J_DEV_A | I2C device header A | 4-pin header 2.54mm | Through-hole | Pin 1=VCC, Pin 2=GND, Pin 3=SDA, Pin 4=SCL |
| J_DEV_B | I2C device header B | 4-pin header 2.54mm | Through-hole | Same pinout — parallel on bus |
| C1 | VCC decoupling | 100nF ceramic | Disc through-hole | Across VCC (pin 3) and GND (pin 2) |
| TP1 | VCC test point | 2mm THT pad | — | Expected ~3.0V |
| TP2 | SDA test point | 2mm THT pad | — | 3.3V idle, pulses during comms |
| TP3 | SCL test point | 2mm THT pad | — | 3.3V idle, pulses during comms |

**Netlist:**

```
J1 pin 1 (SDA)  → J_DEV_A pin 3, J_DEV_B pin 3, TP2
J1 pin 2 (GND)  → GND bus, C1−, J_DEV_A pin 2, J_DEV_B pin 2
J1 pin 3 (VCC)  → C1+, J_DEV_A pin 1, J_DEV_B pin 1, TP1
J1 pin 4 (SCL)  → J_DEV_A pin 4, J_DEV_B pin 4, TP3
J1 pin 5 (GND)  → GND bus
J1 pin 6 (GND)  → GND bus
J1 pins 7,8     → NC
J1 shield (S)   → GND bus
```

**Silkscreen requirements:**
- J1: "FROM NODE BOARD", pin 1 marker
- J_DEV_A, J_DEV_B: "I2C DEVICE", pin labels VCC/GND/SDA/SCL
- C1: "+" marked
- TP1/TP2/TP3: ref and signal name

**Note on I2C device addresses:** BH1750 default 0x23, MLX90614 default 0x5A — no address conflict. If adding a second BH1750, solder ADDR pin high on one to use 0x5C.

---

### DHT22 Satellite Board (×1)

One board. Mounts near the DHT22 sensor (typically inside or near the enclosure with good airflow). Receives 3.3V from main board; breaks out DHT22 header.

**Board size:** 40 × 20mm  
**Power source:** Main board via Cat5e — 3.3V on pin 3 (VCC), GND on pins 2/5/6

| Ref | Component | Value | Package | Notes |
|---|---|---|---|---|
| J1 | RJ45 jack | 8P8C | Through-hole vertical | Same footprint as main board DHT22 jack |
| J_DHT | DHT22 header | 3-pin header 2.54mm | Through-hole | Pin 1=VCC, Pin 2=DATA, Pin 3=GND |
| C1 | VCC decoupling | 100nF ceramic | Disc through-hole | Across VCC and GND |
| TP1 | VCC test point | 2mm THT pad | — | Expected ~3.0V |
| TP2 | DATA test point | 2mm THT pad | — | 3.3V idle, pulses every 2s |

**Netlist:**

```
J1 pin 1 (DATA) → J_DHT pin 2, TP2
J1 pin 2 (GND)  → GND bus, C1−, J_DHT pin 3
J1 pin 3 (VCC)  → C1+, J_DHT pin 1, TP1
J1 pins 4–8     → NC (pins 5,6 to GND bus)
J1 shield (S)   → GND bus
```

**Silkscreen requirements:**
- J1: "FROM NODE BOARD", pin 1 marker
- J_DHT: "DHT22", pin labels VCC/DATA/GND
- C1: "+" marked
- TP1/TP2: ref and signal name

**Note:** The 10kΩ DATA pull-up resistor (R5) is on the main node board — do not add another pull-up on the satellite.

---

### Satellite board ordering notes

- Order 5 of each type per site (spares are cheap at this size)
- Same fab as main board — 2-layer FR4 1.6mm, ENIG finish
- No SMD needed — all through-hole, can be hand-soldered in the field
- No BOM overlap with main board except 100nF caps and RJ45 jacks — order extra of those

---

## Sign-off checklist (before schematic is written)

- [x] Component list reviewed and approved
- [x] Power architecture reviewed and approved
- [x] GPIO table reviewed and approved
- [x] Zone circuit reviewed and approved
- [x] Silkscreen requirements reviewed and approved
- [x] Test protocol reviewed and approved
- [x] Known risks reviewed and approved

**Signed off 2026-06-20. Schematic generation approved.**
