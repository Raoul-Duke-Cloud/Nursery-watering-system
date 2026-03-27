# How NurseryHub Works

## What It Does

NurseryHub keeps an eye on your nursery so you don't have to watch it constantly. Sensors placed throughout your growing areas measure soil moisture, air temperature, humidity, and light levels — all the things that tell you whether your plants are comfortable. When soil gets dry, the system turns on the water. When something looks wrong, it sends you an alert. You can check the status of every zone in your nursery from any web browser, whether you're in the shed or off-site.

The goal is simple: your plants get the right amount of water at the right time, you get notified when something needs your attention, and everything keeps running even when technology misbehaves.

---

## A Typical Day

Every 30 seconds, the sensors in each zone take a reading and send it back to the system. You don't need to do anything — the data just flows in continuously, building up a picture of what's happening across your nursery.

If you open the dashboard at any point, you'll see all your zones listed with their current moisture, temperature, humidity, and light readings. Green means everything is fine. The system handles watering automatically in the background, so most days you won't need to touch it at all.

---

## How Watering Works

The system watches the soil moisture in each zone. When a zone gets dry enough to need water, it opens the valve for a short burst — 15 seconds by default. After that, it waits and checks whether the moisture level actually went up. If it did, the soil absorbed the water as expected and the cycle continues normally.

If the moisture doesn't rise after the watering, the system tries again. If repeated waterings produce no response in the soil, it sends you an alert: something may be blocking the dripper — a piece of grit, scale buildup from hard water, or a kinked line. This is one of the most practical things the system catches, because a blocked emitter is easy to miss until a plant is already in trouble.

---

## Alerts — What They Mean

The system sends alerts when it sees something that needs a human decision. Here's what each one means in plain terms:

**Zone offline** — one of the sensor units stopped checking in. This usually means a power cut to that unit, a WiFi drop, or a hardware fault. Check that it's powered and connected.

**Valve stuck open** — a valve has been open longer than it should be. The system already sent a command to close it and is letting you know. Go check whether the valve physically closed — if it didn't, it may need cleaning or replacement.

**Sensor fault** — a sensor is reporting a hardware failure. Watering in that zone won't stop; it switches to a basic timed schedule so your plants aren't left dry while you sort it out. But the sensor will need attention.

**Critically dry** — soil moisture has dropped below 10%. The system is already attempting emergency watering, but you should check the zone — something may be preventing water from reaching the plants.

**Sensor out of bounds** — a reading came in that's physically impossible (for example, -50°C on a warm day). The system discards the bad reading and keeps the last known good value. Usually this is a brief glitch, but if it keeps happening the sensor may need replacing.

**Stuck moisture** — the moisture reading hasn't changed in six hours, and it wasn't a period when watering was suspended. A moisture sensor that never moves is often coated in calcium or starting to corrode. Pull it out and give it a clean.

**Freeze risk** — air temperature has hit 2°C or below. All watering is suspended and valves are closed automatically. You'll get an alert so you can take any additional steps you need for frost protection.

**Dripper degraded** — after several consecutive waterings, the soil moisture still hasn't moved. The emitter is likely blocked or scaled up, which is especially common with hard water. Time to flush or replace it.

---

## During an Internet Outage

If your internet connection drops, the system keeps running on your local network. Your sensors keep talking to the local hub (a Raspberry Pi on your property) — they have no idea the internet is gone. The Pi keeps recording everything and can still send email alerts. If you're on-site, you can check the dashboard as normal by going to the Pi's local address in your browser.

When the internet comes back, the Pi automatically sends everything it recorded up to the central server. There are no gaps in your data — it just catches up quietly in the background.

---

## The Dashboard

The dashboard gives you an at-a-glance view of every zone. Each zone shows its current readings and a status colour: green for online and normal, blue for actively watering, orange for an alert condition, grey for offline.

From the dashboard you can manually trigger watering in a zone if you want to run a check, or manually stop a valve if one is running longer than you expected. There's also a history view where you can see how moisture and temperature have tracked over time, and an alert log that keeps a record of every notification the system has sent.

---

## Firmware Updates

When a software update is available for the sensors, you increment a version number in the settings and the sensors update themselves the next time they restart. There's no need to pull them out of the ground or connect anything physically.

---

## What You Don't Need to Worry About

The system is designed to keep going when things go wrong. If a sensor fails, the zone switches to a fallback watering schedule rather than stopping entirely. If the server crashes, the valves close themselves automatically within 60 seconds — they won't stay open and flood a bed. If WiFi drops, each sensor unit runs its own local watering schedule until the connection comes back. And if your internet goes down, the local hub keeps everything ticking until it's restored.

You grow the plants. NurseryHub handles the watching.
