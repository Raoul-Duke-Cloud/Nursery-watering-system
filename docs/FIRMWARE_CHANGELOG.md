# ESP32 Firmware Changelog

## v5.0 (current)

### Dual soil moisture sensors (ADS1115)
- Added support for a secondary capacitive moisture sensor per zone via ADS1115 I2C ADC
- Primary sensors remain on ESP32 analog pins (GPIO32–35); secondary sensors on ADS1115 channels A0–A3
- Cross-comparison: readings averaged when within 10%; `moisture_diverged: true` flagged in MQTT payload when outside 10%
- Single-sensor fallback if one fails
- Controlled by `#define DUAL_MOISTURE true/false` at top of firmware

### Dual DHT22 (air temperature + humidity)
- Added second DHT22 on GPIO4
- Cross-comparison: averaged when within 2°C / 5% RH; `dht_diverged: true` flagged in MQTT payload when outside limits
- Single-sensor fallback if one fails
- Both sensors run in same radiation shield housing

### Freeze / unfreeze commands
- New MQTT command: `{"cmd": "freeze"}` — closes all valves immediately, sets freeze mode; `controlZone()` ignores all watering requests while frozen
- New MQTT command: `{"cmd": "unfreeze"}` — clears freeze mode, watering resumes
- Server-side: ZoneServer sends `freeze` when air temp ≤ 2°C (configurable), `unfreeze` when temp ≥ 4°C
- Freeze mode status shown in serial output

### Boot self-test extended
- Self-test now includes secondary moisture sensors and second DHT22
- Results reported via MQTT on startup

---

## v4.2 (previous)
- Dripper baseline learning and `dripper_fault` detection
- VPD calculation from DHT22 + leaf temp
- OTA firmware update with bootloader auto-rollback
- Local fallback watering when server unreachable
- MicroSD local backup of readings
- Operating mode reporting (`normal`, `no_vpd`, `no_moisture`, `local`)

---

## v4.1
- Multi-zone support (up to 4 zones per ESP32)
- MQTT data publish every 30s
- Valve safety timeout: forces close after 60s regardless of server commands
- Degraded mode ladder on sensor failure
