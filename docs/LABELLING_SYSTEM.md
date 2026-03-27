# NurseryHub — Labelling and Identification System

Every physical component in the system must be labelled so that any person — including someone unfamiliar with the installation — can immediately identify what they are looking at, which zone it serves, and where it appears in the software dashboard.

---

## Naming Convention

The system uses a three-level hierarchy that matches the software exactly:

```
SITE  ›  NODE  ›  ZONE
```

| Level | What it is | Example |
|---|---|---|
| **SITE** | The nursery location | `NORTHCOTE` |
| **NODE** | One ESP32 enclosure (controls up to 4 zones) | `NODE-1` |
| **ZONE** | One watering zone (one valve + one set of sensors) | `ZONE-A` |

Full component identifier format:
```
NORTHCOTE / NODE-1 / ZONE-A
```

This matches what you see in the dashboard. If a zone shows a fault on screen, you can read the label on the physical hardware and immediately know what to look for.

### Site ID

Choose a short, memorable, all-caps word for each site. No spaces — use hyphens if needed.

| Example | Notes |
|---|---|
| `NORTHCOTE` | Good — clear, short |
| `HEIDELBERG` | Good |
| `SITE-01` | Acceptable if no meaningful name |
| `The Main Nursery Site` | Bad — too long, spaces, mixed case |

The site ID must match the `SITE_ID` value in the ESP32 firmware and Nerves Pi config exactly. Once set, do not change it — all historical data in the database is indexed by this name.

### Node numbering

Number nodes sequentially per site starting at 1: `NODE-1`, `NODE-2`, etc.

### Zone letters

Zones within a node are always labelled A, B, C, D — matching the `ZONE_IDS` array in the firmware. Zone A is always the first zone on that node.

---

## Label Types and Placement

### 1 — Enclosure Label

**What it identifies:** The ESP32 node inside this enclosure.

**What to put on it:**
```
┌─────────────────────────┐
│  NORTHCOTE              │
│  NODE-1                 │
│  Zones A · B · C · D   │
│                         │
│  MQTT: 192.168.1.XX     │  ← local IP of MQTT broker (Pi or router)
│  Firmware: v4.0         │  ← fill in at commissioning
└─────────────────────────┘
```

**Placement:** On the outside face of the enclosure lid, at eye level.

**Size:** Minimum 60 × 40mm — large enough to read without crouching.

---

### 2 — Valve Label

**What it identifies:** Which zone this solenoid valve controls.

**What to put on it:**
```
NORTHCOTE / NODE-1
ZONE-A
```

**Placement:** Directly on the valve body or on the pipe immediately upstream of the valve. Must be readable without moving any hardware.

---

### 3 — Cable Labels — Both Ends

Every cable must be labelled at **both ends**. A cable with one labelled end is only half labelled.

**Format:**
```
[SITE] / [NODE] / [ZONE] — [SIGNAL]
```

| Signal abbreviation | Meaning |
|---|---|
| `PWR-12V` | 12V DC power |
| `PWR-5V` | 5V DC power |
| `PWR-3V3` | 3.3V sensor supply |
| `GND` | Ground / negative |
| `MOIST-A` | Moisture sensor, Zone A |
| `MOIST-B` | Moisture sensor, Zone B |
| `MOIST-C` | Moisture sensor, Zone C |
| `MOIST-D` | Moisture sensor, Zone D |
| `DHT22` | Air temperature + humidity sensor |
| `BH1750` | Light sensor |
| `MLX` | Leaf IR temperature sensor |
| `VALVE-A` | Solenoid valve, Zone A |
| `VALVE-B` | Solenoid valve, Zone B |
| `VALVE-C` | Solenoid valve, Zone C |
| `VALVE-D` | Solenoid valve, Zone D |
| `I2C-SDA` | I2C data line |
| `I2C-SCL` | I2C clock line |

**Example cable label:**
```
NORTHCOTE / NODE-1 / ZONE-A — MOIST-A
```

**Placement:** Wrap-around labels at each end, within 50mm of the termination point (terminal block or connector).

---

### 4 — Sensor Labels

**What it identifies:** Which sensor this is and which zone it serves.

**What to put on it:**
```
NORTHCOTE / NODE-1
MOISTURE — ZONE-A
```

| Sensor | Label text |
|---|---|
| Capacitive moisture sensor | `MOISTURE — ZONE-A` (etc.) |
| DHT22 | `AIR TEMP + HUMIDITY` |
| BH1750 | `LIGHT SENSOR` |
| MLX90614 | `LEAF TEMP (IR)` |
| ADS1115 | `ADC — DUAL MOISTURE` |

**Placement:** On the sensor body or mounting bracket. For sensors that move (MLX90614 on an adjustable arm), label the cable near the sensor end.

---

### 5 — Terminal Block Labels

Label each terminal on the DIN rail terminal blocks inside the enclosure. Use the same signal abbreviations as the cable labels.

```
PWR-12V(+)  |  GND  |  PWR-5V(+)  |  GND  |  PWR-3V3(+)  |  GND
MOIST-A(+)  |  MOIST-A(SIG)  |  MOIST-A(GND)  |  ...
VALVE-A  |  VALVE-B  |  VALVE-C  |  VALVE-D
```

Adhesive terminal strip markers (Brady or equivalent, pre-printed or write-on) are the neatest option. A printed label strip taped above the terminal row is acceptable.

---

### 6 — Pi Enclosure Label (if Nerves Pi deployed)

```
┌─────────────────────────┐
│  NORTHCOTE              │
│  SITE HUB (Pi)          │
│                         │
│  Dashboard:             │
│  http://192.168.1.XX:4000│
│                         │
│  SSH: ssh nerves.local  │
│  Firmware: vX.X         │
└─────────────────────────┘
```

---

## Label Materials — Outdoor Installations

Labels in a nursery environment are exposed to moisture, UV, fertiliser spray, and temperature cycling. Standard paper or standard adhesive labels will fail within weeks.

| Requirement | Recommended product |
|---|---|
| Cable and sensor labels | Brady M21-750-499 self-laminating vinyl wrap labels, or equivalent |
| Enclosure face labels | UV-stable polyester or polycarbonate overlay labels (laser-printable) — laminate after printing |
| Write-on site labels | Brady BMP21 label printer with M21 vinyl cartridge — suitable for outdoor use without additional lamination |
| Terminal block markers | Brady PermaSleeve wire markers, or clip-in terminal markers (Phoenix Contact or Weidmüller) |

**Minimum spec for any label used outdoors:**
- UV-stable substrate (not plain white paper)
- Waterproof adhesive or mechanical fixing
- Legible at 0.5m in typical site lighting conditions
- Expected service life ≥ 3 years without replacement

Avoid: standard adhesive cable tie labels (UV-degrade and fall off), standard Brother P-Touch tape without lamination (fades within months outdoors), handwritten marker pen on tape (illegible after one season).

---

## Label Register

Maintain a label register for each site — a simple table confirming every label has been applied and what it says. File this register with the commissioning checklist for the site.

| Item | Location | Label text | Applied |
|---|---|---|---|
| Enclosure — Node 1 | Post A, north face | `NORTHCOTE / NODE-1 / Zones A·B·C·D` | [ ] |
| Valve — Zone A | Valve body, Zone A pipe | `NORTHCOTE / NODE-1 / ZONE-A` | [ ] |
| Moisture sensor — Zone A | Sensor body | `MOISTURE — ZONE-A` | [ ] |
| Moisture sensor cable — enclosure end | Terminal block, within 50mm | `NORTHCOTE / NODE-1 / ZONE-A — MOIST-A` | [ ] |
| Moisture sensor cable — sensor end | Cable near sensor | `NORTHCOTE / NODE-1 / ZONE-A — MOIST-A` | [ ] |
| DHT22 — Node 1 | Radiation shield bracket | `AIR TEMP + HUMIDITY — NODE-1` | [ ] |
| BH1750 — Node 1 | Sensor mounting arm | `LIGHT SENSOR — NODE-1` | [ ] |
| MLX90614 — Node 1 | Cable near sensor | `LEAF TEMP (IR) — NODE-1` | [ ] |
| Pi enclosure | Pi mounting location | `NORTHCOTE / SITE HUB (Pi)` | [ ] |

Add one row per cable, sensor, valve, and enclosure at each site.

---

## Quick Identification Guide

If you are standing in front of a piece of hardware and trying to work out what it is:

1. **Find the enclosure label** — it tells you the site, node number, and which zones are inside
2. **Find the zone letter** on the valve or sensor label — this matches the zone letter on the dashboard
3. **Cross-reference with the dashboard** — search by site and zone to see the live readings and status for that exact piece of hardware
4. **If a label is missing or unreadable** — check the label register in the site commissioning file, or trace the cable back to the terminal block inside the enclosure where it will be labelled at the termination point
