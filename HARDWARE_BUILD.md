# NurseryHub — Hardware Build Guide

Physical installation reference for ESP32 sensor nodes: enclosure, wiring, and sensor placement.

---

## Enclosure

### IP Rating

| Location | Minimum rating |
|---|---|
| Under cover (greenhouse, shade house) | IP65 |
| Exposed to direct rain or hosing | IP67 (recommended) |

IP67 is the better default — it costs little extra and handles being accidentally hosed down during irrigation work.

### Size

A four-zone node needs to fit:
- ESP32 dev board (~55 × 28mm)
- DC-DC buck converter (~45 × 20mm)
- 4-channel relay module (~75 × 55mm)
- Terminal blocks for all external connections
- Cable gland clearance on entry faces

**Minimum: 200 × 150 × 75mm.** 200 × 200 × 75mm is more comfortable to work in and recommended if budget allows.

ABS polycarbonate enclosures (Hammond 1554 series or equivalent) are fine. Check the IP rating is independently tested, not just claimed — especially on cheaper options.

### Cable Glands

Cable glands are what actually maintain the IP rating at the cable entries. Use PG-style glands sized to the cable OD:

| Gland size | Cable OD | Use for |
|---|---|---|
| PG7 | 3–6.5mm | Thin sensor cables |
| PG9 | 4–8mm | Sensor bundles |
| PG11 | 5–10mm | Power in, valve cables |

One gland per cable run — never share a gland between two cables. Typical entry count per enclosure:
- 1 × power in (PG11)
- 1 × sensor cable bundle (PG11)
- 4 × valve cables, one per zone (PG9 each) — or 1–2 runs of multicore if zones are close together

Mount glands on a removable backplate if possible — makes assembly and maintenance much easier than fighting glands on the fixed enclosure wall.

### Condensation

Sealed enclosures get condensation from temperature cycling. Add one **IP67-rated membrane breather vent** (Gore-Tex style, ~$2) to allow water vapour to escape without letting liquid water in. Without it, condensation will eventually settle on the ESP32.

### Internal Layout

Put heat-generating components (relay module) away from the ESP32. Terminal blocks for all external connections make field maintenance practical — never solder inside the box.

```
┌─────────────────────────────────────────┐
│  [power in gland]   [sensor gland]      │  ← top face
│                                         │
│  ┌──────────────┐  ┌────────────────┐   │
│  │  DC-DC buck  │  │  ESP32 dev     │   │
│  │  converter   │  │  board         │   │
│  └──────────────┘  └────────────────┘   │
│                                         │
│  ┌──────────────────────────────────┐   │
│  │  4-channel relay module          │   │
│  └──────────────────────────────────┘   │
│                                         │
│  [terminal blocks — all wiring]         │
│  [valve glands ×4]                      │  ← bottom face
└─────────────────────────────────────────┘
```

---

## Wiring

### Signal Types and Maximum Practical Cable Lengths

Different signals have different constraints. Voltage drop on power lines is negligible at these current levels — the limiting factors are digital timing and bus capacitance.

| Signal | Sensors | Wire | Max without extender |
|---|---|---|---|
| I2C (100kHz, 4.7kΩ pull-ups) | BH1750, MLX90614 | Any | ~1–2m |
| I2C (100kHz, 1kΩ pull-ups) | BH1750, MLX90614 | Any | ~4m |
| Analog | Moisture sensors | Shielded if >5m | 10m+ |
| Digital one-wire | DHT22 | Any | 10m (reliable) |
| 12V valve signal | Solenoids | Any | Not a concern |
| 3.3V power | All sensors | 24AWG | Not a concern |

**Voltage drop on power at worst case (12mA all sensors, 3m of 24AWG):**
```
V_drop = 0.012A × (0.084 Ω/m × 2 × 3m) = 6mV
```
6mV on a 3.3V rail is 0.2% — completely negligible.

### I2C Extenders

Only needed if the BH1750 or MLX90614 are mounted more than ~2m from the ESP32 on a long cable run (e.g. MLX on a remote arm well above the canopy).

- **P82B96** — bidirectional bus buffer. Amplifies drive current to overcome cable capacitance. One chip at the ESP32 end extends to ~20m. Transparent to firmware. ~$1–2 per chip.
- **LTC4311** — active termination. Assists rising edges on a marginally slow bus. Better for fixing a slightly borderline run than for true long-distance extension. ~$3–5.

If sensors are inside or directly on the enclosure (recommended), no extender is needed.

### Sensor Cable — 24AWG 4-Core Shielded

Use **24AWG 4-core shielded cable** for moisture sensor runs and any sensor cable run longer than 1m outdoors.

| Core | Connection |
|---|---|
| Core 1 | 3.3V power |
| Core 2 | GND |
| Core 3 | Signal |
| Core 4 | Spare (second sensor or future use) |
| Shield drain wire | GND at enclosure end only |

**Connect the shield drain wire to circuit GND (DC negative) at the enclosure end only — leave it floating at the sensor end.** This gives the shield a reference to divert induced noise without creating a ground loop. This is not mains earth — the system runs on 12V DC and no mains earth is involved.

Wire gauge guide for reference:

| Gauge | Cross-section | Resistance | Use |
|---|---|---|---|
| 22AWG | 0.33mm² | 53 mΩ/m | Overkill for signal, good for power |
| 24AWG | 0.20mm² | 84 mΩ/m | Recommended — signal and power |
| 26AWG | 0.14mm² | 135 mΩ/m | Minimum workable for fixed runs |
| 28AWG | 0.08mm² | 213 mΩ/m | Too fragile for outdoor use |

---

## Sensor Placement

### Soil Moisture Sensors

- Insert at **45°** angle, tip at root depth — typically 10–15cm for pots, 20–30cm for ground beds
- **Not directly under a dripper** — you'll read artificially high immediately after watering
- **Not at the edge of the pot or bed** — dries out faster than the root zone
- For large beds: consider two sensors per zone and average them (requires firmware change)

### DHT22 — Air Temperature + Humidity

- **Must be outside the enclosure** — electronics raise internal temperature 5–15°C above ambient
- **Must be shielded from direct sun and rain** — direct solar radiation causes readings 3–8°C too high
- Mount inside a **multi-plate radiation shield** (white ABS Stevenson screen type, widely available for ~$3) on a bracket attached to the post
- Mount at **crop canopy height**, not at standard 1.5m met-station height — you want the air temperature the plants are actually experiencing
- Keep away from heating/cooling vents, doors, or any non-representative airflow

### BH1750 — Light Level (Lux)

Mount **flat, facing upward** at canopy level.

The BH1750 has a cosine response — sensitivity drops as the angle between the sensor face and the light source increases:

```
measured_lux = actual_lux × cos(θ)
```

| Tilt from horizontal | Reading vs true lux |
|---|---|
| 0° (flat) | 100% — accurate |
| 15° | 96.6% — acceptable |
| 30° | 86.6% — 13% low |
| 45° | 70.7% — 30% low |

A 30° tilt reads 13% low consistently. For this system's current use (day/night context, anomaly detection) that's tolerable — but if you later add DLI (Daily Light Integral) calculations for grow decisions, the error compounds over the day. Mount it flat and eliminate the issue.

**Do not mount it behind glass or polycarbonate.** Both absorb portions of the light spectrum and introduce their own angular distortion. Mount the sensor exposed or in a small open-sided weatherproof housing.

A flat horizontal arm extending from the enclosure post, with the BH1750 board zip-tied or screwed flat, is sufficient. No enclosure needed for the sensor itself if it's rated for outdoor use.

### MLX90614 — Leaf Temperature (IR)

The most placement-critical sensor. It measures thermal radiation from whatever is in its field of view — it must have line of sight to leaves, not soil, walls, or sky.

- The BAA variant has a **90° field of view** (±45° from centre)
- At 10cm above the canopy, it reads a ~20cm diameter circle
- Mount **5–15cm above the canopy top**, pointing directly downward
- Must be on a **cable extension from the enclosure** — do not mount it inside the box
- Keep away from the relay module — relay coils generate infrared heat that pollutes the reading
- Mount on an **adjustable arm** so it can be repositioned as plants grow

### Sensor Arm for MLX90614

Options in order of practicality:

**Articulating camera arm** — security camera or outdoor speaker mount style. Already weatherproof, locking joints at multiple points, mounts to the post with a standard clamp. Most adjustable for repositioning as crop height changes. Recommended for permanent installations.

**PVC conduit arm** — 20mm conduit on a conduit clamp off the post. Run the sensor cable inside the conduit for full protection. Angle it over the canopy, sensor zip-tied to the end. Cheap and weatherproof.

**Stainless threaded rod** — 6–8mm rod with a swivel clamp at the post end. Good adjustability, durable outdoors.

**Bent aluminium flat bar** — quickest to fabricate, repositionable by bending. Adequate for a first deployment while you determine optimal placement in practice.

For all options: run the sensor cable along the arm back to the enclosure, secured with UV-stable zip ties at regular intervals.

---

## Post/Wall Mounting Layout

```
POST
  │
  ├── [enclosure — ~1m height]
  │      all wiring terminates here via cable glands
  │
  ├── [radiation shield — canopy height]
  │      DHT22 inside, shaded from direct sun
  │
  ├── [horizontal arm — canopy height]
  │      BH1750 flat, facing sky
  │
  └── [adjustable arm — above canopy]
         MLX90614 pointing down at leaves
         5–15cm above crop top, repositioned as plants grow
```

All sensor cables run down the post to the enclosure. Tidy with UV-stable zip ties and enter via correctly-sized cable glands.

---

## Hardware Shopping List

| Item | Spec | Notes |
|---|---|---|
| Enclosure | IP67 ABS, 200×150×75mm minimum | Hammond 1554 or equivalent |
| Cable glands | PG7, PG9, PG11 assorted | One per cable entry, not shared |
| Membrane breather vent | IP67-rated Gore-Tex style | One per enclosure |
| Multi-plate radiation shield | White ABS Stevenson screen | For DHT22 |
| DIN terminal blocks | Any brand | For all external wiring |
| 4-core shielded cable | 24AWG, outdoor-rated jacket | Moisture sensors and long sensor runs |
| Articulating arm | Camera/speaker mount style | For MLX90614 above canopy |
| UV-stable zip ties | 200mm, outdoor-rated | Cable management on post |
| P82B96 I2C extender | — | Only if MLX/BH1750 cable run exceeds 2m |
| PG-type cable gland backplate | Removable | Simplifies assembly and maintenance |
