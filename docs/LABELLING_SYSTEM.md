# NurseryHub — Labelling and Identification System

Labels identify **what the component is** — nothing else. No location, no node, no zone assignment in the number. Where a component lives and what it connects to is recorded in the software (Topology page). If you move a component, only the software needs updating. The label never changes.

The label is a permanent asset tag. The Topology page is the map.

---

## ID Format

All components get a short type prefix and a globally unique sequential number, assigned at the time the component is first installed anywhere in the system. Numbers are never reused.

| Component type | Prefix | Example |
|---|---|---|
| ESP32 node enclosure | `ESP` | `ESP-001` |
| Watering zone assembly (valve + moisture sensor) | `ZN` | `ZN-001` |
| Solenoid valve | `VLV` | `VLV-001` |
| Capacitive moisture sensor | `MST` | `MST-001` |
| DHT22 air temp + humidity sensor | `DHT` | `DHT-001` |
| BH1750 light sensor | `LUX` | `LUX-001` |
| MLX90614 leaf IR sensor | `IR` | `IR-001` |
| ADS1115 ADC (dual moisture) | `ADC` | `ADC-001` |
| Nerves Pi hub | `HUB` | `HUB-001` |
| Cable assembly | `CBL` | `CBL-001` |

Numbers run sequentially across all sites from 001. The tenth ESP32 in the whole system is `ESP-010`, regardless of which site it is at.

> **Optional location note:** A small secondary label or tag may be added to any component with a plain-English note of its current physical location — e.g. *"North greenhouse, post 3"*. This is informational only and separate from the ID. The ID label is never changed. The location note can be replaced when the component moves.

---

## Label Formats by Component

### ESP32 Enclosure

Large label on the outside face of the lid, readable without opening.

```
┌─────────────────────────┐
│  ESP-001                │
│                         │
│  Firmware: v4.0         │
└─────────────────────────┘
```

Optional location note (separate, smaller label):
```
North greenhouse — post 3
```

---

### Solenoid Valve

```
VLV-001
```

On the valve body or pipe immediately adjacent. Must be readable without moving hardware.

---

### Moisture Sensor

```
MST-001
```

On the sensor body or mounting bracket.

---

### Shared Sensors (DHT22, BH1750, MLX90614)

```
DHT-001
LUX-001
IR-001
```

On the sensor body or mounting bracket. For sensors on cable extensions (MLX90614), also label the cable near the sensor end.

---

### Cables — Both Ends

Every cable is labelled at **both ends** within 50mm of the termination point. The cable label shows its own ID plus a signal descriptor so you know what it carries without tracing it.

```
CBL-001 — MOIST
CBL-002 — VALVE
CBL-003 — DHT
CBL-004 — IR
CBL-005 — I2C
CBL-006 — PWR-12V
```

Signal descriptors:

| Signal | Descriptor |
|---|---|
| Moisture sensor signal | `MOIST` |
| Solenoid valve | `VALVE` |
| DHT22 | `DHT` |
| BH1750 | `LUX` |
| MLX90614 | `IR` |
| I2C bus | `I2C` |
| 12V power | `PWR-12V` |
| 5V rail | `PWR-5V` |
| 3.3V sensor supply | `PWR-3V3` |
| Ground | `GND` |

---

### Terminal Blocks

Label each terminal inside the enclosure by signal type only — no component IDs on terminal labels, just what signal is on that terminal.

```
PWR-12V(+) | GND | PWR-5V(+) | GND | PWR-3V3(+) | GND
MOIST-1 | MOIST-2 | MOIST-3 | MOIST-4
VALVE-1 | VALVE-2 | VALVE-3 | VALVE-4
I2C-SDA | I2C-SCL | DHT | LUX | IR
```

---

### Nerves Pi Enclosure

```
┌──────────────────────────────┐
│  HUB-001                     │
│                              │
│  Dashboard:                  │
│  http://[ip]:4000            │
│                              │
│  Firmware: vX.X              │
└──────────────────────────────┘
```

---

## How to positively identify hardware in the field

1. An alert or event appears on screen — open the **Topology page** (`/topology`)
2. Find the zone card showing the fault. The software shows which ESP32 node it belongs to and its current location.
3. Go to the field — find the enclosure, valve, or sensor with the ID shown in the software.
4. You are looking at the hardware behind the fault.

The Topology page is the equipment register — every component appears from first connection and persists until explicitly decommissioned. The software is always the source of truth for where a component is. The label is just the permanent identity of the thing itself.

---

## Label Materials — Outdoor Installations

| Component | Required spec | Recommended product |
|---|---|---|
| Enclosure face | UV-stable, waterproof, min 60×40mm | Laser-printed polyester overlay, laminated |
| Valve body | UV-stable, adhesive, min 25×15mm | Brady M21-750-499 self-laminating vinyl |
| Sensor body / bracket | UV-stable, adhesive or mechanical | Brady M21-750-499 or heat-shrink sleeve |
| Cables — both ends | Wrap-around, UV-stable | Self-laminating wrap labels or Brady PermaSleeve heat-shrink |
| Terminal blocks | Clip-in markers or label strip | Phoenix Contact or Weidmüller clip-in markers |
| Optional location note | Plain-English, replaceable | Write-on card sleeve or small label holder on bracket |

Minimum spec for any permanent ID label:
- UV-stable substrate
- Waterproof adhesive or mechanical fixing (heat-shrink, cable tie mount)
- Legible at 0.5m in normal site lighting
- Expected service life ≥ 3 years

Do not use: standard paper labels, standard P-Touch tape without lamination, or handwritten marker pen on tape.
