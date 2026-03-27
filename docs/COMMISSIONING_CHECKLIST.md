# NurseryHub — Testing & Commissioning Checklist

**Site:** ___________________________
**Date:** ___________________________
**Commissioned by:** ___________________________
**NurseryHub version:** ___________________________

Work through each section in order. Tick each item only when confirmed — not when assumed.
Items marked **⚠️ SAFETY** must not be skipped regardless of time pressure. These relate to DC wiring only — mains AC is out of scope (see scope note below).

> **Scope note:** This checklist covers low-voltage DC electronics (12V and below). Mains AC wiring is out of scope and must be handled separately by a licensed electrician before this checklist begins. Assume the 12V DC supply is already present and energised at the enclosure input terminal when you start Section 2.

---

## Section 1 — Pre-Build Site Survey

Complete before ordering hardware or starting any physical work.

- [ ] Confirm 12V DC supply is present and stable at the enclosure input terminal (delivered by others)
  - Measured DC supply: _______ V (acceptable: 11.5–12.5V)
- [ ] Test water hardness at irrigation supply point (TDS meter or lab test) — record result
  - TDS: _______ ppm   [ ] Hard (>200ppm) — inline sediment filter + descaler required
- [ ] Measure static and dynamic water pressure at supply — record result
  - Static: _______ kPa   Dynamic: _______ kPa   Pressure regulator required: [ ] Yes [ ] No
- [ ] Confirm 4G carrier coverage at site and data plan selected
  - Carrier: ___________________________  Plan: ___________________________
- [ ] Count zones and ESP32s required — record:
  - Total zones: _______   ESP32s required: _______   Pi Zeros required: _______
- [ ] Identify enclosure mounting locations (post, wall, DIN rail)
- [ ] Confirm cable run lengths from enclosure to each sensor location — check against limits in HARDWARE_BUILD.md
- [ ] Identify WiFi AP location (site router or Pi AP) — confirm coverage to all ESP32 locations

---

## Section 2 — Electrical / Physical Build

Complete one enclosure at a time. Repeat per ESP32 node.

**Node being commissioned:** ___________________________ (e.g. site_01 ESP32 #1, zones A–D)

### 2.1 Enclosure

- [ ] Enclosure IP rating confirmed ≥ IP65 (IP67 recommended)
- [ ] Cable glands sized correctly per cable OD (PG7/PG9/PG11 — see HARDWARE_BUILD.md)
- [ ] One cable gland per cable entry — no shared glands
- [ ] Membrane breather vent installed (IP67-rated Gore-Tex style)
- [ ] All cable glands torqued finger-tight + 1/4 turn — confirmed sealed
- [ ] Internal layout: relay module away from ESP32 (heat separation)
- [ ] All external connections terminated on DIN terminal blocks — no soldered joints inside enclosure

### 2.2 DC Power Rail — Verify Before Connecting Anything

**Do this before any sensor, ESP32, or relay is connected to the rails.** Connecting incorrectly polarised or out-of-spec voltage to sensors will destroy them instantly and silently.

- [ ] 12V DC input polarity confirmed with multimeter — positive terminal is positive: _______ V
- [ ] LM2596 buck converter output **measured with no load** before connecting ESP32: _______ V
  - If not 5.0V ±0.1V: adjust trimmer pot until correct. Do not connect ESP32 until this reads correctly.
- [ ] LM2596 output polarity confirmed — positive output rail is positive
- [ ] **⚠️ SAFETY** Do not reverse polarity on ESP32 VIN — the onboard regulator will be destroyed immediately. Double-check before connecting.
- [ ] 3.3V sensor rail confirmed **after** ESP32 connected and booted: _______ V (acceptable: 3.2–3.4V)
  - The AO3401 MOSFETs on the sensor VCC line provide reverse-polarity protection — but only if wired correctly. Verify polarity before trusting this protection.
- [ ] ESP32 VIN rail confirmed at 5V with all sensors attached (measure under load): _______ V

### 2.3 Reverse Polarity Protection — AO3401 MOSFET Verification

The sensor VCC line is protected by AO3401 P-channel MOSFETs — one per zone. These are the circuit's primary protection against reverse polarity destroying sensors. They only work if oriented correctly.

**How it works:**

The AO3401 is a P-channel MOSFET wired as a high-side switch. In the correct orientation:
- Source connects to the positive supply (3.3V from ESP32)
- Drain connects to sensor VCC output
- Gate connects to GND (this keeps it switched on under normal operation)

When wired correctly, current flows Source → Drain to the sensor. If polarity is accidentally reversed (supply GND and VCC swapped), the Gate-Source voltage goes positive, the MOSFET turns off, and no current reaches the sensor — protecting it.

**If the MOSFET is installed backwards** (Source and Drain swapped), the body diode conducts in reverse and the protection does not work. The sensor is unprotected.

**Orientation check — before powering:**
- [ ] On each AO3401: identify the Source pin (typically pin 3 on SOT-23, marked side) — confirm it faces the supply rail (3.3V), not the sensor
- [ ] Gate pin (pin 1) connected to GND
- [ ] Drain pin (pin 2) connected to sensor VCC output wire
- [ ] If using a module or breakout with AO3401 already fitted: confirm silkscreen orientation matches the above — check the datasheet for your specific package marking

**Functional test — perform after wiring, before inserting sensors:**

This test confirms the MOSFET blocks reverse voltage before sensors are at risk.

1. With sensors disconnected from the VCC output:
   - [ ] Apply correct polarity 3.3V to the supply rail
   - [ ] Measure voltage at sensor VCC output pad — should read ~3.3V (MOSFET conducting): _______ V
2. Remove 3.3V supply. Reverse the supply connections (apply GND where 3.3V was, 3.3V where GND was):
   - [ ] Measure voltage at sensor VCC output pad — should read 0V or near-zero (MOSFET blocking): _______ V
   - If this reads 3.3V: MOSFET is installed backwards. Do not proceed — correct orientation before connecting sensors.
3. Restore correct polarity supply — confirm sensor VCC output returns to ~3.3V: _______ V
- [ ] All AO3401s pass the above test before any sensor is connected

> **Note:** The AO3401 body diode has a forward voltage of ~0.7V. In a reversed-polarity scenario the output may read up to ~0.7V due to body diode conduction — this is normal and insufficient to damage sensors. If you read anything above ~1V reversed, investigate before proceeding.

### 2.4 Sensor Protection — Before You Wire Anything

Sensors are the most fragile and most expensive-to-replace components. These checks prevent the most common damage modes.

**Handling:**
- [ ] Anti-static precautions observed when handling bare PCBs — touch a grounded metal surface before picking up any sensor board, or use an ESD wrist strap
- [ ] No sensor boards placed on conductive surfaces (metal bench, foil, anti-static bag exterior)

**Voltage — verify before connecting each sensor:**
- [ ] All sensors in this system run on 3.3V. The 5V ESP32 VIN rail must NEVER be connected to sensor VCC pins.
  - DHT22: max 5.5V (tolerates 5V, but 3.3V is used here)
  - BH1750: max 3.6V — will be destroyed by 5V
  - MLX90614: max 3.6V — will be destroyed by 5V
  - Capacitive moisture sensor: typically 3.3V rated — confirm your specific module before wiring
  - ADS1115: max 5.5V (tolerant, but wire to 3.3V)
- [ ] Confirm sensor VCC wires connect to 3.3V rail (ESP32 3V3 pin), not 5V VIN

**I2C bus — before connecting BH1750 or MLX90614:**
- [ ] I2C SDA and SCL are not swapped — SDA to GPIO21, SCL to GPIO22 on this firmware
- [ ] Pull-up resistors present on SDA and SCL (4.7kΩ to 3.3V for runs <2m)
- [ ] No two I2C devices sharing the same address — BH1750 default 0x23, MLX90614 default 0x5A, ADS1115 default 0x48. Confirm no conflicts before powering.
- [ ] I2C bus scan performed after first boot (open Serial Monitor, check firmware reports sensors found — a missing sensor here usually means wiring fault or address conflict, not a dead sensor)

**Capacitive moisture sensors:**
- [ ] Do not run moisture sensors powered but out of soil for extended periods — the sensor oscillator runs continuously and generates heat when unloaded. Wire last, after enclosure is installed and sensors are in position.
- [ ] Sensor board coating intact — no cracks or exposed copper on the sensing tines (corrosion accelerates rapidly at hard water sites if coating is damaged)

**Relay module — before connecting solenoids:**
- [ ] Relay coil flyback diodes present on relay module board (most modules include these — visually confirm before assuming)
- [ ] If using bare relay without flyback diode: add 1N4007 across each coil, cathode to positive
- [ ] Relay common (COM) terminals wired correctly — check which contact is NO (normally open) vs NC (normally closed). Solenoid valves must wire to NO so they default closed on power loss.
- [ ] Relay module IN pins driven from ESP32 GPIO through the module's optoisolator — do not connect relay IN directly to 3.3V logic without checking module specs (most accept 3.3V; some require 5V signal level)

**MLX90614 — most sensitive to incorrect wiring:**
- [ ] VCC: 3.3V only — absolutely not 5V
- [ ] Do not hot-plug the MLX90614 while the I2C bus is active — power off the ESP32 first when connecting or disconnecting

### 2.5 Wiring

- [ ] 24AWG 4-core shielded cable used for all moisture sensor runs and outdoor runs >1m
- [ ] Shield drain wire connected to GND at enclosure end only — floating at sensor end
- [ ] I2C pull-up resistors confirmed (4.7kΩ for runs <2m; 1kΩ for runs 2–4m)
- [ ] I2C extender (P82B96) installed if MLX90614 or BH1750 cable run exceeds 2m
- [ ] All wiring labels match terminal block labels — verified by continuity test
- [ ] No exposed conductors inside enclosure — all insulation intact

### 2.6 Sensors — Physical Installation

- [ ] **Soil moisture sensors** — inserted at 45° angle, tip at root depth (10–15cm pots / 20–30cm beds)
- [ ] Moisture sensors not directly under a dripper
- [ ] Moisture sensors not at edge of pot or bed
- [ ] **DHT22** — mounted outside enclosure in multi-plate radiation shield, at canopy height, away from direct sun and rain
- [ ] **BH1750** — mounted flat, facing upward, at canopy height, not behind glass or polycarbonate
- [ ] **MLX90614** — mounted on cable extension from enclosure (not inside box), 5–15cm above canopy top, pointing directly downward, clear line of sight to leaves not soil or sky, away from relay module
- [ ] MLX90614 mounting arm allows repositioning as canopy height changes
- [ ] All sensor cables secured to post/structure with UV-stable zip ties at regular intervals

### 2.7 Valves and Solenoids

- [ ] Solenoid valves rated for site water pressure confirmed
- [ ] Valve orientation confirmed (most solenoids are directional — arrow on body points downstream)
- [ ] Inline sediment filter installed before solenoid block (especially required at hard water sites)
- [ ] Pressure regulator installed if site static pressure exceeds drip system specification
- [ ] Manual shutoff valve installed upstream of solenoid block for maintenance isolation
- [ ] Drip lines and emitters installed and flow tested with manual fill — no obvious blockages before commissioning
- [ ] Self-flushing pressure-compensating emitters confirmed (required at hard water sites)

---

## Section 3 — ESP32 Firmware

### 3.1 Configuration

Open `esp32_firmware/ESP32_Plant_Monitor_v5/ESP32_Plant_Monitor_v5.ino` and confirm:

- [ ] `SITE_ID` set to correct unique site identifier: ___________________________
- [ ] `NUM_ZONES` set correctly for this ESP32: _______
- [ ] `ZONE_IDS[]` set to correct zone identifiers for this node: ___________________________
- [ ] `MOISTURE_PINS[]` match physical wiring
- [ ] `RELAY_PINS[]` match physical wiring
- [ ] `TEST_MODE` set to `false`
- [ ] WiFi SSID and password set correctly for site network
- [ ] `MQTT_HOST` set to correct IP (Pi IP if Nerves Pi deployed; otherwise central server IP)
- [ ] `MQTT_USERNAME` and `MQTT_PASSWORD` set and match the broker config
- [ ] `OTA_VERSION_URL` and `OTA_FIRMWARE_URL` point to correct server (Pi if deployed; central otherwise)
- [ ] `FIRMWARE_VERSION` recorded: ___________________________
- [ ] `DUAL_MOISTURE` set correctly (`true` if ADS1115 fitted, `false` if single moisture sensor per zone)

> **Note:** `NODE_ID` and sensor ID defines (`SENSOR_ID_DHT`, `SENSOR_ID_MST[]`, etc.) are **not configured in firmware**. The device is identified by its hardware chip ID (derived from MAC address) and asset tags are assigned through the Topology page after first boot.

### 3.2 Flash

- [ ] Arduino IDE board: "ESP32 Dev Module" (or matching variant)
- [ ] Upload speed: 115200
- [ ] Flash successful — no compile errors, no upload errors
- [ ] Serial monitor opened at 115200 baud — confirm boot messages without error
- [ ] Serial monitor shows WiFi connected: ___________________________
- [ ] Serial monitor shows MQTT connected to broker
- [ ] Serial monitor shows first sensor readings published within 35s of boot

### 3.3 Confirm all zones flashed

| Zone / ESP32 | SITE_ID | ZONE_IDs | Flashed | MQTT connected | First reading received |
|---|---|---|---|---|---|
| ESP32 #1 | | | [ ] | [ ] | [ ] |
| ESP32 #2 | | | [ ] | [ ] | [ ] |
| ESP32 #3 | | | [ ] | [ ] | [ ] |
| ESP32 #4 | | | [ ] | [ ] | [ ] |

### 3.4 Device Registration — Assign Asset Tags

After each ESP32 is powered and connected, register it through the Topology page. Asset tags are assigned here once and stored permanently in the server — no firmware changes needed.

For each ESP32 node:

- [ ] Open Topology page (`/topology`) — confirm node appears as orange **Unregistered · [chip_id]**
- [ ] Click **Register →** — confirm form opens with next available tag numbers pre-filled
- [ ] Verify or adjust the suggested numbers match the labels physically applied to the hardware:
  - Node tag (enclosure label): ___________________________
  - DHT22 tag: ___________________________  BH1750 tag: ___________________________  MLX tag: ___________________________
  - Moisture probes: zone_a _________  zone_b _________  zone_c _________  zone_d _________
- [ ] Click **Save** — confirm node immediately shows with assigned tags (orange banner gone)
- [ ] Confirm sensor asset tags appear on zone cards and in the shared sensors row

| ESP32 | Chip ID | Node tag assigned | Sensors registered |
|---|---|---|---|
| ESP32 #1 | | | [ ] |
| ESP32 #2 | | | [ ] |
| ESP32 #3 | | | [ ] |
| ESP32 #4 | | | [ ] |

---

## Section 4 — Network

### 4.1 Local WiFi

- [ ] 4G router powered and connected to site SIM
- [ ] Site WiFi SSID and password set — record SSID: ___________________________
- [ ] All ESP32s shown as connected clients on router admin page
- [ ] Nerves Pi (if deployed) shown as connected client on router admin page
- [ ] Pi has a static IP assigned (via DHCP reservation on router) — record: ___________________________
- [ ] Central server IP or WAN address confirmed and reachable from site: ___________________________

### 4.2 WireGuard VPN (required before going live)

- [ ] WireGuard configured on 4G router
- [ ] WireGuard configured on central server
- [ ] VPN tunnel confirmed up — ping from site to central server via VPN tunnel
- [ ] MQTT port accessible over VPN tunnel (not exposed to public internet)

### 4.3 MQTT Broker

- [ ] Mosquitto running on broker host (Pi or central server)
- [ ] MQTT password authentication enabled — default open access disabled
- [ ] MQTT password matches ESP32 firmware and Elixir app config
- [ ] MQTT Explorer (or equivalent) connected to broker — confirm `nursery/#` messages arriving every ~30s per active ESP32

---

## Section 5 — Sensor Validation

For each zone, verify that the readings are physically plausible. This is the most important section — a sensor wired wrong or placed incorrectly will silently produce bad data.

**Tools needed:** phone with a torch, spray bottle of water, hot water bottle or hands for leaf temp test.

### 5.1 Soil Moisture

- [ ] With sensor in dry soil: reading is LOW (below 30%) — confirm: _______%
- [ ] Spray water directly onto soil around sensor — reading rises within 60s
- [ ] Reading rises to >60% within 2 minutes of thorough wetting — confirm: _______%
- [ ] After 10 minutes, reading begins to fall (drainage working) — confirm: _______%
- [ ] If dual moisture enabled: primary and secondary readings agree within 10% — primary: _______% secondary: _______%
- [ ] `moisture_diverged` alert NOT firing under normal conditions

### 5.2 DHT22 — Air Temperature and Humidity

- [ ] Temperature reading plausible for current ambient conditions: _______ °C
- [ ] Humidity reading plausible for current ambient conditions: _______ %
- [ ] Breathe on the sensor briefly — humidity rises within a few seconds (confirms sensor is live, not stuck)
- [ ] VPD reading shown on dashboard is plausible (should be 0.4–1.5 kPa in typical greenhouse conditions): _______ kPa

### 5.3 BH1750 — Light Level

- [ ] In daytime outdoor conditions: lux reading is substantial (>1000 lux expected outdoors): _______ lux
- [ ] Cover sensor with hand — reading drops to near zero within 5 seconds
- [ ] Remove hand — reading recovers within 5 seconds
- [ ] Confirm no glass or polycarbonate in sensor's field of view

### 5.4 MLX90614 — Leaf Temperature (IR)

- [ ] Reading is plausible for current leaf/canopy temperature — typically within 2–5°C of air temp in stable conditions: _______ °C
- [ ] Hold a warm hand (or warm water bottle) directly under the sensor — reading rises noticeably
- [ ] Remove hand — reading returns toward ambient within 30s
- [ ] Confirm sensor has clear line of sight to foliage, not walls, soil, or sky

---

## Section 6 — Valve and Solenoid Testing

**⚠️ SAFETY** Confirm manual shutoff valve is accessible and operational before testing. Keep a person at the shutoff during first valve tests.

- [ ] Manual shutoff valve tested — closes water supply completely when turned
- [ ] All zones confirmed in "stop" / valve closed state before beginning
- [ ] Water supply turned on to system — no leaks at connections, fittings, or glands under static pressure
- [ ] **Zone A (or first zone):** issue Water command from dashboard — valve opens, water flows from drip emitters
- [ ] Drip emitters producing even flow across all emitters in zone — no blocked emitters
- [ ] No water leaking from solenoid valve body or connections
- [ ] Stop command issued from dashboard — valve closes, flow stops within 5 seconds
- [ ] Valve stuck-open safety timeout: hold valve open beyond 120 seconds — confirm dashboard shows `valve_stuck_open` alert and stop command auto-sent
- [ ] Repeat above for each zone:

| Zone | Opens on command | Drip flow even | Closes on stop | Timeout alert fires |
|---|---|---|---|---|
| Zone A | [ ] | [ ] | [ ] | [ ] |
| Zone B | [ ] | [ ] | [ ] | [ ] |
| Zone C | [ ] | [ ] | [ ] | [ ] |
| Zone D | [ ] | [ ] | [ ] | [ ] |
| Zone E | [ ] | [ ] | [ ] | [ ] |
| Zone F | [ ] | [ ] | [ ] | [ ] |
| Zone G | [ ] | [ ] | [ ] | [ ] |
| Zone H | [ ] | [ ] | [ ] | [ ] |

---

## Section 7 — Central Server and Dashboard

### 7.1 Server startup

- [ ] Mosquitto running (auto-started on boot or confirmed running)
- [ ] NurseryHub Elixir app started without errors
- [ ] Dashboard accessible at configured URL: ___________________________
- [ ] Dashboard login works with configured credentials

### 7.2 Dashboard validation

- [ ] Topology page (`/topology`) loads and shows the central server node
- [ ] All commissioned sites appear as blocks in the Topology view
- [ ] All ESP32 nodes show with assigned asset tags (e.g. `ESP-001`) — no orange **Unregistered** nodes remaining
- [ ] Shared sensor row visible on each node: DHT-NNN, LUX-NNN, IR-NNN tags shown with live readings and green status dots
- [ ] Each zone card shows moisture probe tag (MST-NNN) beside the moisture bar
- [ ] All zone cards show status `online` (green) — no red or yellow cards
- [ ] Sensor fault indicators: cover a sensor — confirm fault dot appears in topology within ~35s; uncover — confirms it clears
- [ ] Topology updates live — watch a zone card, confirm readings change within ~35s
- [ ] Click a zone card — confirms it navigates to the zone detail page
- [ ] All zones show status `online` in the table view (`/`)
- [ ] Sensor readings updating live in table view — watch for 2–3 refresh cycles
- [ ] VPD values shown and plausible for current conditions
- [ ] Zone mode shown as `normal` for all zones (not `local`, `no_vpd`, `no_moisture`)
- [ ] Filter by site works correctly
- [ ] Filter by status works correctly
- [ ] History button on a zone row opens zone history page with charts populating
- [ ] CSV export from dashboard downloads a valid file

### 7.3 Security (required before going live)

- [ ] `dashboard_auth` username and password changed from defaults in `config/config.exs`
- [ ] `settings_password` changed from default
- [ ] `secret_key_base` regenerated: `mix phx.gen.secret`
- [ ] MQTT username and password set in Mosquitto password file
- [ ] MQTT credentials match in `config/config.exs` and all ESP32 firmware
- [ ] All settings saved and app restarted — confirm login still works

---

## Section 8 — Alerting

### 8.1 Email alerts

- [ ] SMTP settings configured in Settings page (host, port, username, password, from address)
- [ ] Test email sent from Settings page — received in inbox (check spam)
- [ ] Reply-to / from address looks legitimate and won't be caught by spam filters

### 8.2 SMS alerts

- [ ] Twilio account SID, auth token, and from number configured in Settings page
- [ ] Test SMS sent from Settings page — received on mobile

### 8.3 Alert routing

- [ ] Alert routing configured per alert type in Settings → Alert Routing
- [ ] Confirm `critical_dry` routes to Email + SMS
- [ ] Confirm `valve_stuck_open` routes to Email + SMS
- [ ] Confirm `zone_offline` routes to Email

### 8.4 Live alert tests

- [ ] **Zone offline test:** stop one ESP32 (or unplug it) — `zone_offline` alert fires within 35 minutes, email received
  - Wait time confirmed: _______ minutes
- [ ] Zone comes back online — alert resolves and shows resolved timestamp in alert log
- [ ] **Critical dry test (dry sensor):** remove a moisture sensor from soil and let it read dry air — `critical_dry` alert fires, email + SMS received
- [ ] Sensor reinserted — alert clears

### 8.5 Heartbeat

- [ ] Heartbeat email configured for correct UTC hour in `config/config.exs`
- [ ] Wait for the configured heartbeat time, or temporarily change the hour to the next UTC hour and restart app — confirm heartbeat email received with zone summary

---

## Section 9 — OTA Firmware Updates

- [ ] Compiled firmware binary placed in `priv/static/firmware/esp32_plant_monitor.bin`
- [ ] Firmware version number updated in Settings → OTA Firmware Version
- [ ] Save & Deploy triggered
- [ ] At least one ESP32 rebooted manually — confirm it checks version, downloads new firmware, reboots, and reconnects within 2 minutes
- [ ] After OTA reboot: zone reappears as `online` on dashboard
- [ ] Old firmware version number changed back for the remaining fleet, or increment version and deploy again

---

## Section 10 — Nerves Pi Commissioning

*Complete this section only when the Nerves Pi hardware is physically available.*

### 10.1 Build and flash

- [ ] Nerves bootstrap archive installed on build machine: `mix archive.install hex nerves_bootstrap`
- [ ] Nerves deps added to `mix.exs`: `nerves`, `nerves_hub_link`, `nerves_system_rpi0_2`
- [ ] `config/target.exs` created (imports `nerves.exs`)
- [ ] Environment variables set for this site:
  - `MIX_TARGET=rpi0_2`
  - `SITE_ID=` ___________________________
  - `CENTRAL_URL=` ___________________________
  - `SYNC_API_KEY=` ___________________________
- [ ] `mix deps.get` completed without errors
- [ ] `mix firmware` completed without errors
- [ ] SD card inserted into reader on build machine
- [ ] `mix burn` completed — SD card written and safely ejected

### 10.2 First boot

- [ ] SD card inserted into Pi Zero 2W
- [ ] Pi powered on from site 12V → 5V rail
- [ ] Pi boots within 20 seconds
- [ ] Pi appears on network — confirm IP: ___________________________
- [ ] Local dashboard accessible at `http://[pi-ip]:4000`
- [ ] All site zones visible in local dashboard
- [ ] Local Mosquitto confirmed running (MQTT Explorer connects to Pi IP port 1883)

### 10.3 Reconfigure ESP32s to use Pi

- [ ] `MQTT_HOST` in all site ESP32 firmware updated to Pi's local IP
- [ ] `OTA_VERSION_URL` and `OTA_FIRMWARE_URL` updated to point to Pi
- [ ] All site ESP32s reflashed with updated firmware
- [ ] All zones reappear in Pi's local dashboard
- [ ] All zones also appear on central server dashboard (via DataSync)

### 10.4 Local alerting

- [ ] Email relay configured on Pi (SMTP credentials set via Pi's local Settings page)
- [ ] Test email sent from Pi's Settings page — received in inbox
- [ ] Disconnect Pi from WAN (disable 4G on router or block Pi's route) — confirm local dashboard still accessible and updating
- [ ] Reconnect WAN

---

## Section 11 — DataSync and WAN Failover

- [ ] Central server `/api/sync/health` endpoint responding: `curl http://[central]/api/sync/health` returns 200
- [ ] DataSync GenServer confirmed active on Pi — check Pi logs via `ssh nerves.local`
- [ ] Confirm readings from Pi are appearing in central server dashboard in near real-time (within 2 minutes)

### 11.1 WAN outage simulation

- [ ] Disable 4G connection (pull SIM or disable mobile data on router)
- [ ] Confirm Pi's local dashboard continues to update — zone readings still live
- [ ] Confirm local alerting still fires during outage (trigger a test alert)
- [ ] Leave WAN disconnected for at least 5 minutes — confirm no data loss on Pi (readings continue to local SQLite)
- [ ] Record number of readings buffered while WAN down: _______

### 11.2 WAN restore

- [ ] Re-enable 4G connection
- [ ] Confirm DataSync detects WAN restore within 60–90 seconds
- [ ] Confirm all buffered readings pushed to central server — verify in central dashboard history charts (no gap)
- [ ] `pending_count` in DataSync logs returns to 0

---

## Section 12 — NervesHub OTA (Phase 4)

*Complete once all sites are operational and you want remote Pi firmware management.*

- [ ] NervesHub account created at nerves-hub.org
- [ ] Pi provisioned with NervesHub certificate on first flash (run `mix nerves_hub.device create` during build)
- [ ] Pi appears in NervesHub device list — confirm device identity
- [ ] Test OTA update: increment Pi firmware version, `mix firmware && mix nerves_hub.firmware publish`
- [ ] Deploy update to this Pi from NervesHub dashboard
- [ ] Pi receives and applies update — reboots and reconnects without physical intervention
- [ ] Rollback test: build a firmware that deliberately fails to start — confirm Pi auto-rolls back to previous version

---

## Section 13 — Final Sign-Off

### 13.1 System state check

- [ ] All zones `online` with `normal` mode in dashboard
- [ ] No active alerts in alert log
- [ ] All sensor readings plausible and stable
- [ ] No error messages in application logs
- [ ] Automatic watering cycle confirmed — at least one zone has completed a watering cycle triggered by low moisture and closed cleanly

### 13.2 Maintenance schedule documented and handed over

- [ ] Moisture sensor cleaning and recalibration: every 3 months (especially hard water sites)
- [ ] Solenoid valve replacement cycle: 12 months (hard water sites)
- [ ] Drip line citric acid flush schedule: recorded in site maintenance log
- [ ] Sediment filter replacement interval noted
- [ ] NurseryHub software update process documented for site operator

### 13.3 Sign-off

**Commissioned by:** ___________________________
**Date:** ___________________________
**NurseryHub version:** ___________________________
**ESP32 firmware version:** ___________________________
**Nerves Pi firmware version (if deployed):** ___________________________

Any known deviations from this checklist (with justification):

___________________________
___________________________

---

## Appendix A — Troubleshooting Quick Reference

| Symptom | First check |
|---|---|
| Zone shows `offline` | Check ESP32 serial log — is it publishing? Check MQTT broker — is it receiving? Check `MQTT_HOST` in firmware points to correct broker IP |
| Zone shows `local` mode | ESP32 has lost MQTT connection. Check WiFi signal at ESP32 location. Check MQTT broker is running. |
| Moisture reading stuck or implausible | Sensor not in soil, sensor dry, wiring fault, or calcium coating (hard water). Clean sensor and re-seat. |
| VPD reading wrong | DHT22 placement issue (inside enclosure, direct sun, near heat source). Check placement against HARDWARE_BUILD.md. |
| Valve not opening on command | Check relay module power (5V to VCC). Check relay LED fires on command. Check solenoid wiring at terminal blocks. Check water supply is on and pressure adequate. |
| Valve not closing | Check stop command received in MQTT Explorer. Relay latched? Check relay module GND common. Solenoid debris — flush valve. |
| Dashboard not updating | Is the Elixir app running? Is Mosquitto running? Check `nursery/#` in MQTT Explorer for live messages. |
| DataSync not pushing | Check `/api/sync/health` on central server. Check `SYNC_API_KEY` matches on both Pi and central. Check Pi has WAN route (ping 8.8.8.8). |
| ESP32 OTA not triggering | Check `OTA_VERSION_URL` returns a version string. Check version in URL is higher than `FIRMWARE_VERSION` in running firmware. |

---

## Appendix B — Contact and Access

| Resource | Location |
|---|---|
| System overview | `docs/NurseryHub_Overview_and_Setup.md` |
| Hardware build guide | `HARDWARE_BUILD.md` |
| Architecture | `docs/ARCHITECTURE.md` |
| Security hardening | `SECURITY_SETUP.md` |
| Nerves Pi design | `docs/NERVES_PI_DESIGN.md` |
| FMEA | `docs/fmea/system_fmea.csv` |
| Dashboard | `http://[server-ip]:4000` |
| Local Pi dashboard | `http://[pi-ip]:4000` |
| Pi SSH | `ssh nerves.local` |
| NervesHub | https://nerves-hub.org |

