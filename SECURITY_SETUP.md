# NurseryHub — Security Setup Guide

This guide covers all security steps. Complete these before connecting
any site to the live system.

---

## Security checklist

- [ ] Set MQTT password in Mosquitto
- [ ] Set MQTT credentials in config.exs
- [ ] Set MQTT credentials in ESP32 firmware
- [ ] Change dashboard password in config.exs
- [ ] Regenerate Phoenix secret keys
- [ ] Set up VPN between sites and server (recommended)
- [ ] Set sync API key on central server and site Pi

---

## Step 1 — Set up Mosquitto authentication

Mosquitto by default accepts any connection. This must be changed.

**Open Command Prompt as Administrator:**

```
cd "C:\Program Files\mosquitto"
```

Create the password file with two users — one for the server app,
one for the ESP32 devices:

```
mosquitto_passwd -c passwordfile nursery_hub
```
(enter a strong password — this goes in config.exs as `mqtt_password`)

```
mosquitto_passwd passwordfile esp32_device
```
(enter a different strong password — this goes in the ESP32 firmware as MQTT_PASS)

**Copy the config file:**

Copy `nursery_hub\mosquitto_config\mosquitto.conf` to:
```
C:\Program Files\mosquitto\mosquitto.conf
```

**Restart Mosquitto:**
```
net stop mosquitto
net start mosquitto
```

**Verify auth is working:**
```
mosquitto_sub -t "test" -v
```
This should now fail with "Connection Refused: not authorised".

```
mosquitto_sub -u nursery_hub -P YOUR_PASSWORD -t "test" -v
mosquitto_pub -u nursery_hub -P YOUR_PASSWORD -t "test" -m "hello"
```
This should succeed.

---

## Step 2 — Set MQTT credentials in config.exs

Edit `nursery_hub\config\config.exs`:

```elixir
config :nursery_hub,
  mqtt_username: "nursery_hub",
  mqtt_password: "your_mqtt_password_here",   # ← the password you set in Step 1
  ...
```

---

## Step 3 — Set MQTT credentials in ESP32 firmware

Edit `esp32_firmware\ESP32_Plant_Monitor_v4.ino`:

```cpp
#define MQTT_USER   "esp32_device"
#define MQTT_PASS   "your_esp32_mqtt_password"   // ← password from Step 1
```

Re-upload to every ESP32.

---

## Step 4 — Change the dashboard password

Edit `nursery_hub\config\config.exs`:

```elixir
config :nursery_hub, :dashboard_auth,
  username: "admin",
  password: "your_strong_dashboard_password"   # ← change this
```

Restart the app after changing. Browser will prompt for login on next visit.

---

## Step 5 — Regenerate Phoenix secret keys

The secret_key_base signs session cookies. Generate a unique one:

```bash
cd nursery_hub
mix phx.gen.secret
```

Copy the output into `config/config.exs`:

```elixir
config :nursery_hub, NurseryHubWeb.Endpoint,
  secret_key_base: "paste_the_generated_value_here",
  live_view: [signing_salt: "paste_first_24_chars_here"],
  ...
```

---

## Step 6 — VPN between sites and server (recommended)

Without a VPN, ESP32s at remote sites must reach your server over the open
internet. Even with MQTT passwords, traffic is unencrypted.

**Recommended: WireGuard VPN**

WireGuard creates an encrypted tunnel between each site's 4G router and
your server. MQTT traffic travels inside the tunnel and never touches the
open internet in plain text.

**Many GL.iNet routers have WireGuard built in** — this is the easiest path.

**Overview of the setup:**

```
Site 4G router ──[WireGuard tunnel, encrypted]──▶ Your server
ESP32 connects to router's local WiFi
Router forwards MQTT traffic through the tunnel
Server's Mosquitto only listens on the VPN interface
```

**Server side (Windows):**
1. Download WireGuard from **wireguard.com**
2. Create a server config — WireGuard will guide you through key generation
3. Note the server's VPN IP (e.g. `10.0.0.1`)
4. Update `config.exs` to use the VPN interface IP if needed

**Router side (GL.iNet with WireGuard support):**
1. Log into the router admin panel
2. VPN → WireGuard Client → add your server config
3. Set to connect automatically on boot

**After VPN is set up:**
Update `mosquitto.conf` to listen on the VPN interface:
```
listener 1883 10.0.0.1
```
This means only devices connected via VPN can reach the MQTT broker —
even if someone scans the internet they cannot find or connect to it.

---

## Step 7 — Set the sync API key

The sync API (`POST /api/sync/readings`) is how site Pi devices push buffered readings to the central server. Without authentication, anyone who knows the URL could inject fake readings.

**On the central server** — edit `config/config.exs`:
```elixir
config :nursery_hub, :sync_api_key, "your_strong_random_key_here"
```

Generate a random key:
```bash
mix phx.gen.secret 32
```
(copy the output as your key)

**On each site Pi** — set the environment variable before building firmware:
```
export SYNC_API_KEY=your_strong_random_key_here
```
Or hard-code it in `config/nerves.exs`:
```elixir
config :nursery_hub, :sync_api_key, "your_strong_random_key_here"
```

The key must be identical on both ends. The Pi sends it as an `X-Sync-Key` HTTP header with every batch push. The central server rejects any request with a missing or wrong key with a 401 response.

The health check endpoint (`GET /api/sync/health`) does not require the key — it is only used for WAN detection and contains no data.

---

## What each security measure protects against

| Measure | Protects against |
|---|---|
| MQTT authentication | Unauthorised devices sending fake sensor data or valve commands |
| Dashboard login | Unauthorised viewing of site data or triggering watering |
| Phoenix secret keys | Session cookie forgery |
| WireGuard VPN | Traffic interception, man-in-the-middle, port scanning |
| Sync API key | Unauthorised devices pushing fake sensor readings to the central server |

---

## Already built-in protections

These are in the code regardless of the above:

| Protection | Where |
|---|---|
| Valve safety timeout (60s max) | ESP32 firmware — forces valve closed even if server sends bad command |
| Valve stuck-open detection | Elixir zone_server.ex — sends stop command + alerts |
| ESP32 local fallback | Firmware — keeps watering if server unreachable |
| Degraded mode ladder | Firmware — keeps watering through sensor failures |
