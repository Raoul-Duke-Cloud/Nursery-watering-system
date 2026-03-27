# NurseryHub — Labelling and Identification System

Labels on physical hardware identify the hardware itself. The software (dashboard → Topology page) tells you which site it belongs to and what its current status is. A label is not a map — the software is the map.

The rule is simple: **if you can see it in the software, the label on the physical hardware must match it exactly.**

---

## Naming Convention

Every piece of hardware has a short, unique identifier that matches what appears in the dashboard.

| Hardware | Label format | Example | Matches in software |
|---|---|---|---|
| ESP32 enclosure | `NODE-{n}` | `NODE-1` | Groups of zones in the Topology view |
| Watering zone | `{node}-{zone}` | `N1-A` | Zone ID column in dashboard |
| Solenoid valve | `{node}-{zone}` | `N1-A` | Same as zone — one valve per zone |
| Sensor (moisture) | `{node}-{zone} MOIST` | `N1-A MOIST` | Zone ID + sensor type |
| Sensor (air temp/humidity) | `{node} DHT` | `N1 DHT` | Node-level shared sensor |
| Sensor (light) | `{node} LUX` | `N1 LUX` | Node-level shared sensor |
| Sensor (leaf temp IR) | `{node} IR` | `N1 IR` | Node-level shared sensor |
| Nerves Pi hub | `HUB-{n}` | `HUB-1` | Site hub in Topology view |
| Cable | `{node}-{zone} — {signal}` | `N1-A — MOIST` | N/A — internal wiring reference |

Node numbers are assigned sequentially across the whole deployment — `NODE-1`, `NODE-2`, etc. regardless of which site they are at. The software maps each node's zones to a site. The label just says what the hardware is.

---

## Label Formats by Component

### ESP32 Enclosure

Large label on the outside of the lid, readable without opening.

```
┌──────────────────────┐
│  NODE-1              │
│  Zones: A  B  C  D  │
│                      │
│  Firmware: v4.0      │
└──────────────────────┘
```

Fill in firmware version at commissioning and update when firmware is changed.

---

### Solenoid Valve

```
N1-A
```

On the valve body, or on the pipe immediately adjacent. Must be readable without moving hardware.

---

### Sensors

| Sensor | Label |
|---|---|
| Moisture sensor (Zone A on Node 1) | `N1-A MOIST` |
| Moisture sensor (Zone B on Node 1) | `N1-B MOIST` |
| Secondary moisture (if dual fitted) | `N1-A MOIST-2` |
| DHT22 air temp + humidity | `N1 DHT` |
| BH1750 light | `N1 LUX` |
| MLX90614 leaf IR | `N1 IR` |
| ADS1115 ADC (if fitted) | `N1 ADC` |

Label on the sensor body or mounting bracket. For sensors on cable extensions (MLX90614), label the cable near the sensor end.

---

### Cables — Both Ends

Every cable must be labelled at **both ends** within 50mm of the termination point.

| Signal | Cable label |
|---|---|
| Moisture sensor, Zone A | `N1-A — MOIST` |
| Moisture sensor, Zone B | `N1-B — MOIST` |
| Secondary moisture, Zone A | `N1-A — MOIST-2` |
| DHT22 | `N1 — DHT` |
| BH1750 | `N1 — LUX` |
| MLX90614 | `N1 — IR` |
| Solenoid valve, Zone A | `N1-A — VALVE` |
| Solenoid valve, Zone B | `N1-B — VALVE` |
| I2C bus | `N1 — I2C` |
| 12V power in | `N1 — PWR-12V` |
| 5V rail | `N1 — PWR-5V` |
| 3.3V sensor supply | `N1 — PWR-3V3` |
| GND | `N1 — GND` |

---

### Terminal Blocks

Label each terminal inside the enclosure. Use the same signal abbreviations as the cable labels. Use clip-in terminal markers or a printed label strip above the terminal row.

```
PWR-12V(+) | GND | PWR-5V(+) | GND | PWR-3V3(+) | GND
N1-A MOIST | N1-B MOIST | N1-C MOIST | N1-D MOIST
N1-A VALVE | N1-B VALVE | N1-C VALVE | N1-D VALVE
I2C-SDA | I2C-SCL | N1 DHT | N1 LUX | N1 IR
```

---

### Nerves Pi Enclosure

```
┌──────────────────────────────┐
│  HUB-1                       │
│                              │
│  Dashboard:                  │
│  http://[ip]:4000            │
│                              │
│  Firmware: vX.X              │
└──────────────────────────────┘
```

Fill in the Pi's local IP at commissioning.

---

## How to positively identify hardware in the field

1. An alert or event appears — open the **Topology page** (`/topology`)
2. Find the coloured zone card. It shows the site and zone ID.
3. Go to the field. Find the enclosure labelled `NODE-{n}` for that node.
4. Find the valve or sensor labelled `N{n}-{zone}` — that is the physical hardware behind the fault.

The Topology page is the map. The label is the positive ID. The Topology page is also the equipment register — zones appear there permanently from first connection and remain until explicitly decommissioned. No separate paper register is required or maintained.

---

## Label Materials — Outdoor Installations

| Location | Required spec | Recommended product |
|---|---|---|
| Enclosure face | UV-stable, waterproof, min 60×40mm | Laser-printed polyester overlay, laminated |
| Valve body | UV-stable, adhesive, min 25×15mm | Brady M21-750-499 self-laminating vinyl |
| Sensor body / bracket | UV-stable, adhesive or mechanical | Brady M21-750-499 or heat-shrink sleeve |
| Cables — both ends | Wrap-around, UV-stable | Self-laminating wrap labels or Brady PermaSleeve heat-shrink |
| Terminal blocks | Clip-in markers or label strip | Phoenix Contact or Weidmüller clip-in markers |

Minimum spec for any outdoor label:
- UV-stable substrate
- Waterproof adhesive or mechanical fixing (heat-shrink, cable tie mount)
- Legible at 0.5m in normal site lighting
- Expected service life ≥ 3 years

Do not use: standard paper labels, standard P-Touch tape without lamination, or handwritten marker pen on tape.

