# FMEA — Methodology and Findings

## What is FMEA?

Failure Mode and Effects Analysis (FMEA) is a structured method for identifying how a system can fail, what the consequences are, and how detectable each failure is. Each failure mode is scored to produce a Risk Priority Number (RPN) that allows failures to be ranked and addressed in priority order.

FMEA is used here for two purposes:
1. To validate architectural decisions (specifically: does adding a Nerves Pi at each site materially reduce risk, and where?)
2. To identify design gaps — failures that are currently high-risk and unmitigated

---

## Scoring

Each failure mode is scored on three dimensions, each from 1 to 10.

### Severity (S) — how bad is the outcome?

| Score | Meaning | Example in this system |
|---|---|---|
| 1–2 | Negligible — no real impact | AO3401 short-circuit (normal operating state maintained) |
| 3–4 | Minor — slight degradation, easily recovered | ESP32 watchdog reset (30-second data gap) |
| 5 | Moderate — function degraded but system continues | Shared sensor hard failure (zone drops to degraded mode, watering continues) |
| 6 | Significant — reduced capability, some risk | Sensor calibration drift (watering decisions distorted) |
| 7 | Serious — plants at risk, intervention required | Zone offline (no monitoring, no watering) |
| 8 | High — plant loss or hardware damage likely | Mains power failure; freeze event; high-voltage PSU failure |
| 9 | Critical — severe damage or complete water loss to plants | Solenoid valve stuck open (flooding); complete water supply loss |
| 10 | Catastrophic — irreversible or site-wide damage | Solenoid mechanical stuck-open bypassing NC fail-safe; lightning strike |

### Occurrence (O) — how often does this failure happen?

| Score | Meaning | Example in this system |
|---|---|---|
| 1 | Extremely unlikely (<1 in 10,000 operating hours) | Lightning strike; DC-DC over-voltage |
| 2 | Rare (once in years of operation) | ESP32 hardware death; relay contact welding |
| 3 | Occasional (once per 6–12 months at a site) | 4G router hardware failure; power supply failure |
| 4–5 | Moderate (several times per year) | 4G outages; ESP32 reboots; moisture sensor hard failure |
| 6 | Common (monthly or more) | Capacitive sensor calibration drift; MLX90614 FOV issues |
| 7 | Frequent (weekly or persistent condition) | DHT22 drift at older sensors |
| 8 | Near-certain (confirmed persistent site condition) | Wide supply voltage variation (205–275VAC confirmed); hard water scale buildup |
| 9–10 | Almost certain to occur | Rarely used at this scale |

### Detection (D) — how easily is this failure caught?

Detection scores the difficulty of detecting the failure **with the current controls in place**. A low score means easy/fast detection; a high score means silent or undetectable.

| Score | Meaning | Example in this system |
|---|---|---|
| 1 | Immediately obvious — operator sees it instantly | Dashboard unavailable (you can't load the page) |
| 2 | Detected within minutes by existing automated checks | Shared sensor hard failure (sensor_ok flag fires immediately) |
| 3 | Detected within an hour by existing checks | ESP32 watchdog reset (data gap visible in history) |
| 4 | Detected within a few hours — delayed but reliable | Dripper fault (no moisture rise — detected after one watering cycle) |
| 5 | Detected eventually but with meaningful delay | Zone offline alert fires after 30 minutes of silence |
| 6 | Detectable but requires operator attention or pattern recognition | Relay stuck closed (dripper_fault fires but cause unclear) |
| 7 | Difficult to detect — only noticed after consequence | 4G loss (zone goes offline — cause vs. ESP32 failure indistinguishable remotely) |
| 8 | Very difficult — intermittent or indirect | Connector corrosion; mains voltage variation (no monitoring) |
| 9 | Near-impossible with current controls — plausible-looking bad data | Capacitive sensor drift (reads within valid range; no cross-reference) |
| 10 | Completely undetectable — no current mechanism | Solenoid stuck-open mechanical failure; water quality contamination |

---

## Risk Priority Number (RPN)

**RPN = Severity × Occurrence × Detection**

Range: 1 (best) to 1,000 (worst).

### Important caveat on RPN

RPN is a prioritisation tool, not an absolute risk measure. A high Severity score always warrants attention regardless of RPN — for example:

- S=10, O=1, D=2 → RPN=20 (low) but the failure destroys equipment and is worth preventing
- S=3, O=4, D=3 → RPN=36 (similar) but this is a minor nuisance

Always read the Severity column. Any S≥8 failure deserves engineering attention regardless of how the O and D scores affect the RPN.

### How we use RPN in this project

1. **RPN ≥ 300** — Address immediately. Either design it out or implement detection/mitigation before deployment.
2. **RPN 150–299** — Address in next design iteration. Prioritise by Severity.
3. **RPN 100–149** — Plan a mitigation. Monitor these during initial deployment.
4. **RPN < 100** — Accept with awareness, or address opportunistically.

---

## FMEA files

| File | Scope |
|---|---|
| `system_fmea.csv` | System-level functional blocks (MQTT, central server, 4G comms, alerting, etc.) |
| `component_fmea.csv` | Individual hardware components (ESP32, sensors, relays, solenoids, PSU, etc.) plus site infrastructure (power supply variation, water supply, hard water, environmental) |

Both files use the same column structure:

```
Component, Failure_Mode, Effect, S, Cause, O, Current_Controls, D, RPN,
Recommended_Action, Nerves_Pi_Impact, Residual_RPN_with_Nerves
```

The `Nerves_Pi_Impact` and `Residual_RPN_with_Nerves` columns quantify the effect of adding a Nerves device at each site (see `ARCHITECTURE.md`).

---

## Key findings summary

### Highest-risk items (RPN ≥ 300)

| RPN | Item | Action |
|---|---|---|
| **512** | Wide supply voltage variation (205–275VAC confirmed at site) | **Blocking for deployment** — industrial 85–305VAC PSU + Type 2 SPD mandatory |
| **324** | Moisture sensor calibration drift | Software bounds check implemented; per-zone calibration + dual sensors planned |
| **320** | Moisture sensor stuck reading | Stuck-reading detection implemented in software (6h unchanged threshold) |
| **400*** | No system heartbeat | Daily heartbeat email implemented |

*The 400 RPN entry is from the system FMEA (S=8, O=5, D=10 — completely undetectable system death). Now resolved.

### Critical architectural findings

**Nerves Pi reduces the two largest system-level risks dramatically:**

| Failure | Current RPN | With Nerves Pi |
|---|---|---|
| Data lost during 4G outage | 280 | 28 |
| Alerts lost during 4G outage | 280 | 56 |
| Central server failure | 192 | 72 |

This quantitatively validates the Nerves topology decision.

**Site-specific risks that must be addressed before deployment at the primary site:**

| Risk | RPN | Nature |
|---|---|---|
| Wide supply voltage (205–275VAC) | 512 | Hardware design — PSU selection |
| Hard water scale buildup | 280 | Physical maintenance plan + hardware selection |
| Mains power loss | 168 | UPS/battery backup |

**Software fixes implemented based on FMEA findings:**

| Fix | FMEA item addressed | RPN before | RPN after |
|---|---|---|---|
| Daily heartbeat email | Silent system death | 400 | ~40 |
| Sensor plausibility bounds checking | Sensor drift undetected | 270–324 | ~54–64 |
| Stuck moisture detection (6h threshold) | Sensor stuck-wet silent | 320 | ~64 |
| Freeze protection (≤2°C alert + valve stop) | Frost damage to pipework | 48 | 32 |

### Water supply failures — key gaps

Three water supply failure modes have high severity but low current detectability:

| Failure | S | D | RPN | Gap |
|---|---|---|---|---|
| Complete water supply loss | 9 | 7 | 126 | dripper_fault catches it after one cycle — acceptable delay |
| Low water pressure | 7 | 6 | 126 | Partially caught by dripper_fault |
| Water quality / chemical contamination | 7 | 10 | 140 | Completely undetectable — needs EC/pH sensor |
| Fertigation over-concentration | 8 | 9 | 144 | Completely undetectable — needs EC sensor |

The water quality failures cannot be addressed in software. They require physical EC/pH sensors on the supply line — identified as a future hardware expansion.

---

## How to maintain this FMEA

The FMEA is a living document. Update it when:

- New hardware is added (new component rows)
- Software mitigations are implemented (update Current_Controls, recalculate D and RPN)
- Nerves Pi is deployed (update Residual_RPN_with_Nerves columns to reflect actual, not estimated)
- A failure occurs in the field (update Occurrence scores based on actual field data)
- New sites are added with different conditions (site-specific rows may be needed)

The RPN scores are estimates based on engineering judgement at the time of writing. Field experience will improve their accuracy.
