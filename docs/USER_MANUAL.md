# NurseryHub — User Manual

This manual is for the people who operate the nursery day to day. You do not need to understand how the system was built to use it. If something is not working and this manual does not resolve it, contact your system administrator.

---

## What the system does

NurseryHub monitors every watering zone across your nursery and waters automatically based on soil moisture. It watches for problems — dry zones, stuck valves, sensor failures, offline zones — and sends you alerts by email or SMS when something needs attention.

You interact with the system through a web dashboard that you open in any browser.

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

Your system administrator will give you the correct addresses for your site. Bookmark them.

You will be asked to log in with a username and password. Your administrator will provide these.

---

## The main dashboard

When you log in you will see a table with one row per zone. Here is what each column means:

| Column | What it shows |
|---|---|
| **Site** | Which nursery location this zone is at |
| **Zone** | The zone name (matches the label on the physical valve and sensor) |
| **Status** | Whether the zone is working normally right now |
| **Mode** | What information the zone is using to make watering decisions |
| **Moisture** | Current soil moisture % |
| **Air Temp** | Air temperature at canopy height |
| **Humidity** | Relative humidity % |
| **VPD** | Vapour pressure deficit — a measure of how much the air is driving water out of the plants |
| **Light** | Light level in lux |
| **Leaf Temp** | Leaf surface temperature (infrared) |
| **Last Seen** | When the zone last sent a reading to the system |
| **Actions** | Buttons to water, stop, or view history for this zone |

The dashboard updates automatically every 30 seconds — you do not need to refresh the page.

---

## Zone status — what the colours mean

| Status | Meaning | What to do |
|---|---|---|
| **online** | Zone is working normally | Nothing |
| **watering** | Zone valve is currently open and watering | Normal — will close automatically |
| **alert** | Zone has a problem that needs attention | Read the alert — see Section: Alerts |
| **offline** | No data received from this zone for more than 30 minutes | See Section: Zone is offline |

---

## Zone mode — what it means

| Mode | Meaning |
|---|---|
| **normal** | All sensors working, zone making full decisions |
| **no_vpd** | Light or humidity sensor has a fault — zone still waters but based on moisture only |
| **no_moisture** | Moisture sensor has a fault — zone waters on a fixed time schedule instead |
| **local** | Zone has lost connection to the system — ESP32 is running on its own internal schedule. No live data until connection restores. |
| **unknown** | Zone has not yet sent its first reading since startup |

If a zone is in `no_vpd`, `no_moisture`, or `local` mode, it is still watering but with reduced information. Log it and inform your administrator.

---

## Manually watering a zone

You can trigger a watering cycle for any zone at any time from the dashboard.

1. Find the zone row in the dashboard table
2. Click the **Water** button in the Actions column
3. The zone status will change to `watering`
4. The valve will close automatically after the configured cycle time (typically 15 seconds for a manual trigger)

To stop a watering cycle before it finishes:

1. Find the zone row — it will show status `watering`
2. Click the **Stop** button in the Actions column
3. The valve will close within a few seconds

> **Note:** If a valve does not close after pressing Stop, or remains open for more than 2 minutes, the system will send a `valve_stuck_open` alert automatically and attempt to close it. If the valve is physically stuck, close the manual shutoff valve upstream and contact your administrator immediately.

---

## Viewing zone history

To see the history of sensor readings and watering events for a zone:

1. Find the zone row in the dashboard table
2. Click the **History** button in the Actions column
3. The zone history page shows moisture, VPD, and temperature charts over time, and a table of all watering events
4. Use the date range picker to zoom in on a specific period
5. Click **Export CSV** to download the data as a spreadsheet

---

## Alerts

When something goes wrong, the system sends you an alert by email or SMS (depending on your settings) and logs it in the alert log.

### Types of alerts

| Alert | What it means |
|---|---|
| **Zone offline** | A zone has not sent any data for more than 30 minutes. Could be a power outage, WiFi dropout, or hardware fault. |
| **Critical dry** | Soil moisture has dropped to 10% or below. The zone needs water urgently. |
| **Valve stuck open** | A valve has been open for more than 2 minutes without closing. The system has attempted to close it. Check physically. |
| **Sensor fault** | A sensor has stopped working or is reporting impossible values. The zone will continue operating in a reduced mode. |
| **Stuck moisture** | The moisture reading has not changed for more than 6 hours while the zone has not been watering. The sensor may need cleaning or reseating. |

### Viewing the alert log

Click **Logs** in the navigation bar. You can filter by:
- **All** — every alert, resolved or active
- **Active** — alerts that are still ongoing
- **Resolved** — alerts that have cleared

Each alert shows the zone, the type of fault, when it started, and when it resolved (if it has).

### When an alert resolves itself

Many alerts resolve automatically when the underlying condition clears — for example, a zone offline alert resolves when the zone comes back online. You do not need to manually clear these.

---

## What to do when things go wrong

### Zone is offline

A zone offline alert means no data has arrived from that zone in over 30 minutes.

**Check first:**
- Is the power on at that enclosure? Check the enclosure at the site — the ESP32 board should have a power LED lit.
- Is the site WiFi working? Check that other zones at the same site are still online. If all zones at a site are offline simultaneously, it is likely a network or power issue affecting the whole site, not individual zones.
- Has the enclosure been opened recently? Check that all cables are seated in their terminal blocks.

**If you cannot resolve it:** Log the time and zone, and contact your administrator.

### Moisture reading seems wrong

If a moisture reading looks too high or too low and does not match what you observe in the soil:

- The sensor may have shifted out of position — check the physical sensor is still inserted correctly at 45° angle to root depth
- At hard water sites, calcium buildup on the sensor tines causes readings to drift low over time — clean the sensor with a soft brush and mild citric acid solution, then reinsert
- If the reading is completely flat (not changing at all over hours), the sensor may have failed — contact your administrator

### A valve will not open

If you press Water and the zone does not start watering:

- Check the dashboard — does the status change to `watering`? If yes, the command was received. The fault is at the valve.
- Check the physical valve: is the solenoid receiving power? Is water supply turned on upstream?
- Check the relay LED on the ESP32 enclosure — if the relay LED lights when you press Water but the valve does not open, the solenoid or valve seat may be faulty.

### A valve will not close

If a zone is stuck in `watering` state and pressing Stop does not help:

1. **Close the manual shutoff valve** upstream of the solenoid block immediately — this physically stops water flow regardless of the solenoid state
2. Note the time and zone
3. Contact your administrator

Do not leave a stuck-open valve unattended.

### All zones showing offline at once

This usually means the central server or the site hub (Pi) has stopped running, or the network connection between the site and the server has been lost.

- Check whether the dashboard itself is loading. If you cannot load the dashboard at all, the server may be down — contact your administrator.
- If the dashboard loads but all zones at one site are offline, the site's network connection (4G) is likely down. Check the 4G router at the site has power and signal. Zones at the site will continue to water automatically on their own internal schedule while the connection is down — the system is designed to keep running without the server.

---

## Settings

The Settings page (accessible from the navigation bar) is password-protected. Contact your administrator for access.

Settings include email and SMS configuration, alert routing (which alerts trigger email vs SMS), and OTA firmware version for ESP32 updates.

---

## Routine maintenance reminders

These are not software tasks — they are physical tasks that keep the system accurate. Your administrator will confirm the schedule for your site.

| Task | Frequency | Why |
|---|---|---|
| Clean moisture sensors | Every 3 months | Calcium and mineral buildup causes readings to drift, especially at hard water sites |
| Inspect drip emitters for blockages | Monthly | Scale and debris block emitters, causing uneven watering |
| Flush drip lines with citric acid solution | Every 6 months (hard water sites) | Prevents progressive scale buildup in pipes |
| Inspect solenoid valves for slow closing | Every 6 months | Early sign of debris on valve seat |
| Replace solenoid valves | Every 12 months (hard water sites) | Scale on valve seat eventually causes valve failure |
| Check sensor physical placement | After any plant management work | Sensors can be dislodged during pruning or repotting |

---

## Contacting support

If you have followed the steps above and cannot resolve the issue:

**Information to have ready:**
- Which site and zone is affected (read the label on the physical hardware)
- What the dashboard shows (status, mode, last seen time)
- What alert was received (copy the alert text)
- What you have already checked or tried

The more specific you can be, the faster the problem can be resolved.

---

## Quick reference card

Print this section and keep it at the site.

```
┌─────────────────────────────────────────────────────────────────┐
│  NurseryHub — Quick Reference                                   │
│                                                                 │
│  Dashboard: http://___________________________:4000             │
│  On-site:   http://___________________________:4000             │
│                                                                 │
│  STATUS COLOURS                                                 │
│  online    — normal, no action needed                           │
│  watering  — valve open, watering in progress                   │
│  alert     — fault, check alert log                             │
│  offline   — no data >30 min, check power and network           │
│                                                                 │
│  TO MANUALLY WATER:  Dashboard → Water button                   │
│  TO STOP WATERING:   Dashboard → Stop button                    │
│  VALVE WON'T CLOSE:  Close manual shutoff valve → call admin    │
│                                                                 │
│  ALERTS                                                         │
│  critical_dry      — moisture ≤10%, zone needs water urgently   │
│  valve_stuck_open  — close manual shutoff, call admin           │
│  zone_offline      — check power and WiFi at site               │
│  sensor_fault      — zone still watering, log and inform admin  │
│                                                                 │
│  Admin contact: _______________________________                 │
└─────────────────────────────────────────────────────────────────┘
```
