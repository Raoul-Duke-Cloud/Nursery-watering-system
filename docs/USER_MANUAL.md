# NurseryHub — User Manual

This manual is for the people who operate the nursery day to day. You do not need to understand how the system was built to use it. If something is not working and this manual does not resolve it, contact your system administrator.

---

## What the system does

NurseryHub keeps an eye on your nursery so you don't have to watch it constantly. Sensors placed throughout your growing areas measure soil moisture, air temperature, humidity, light, and leaf temperature — all the things that tell you whether your plants are comfortable. When soil gets dry, the system turns on the water. When something looks wrong, it sends you an alert by email or SMS. You can check the status of every zone from any web browser, whether you're in the shed or off-site.

The goal is simple: your plants get the right amount of water at the right time, you get notified when something needs your attention, and everything keeps running even when technology misbehaves.

---

## A typical day

Every 30 seconds, the sensors in each zone take a reading and send it back to the system. You don't need to do anything — the data flows in continuously, building up a picture of what's happening across your nursery.

If you open the dashboard at any point, you'll see all your zones with their current readings. The system handles watering automatically in the background, so most days you won't need to touch it at all.

---

## How watering works

The system watches the soil moisture in each zone. When a zone gets dry enough, it opens the valve for a short burst — 15 seconds by default. After that, it waits and checks whether the moisture level actually went up. If it did, the soil absorbed the water as expected and the cycle continues normally.

If the moisture doesn't rise after watering, the system tries again. If repeated waterings produce no response, it sends you an alert — something may be blocking the dripper. A blocked emitter is easy to miss until a plant is already in trouble; this is one of the most practical things the system catches.

---

## During an internet outage

If the internet connection drops, the system keeps running on the local network. Sensors keep talking to the local hub at the site — they have no idea the internet is gone. The hub keeps recording everything and can still send email alerts. If you're on-site, you can check the dashboard as normal at the Pi's local address.

When the internet comes back, the hub automatically sends everything it recorded to the central server. There are no gaps in your data — it catches up quietly in the background.

---

## Opening the dashboard

Open a web browser and go to:

**Central dashboard (from anywhere with internet):**
```
http://[your-server-address]:4000
```

**On-site dashboard (on the nursery network only):**
```
http://[pi-ip-address]:4000
```

Your system administrator will give you the correct addresses. Bookmark them.

You will be asked to log in with a username and password. Your administrator will provide these.

---

## The Topology page — start here when something goes wrong

The Topology page (`/topology`, or click **Topology** in the header) is a live map of all equipment in the system:

- The central server at the top
- Each site as a block, colour-coded by its worst current status
- Every zone as a card within its site, showing moisture, temperature, status, and any active alerts

**This is how you locate a fault in the field:**

1. Open the Topology page — find the red, yellow, or orange card
2. Note the component IDs shown on the card
3. Go to the physical site — find the enclosure with the `ESP-XXX` ID shown in the software
4. Find the sensor or valve with the `VLV-XXX` / `MST-XXX` ID shown in the software
5. That is the hardware behind what you saw on screen

The Topology page is the authoritative record of all equipment known to the system. Once a zone connects for the first time it appears here and stays until explicitly removed.

---

## The main dashboard

The table view (`/`) shows all zones with live sensor readings.

| Column | What it shows |
|---|---|
| **Site** | Which nursery location this zone is at |
| **Zone** | The zone identifier |
| **Status** | Whether the zone is working normally right now |
| **Mode** | What information the zone is using to make watering decisions |
| **Moisture** | Current soil moisture % |
| **Air Temp** | Air temperature at canopy height |
| **Humidity** | Relative humidity % |
| **VPD** | Vapour pressure deficit — a measure of how hard the air is driving water out of the plants |
| **Light** | Light level in lux |
| **Leaf Temp** | Leaf surface temperature (infrared) |
| **Last Seen** | When the zone last sent a reading |
| **Actions** | Water, Stop, History buttons |

The dashboard updates automatically every 30 seconds.

---

## Zone status — what the colours mean

| Status | Meaning | What to do |
|---|---|---|
| **online** | Zone is working normally | Nothing |
| **watering** | Valve is currently open | Normal — closes automatically |
| **alert** | Zone has a problem | Read the alert — see Alerts section |
| **offline** | No data for more than 30 minutes | See: Zone is offline |

---

## Zone mode — what it means

| Mode | Meaning |
|---|---|
| **normal** | All sensors working, full watering decisions |
| **no_vpd** | Light or humidity sensor fault — zone waters on moisture only |
| **no_moisture** | Moisture sensor fault — zone waters on a fixed time schedule |
| **local** | Lost connection to the system — ESP32 running its own schedule, no live data |
| **unknown** | First reading not yet received |

If a zone is in `no_vpd`, `no_moisture`, or `local` mode it is still watering, but with reduced information. Log it and inform your administrator.

---

## Manually watering a zone

1. Find the zone row in the dashboard table
2. Click **Water** — the status changes to `watering`
3. The valve closes automatically after the cycle time (typically 15 seconds)

To stop early:

1. Find the zone row showing `watering`
2. Click **Stop** — the valve closes within a few seconds

> If a valve does not close after pressing Stop, or stays open more than 2 minutes, the system will alert automatically and attempt to close it. If the valve is physically stuck, close the manual shutoff valve upstream and contact your administrator immediately.

---

## Viewing zone history

1. Click **History** on any zone row (or click the zone card in Topology)
2. The history page shows moisture, VPD, and temperature charts over time
3. Use the date range picker to zoom in on a specific period
4. The watering events table shows when each valve opened, what triggered it, duration, and before/after moisture
5. Click **Export CSV** to download the data

---

## Alerts

When something goes wrong, the system sends an alert by email or SMS and logs it in the alert log.

### What each alert means

| Alert | What it means |
|---|---|
| **Zone offline** | No data for more than 30 minutes — power outage, WiFi drop, or hardware fault |
| **Critical dry** | Moisture at 10% or below — zone needs water urgently. System is attempting emergency watering. |
| **Valve stuck open** | Valve open more than 2 minutes — system has attempted to close it. Check physically. |
| **Sensor fault** | Sensor reporting a hardware failure — zone switches to reduced operating mode |
| **Sensor out of bounds** | A reading came in that's physically impossible — discarded, last good value kept. Usually a brief glitch. |
| **Stuck moisture** | Moisture reading unchanged for 6+ hours while not watering — sensor likely coated or corroded |
| **Freeze risk** | Air temperature at 2°C or below — all watering suspended, valves closed automatically |
| **Dripper degraded** | Repeated waterings with no moisture rise — emitter likely blocked or scaled |

### Viewing the alert log

Click **Logs** in the navigation bar. Filter by All / Active / Resolved. Each entry shows the zone, fault type, when it started, and when it resolved.

Most alerts resolve automatically when the underlying condition clears — you do not need to manually clear them.

---

## What to do when things go wrong

### Zone is offline

- Check the enclosure at the site — the ESP32 board should have a power LED lit
- Check whether other zones at the same site are also offline — if yes, it is likely a site-wide power or network issue, not a single zone fault
- Check that all cables are seated in their terminal blocks if the enclosure was recently opened
- If you cannot resolve it: note the time, zone ID, and contact your administrator

### Moisture reading seems wrong

- Check the sensor is still inserted correctly at 45° angle to root depth — it may have been dislodged during plant work
- At hard water sites, calcium buildup on the sensor tines causes readings to drift low — clean with a soft brush and mild citric acid solution, then reinsert
- If the reading is completely flat for hours: sensor may have failed — contact your administrator

### A valve will not open

- Does the dashboard status change to `watering` when you press Water? If yes, the command was received — the fault is at the valve
- Check that the water supply is turned on upstream
- If the relay LED on the ESP32 enclosure lights when you press Water but the valve doesn't open, the solenoid or valve seat may be faulty

### A valve will not close

1. **Close the manual shutoff valve** upstream immediately — stops water flow regardless of solenoid state
2. Note the time and zone ID
3. Contact your administrator

Do not leave a stuck-open valve unattended.

### All zones at one site offline at once

The site's 4G connection is likely down. Check the 4G router has power and signal. The zones will continue watering on their own internal schedule — the system is designed to keep running without the server. When the connection restores, all data syncs automatically.

### Cannot load the dashboard at all

The central server may be down. Contact your administrator.

---

## Settings

The Settings page is password-protected. Contact your administrator for access. It covers email and SMS configuration, alert routing, and OTA firmware version for ESP32 updates.

---

## Routine maintenance

These are physical tasks that keep the system accurate. Your administrator will confirm the schedule for your site.

| Task | Frequency | Why |
|---|---|---|
| Clean moisture sensors | Every 3 months | Calcium buildup causes readings to drift |
| Inspect drip emitters for blockages | Monthly | Scale and debris cause uneven watering |
| Flush drip lines with citric acid | Every 6 months (hard water) | Prevents progressive scale buildup |
| Inspect solenoid valves for slow closing | Every 6 months | Early sign of debris on valve seat |
| Replace solenoid valves | Every 12 months (hard water) | Scale eventually causes valve failure |
| Check sensor placement | After any plant management work | Sensors can be dislodged during pruning or repotting |

---

## What you don't need to worry about

The system is designed to keep going when things go wrong. If a sensor fails, the zone switches to a fallback schedule rather than stopping entirely. If the server crashes, valves close themselves automatically within 60 seconds. If WiFi drops, each ESP32 runs its own local watering schedule until it reconnects. If the internet goes down, the local hub keeps everything running until it's restored.

You grow the plants. NurseryHub handles the watching.

---

## Contacting support

**Information to have ready:**
- Component ID of the affected hardware (read the label)
- What the Topology or dashboard shows (status, mode, last seen)
- What alert was received (copy the text)
- What you have already checked

The more specific you can be, the faster the problem can be resolved.

---

## Quick reference card

Print this and keep it at the site.

```
┌─────────────────────────────────────────────────────────────────┐
│  NurseryHub — Quick Reference                                   │
│                                                                 │
│  Dashboard:  http://___________________________:4000            │
│  On-site:    http://___________________________:4000            │
│  Topology:   [above address]/topology                           │
│                                                                 │
│  FAULT IN THE FIELD?                                            │
│  1. Open Topology page → find the coloured card                 │
│  2. Read the component ID from the card                         │
│  3. Find the hardware with that ID label                        │
│                                                                 │
│  STATUS COLOURS                                                 │
│  green  — online, normal                                        │
│  blue   — watering in progress                                  │
│  yellow — alert, check the card                                 │
│  red    — offline, check power and network                      │
│                                                                 │
│  TO MANUALLY WATER:  Table view → Water button                  │
│  TO STOP WATERING:   Table view → Stop button                   │
│  VALVE WON'T CLOSE:  Close manual shutoff → call admin          │
│                                                                 │
│  ALERTS                                                         │
│  critical_dry      — moisture ≤10%, water urgently              │
│  valve_stuck_open  — close manual shutoff, call admin           │
│  zone_offline      — check power and WiFi at site               │
│  sensor_fault      — zone still watering, inform admin          │
│  freeze_risk       — watering suspended, check frost protection │
│                                                                 │
│  Admin contact: _______________________________                 │
└─────────────────────────────────────────────────────────────────┘
```
