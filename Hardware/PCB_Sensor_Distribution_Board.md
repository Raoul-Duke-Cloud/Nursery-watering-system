# Sensor Distribution Board — Design Spec

One PCB per ESP32 node. Mounts between the ESP32 and all field cables.
Moves all passive components (pull-ups, protection diodes, decoupling caps)
off the breadboard and onto a dedicated board. All sensor cables plug in
via standardised connectors — cables are generic and reusable.

---

## Goals

- All passives (pull-ups, TVS diodes, decoupling caps) on-board — nothing on breadboard
- Every sensor plugs into a labelled connector — no bare wire terminations in the field
- Cables are generic and interchangeable within each sensor type
- Cables testable with EOL loopback plugs using the Cable_Tester sketch
- ESP32 mounts directly to board via pin headers (removable for reflashing)
- Single 12V input → on-board buck to 5V and 3.3V rails

---

## Connectors

All field-side connectors are **JST-XH 2.54mm** — polarised, locking, widely available.
ESP32 side uses standard 2.54mm pin headers.

| Connector | Pins | Cable carries | Notes |
|---|---|---|---|
| Moisture sensor × 4 | 3-pin JST-XH | VCC / GND / SIG | One per zone |
| Relay / solenoid × 4 | 3-pin JST-XH | VCC / GND / IN | Relay module, not coil directly |
| DHT22 | 4-pin JST-XH | VCC / GND / DATA / NC | |
| BH1750 / MLX90614 | 4-pin JST-XH | VCC / GND / SDA / SCL | Shared I2C bus — daisy-chain or star |
| ADS1115 (secondary moisture) | 4-pin JST-XH | VCC / GND / SDA / SCL | Same I2C bus |
| Power in | 2-pin screw terminal | 12V / GND | From site rail |
| ESP32 | 2 × 19-pin header | All GPIO | ESP32-DevKitC footprint |

---

## Passive components per channel

### Moisture sensor (× 4)
- 100nF decoupling cap on VCC pin
- No pull-up needed (ADC input, driven output from sensor)
- **Schottky diode (1N5819 or BAT54)** on VCC line — anode toward connector,
  cathode toward ESP32 3.3V rail. Blocks reverse polarity from mis-wired cable.
- TVS diode (SMBJ3.3A) on SIG line — clamps transients to 3.3V
- Diode protection is verified by the Cable_Tester sketch reverse-direction test

### DHT22
- 10kΩ pull-up on DATA line to 3.3V (required by protocol)
- 100nF decoupling cap on VCC
- **Schottky diode (1N5819)** on VCC line — same orientation as moisture sensors

### I2C bus (shared — BH1750, MLX90614, ADS1115)
- 4.7kΩ pull-up on SDA to 3.3V
- 4.7kΩ pull-up on SCL to 3.3V
- Pull-ups fit once on the bus, not per device
- 100nF decoupling cap on each device VCC pin
- **Schottky diode (1N5819)** on VCC line of each I2C connector

### Relay control lines (× 4)
- 1kΩ series resistor on IN line (limits GPIO current if relay module lacks it)
- Optional: flyback diode on coil side if driving coil directly (not needed for relay modules)

---

## Power

| Rail | Source | Used by |
|---|---|---|
| 12V | External input | Relay coils, solenoids |
| 5V | LM2596 or MP2307 buck | ESP32 VIN, relay module VCC |
| 3.3V | AMS1117-3.3 LDO from 5V | All sensors, pull-ups |

Decoupling: 100µF electrolytic + 100nF ceramic on each rail at the board.

---

## Cable pinout standard

All cables follow the same colour convention:

| Pin | Colour | Signal |
|---|---|---|
| 1 | Red | VCC (3.3V) |
| 2 | Black | GND |
| 3 | Yellow | SIG / DATA / SDA |
| 4 | White | SCL (I2C only) |

---

## EOL test plug wiring

One plug per cable type — used with the Cable_Tester sketch.

| Cable type | Loopback wiring |
|---|---|
| Moisture (3-pin) | Pin 1 (VCC) → Pin 3 (SIG) |
| DHT22 (4-pin) | Pin 1 (VCC) → Pin 3 (DATA) |
| Relay (3-pin) | Pin 1 (VCC) → Pin 3 (IN) |
| I2C (4-pin) | Pin 1 (VCC) → Pin 3 (SDA) and Pin 2 (GND) → Pin 4 (SCL) |

---

## Board layout notes

- ESP32 pin headers centred on board — DevKitC is 25.4mm wide
- Connectors grouped by type along board edges, labelled silkscreen
- Power input screw terminal at corner with polarity marking
- Test points on 3.3V, 5V, GND rails
- LED indicators: power good (3.3V), power good (5V)
- Board size target: 100 × 80mm (fits standard PCB fab minimum)
- Consider panel of 2 on a 100 × 100mm board to reduce per-unit cost

---

## Next steps

1. Schematic in KiCad (or EasyEDA for faster fab turnaround)
2. Route PCB — connectors on edges, passives close to ESP32 headers
3. Order prototype from JLCPCB or PCBWay (5× boards ~$5–10 + shipping)
4. Validate with Cable_Tester sketch before connecting any sensors
