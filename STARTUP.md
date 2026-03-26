# NurseryHub — Starting the Server

---

## Every time you want to run the dashboard

### Step 1 — Start Mosquitto (if not already running)

Open Command Prompt as Administrator and run:

```
net start mosquitto
```

If you see "The requested service has already been started" — that's fine, it's already running.

Mosquitto is set to start automatically on Windows boot, so after the first setup you usually won't need this step.

---

### Step 2 — Start the NurseryHub server

Open PowerShell and run:

```
cd C:\Users\Ramon\Downloads\nursery_hub
```

Then:

```
cmd /c "C:\Program Files\Elixir\bin\mix.bat" run -e ":timer.sleep(:infinity)"
```

The terminal will appear to hang — that is correct. It means the server is running. You should see output like:

```
[info] NurseryHub starting...
[info] MQTT connected to localhost:1883 as nursery_hub
[info] Running NurseryHubWeb.Endpoint with Bandit at 0.0.0.0:4000 (http)
[info] Access NurseryHubWeb.Endpoint at http://localhost:4000
```

Leave this window open for as long as you want the server running. Closing it stops the server.

---

### Step 3 — Open the dashboard

Open your browser and go to:

```
http://localhost:4000
```

Log in with the credentials set in `config/config.exs` under `dashboard_auth` (default: admin / CHANGE_THIS_DASHBOARD_PASSWORD).

---

## To stop the server

Press **Ctrl+C** in the PowerShell window running the server.

### If you've closed the PowerShell window (server still running in background)

Open any terminal and run:

```
taskkill /IM beam.smp.exe /F
```

Or find it by port:

```
netstat -ano | findstr :4000
taskkill /PID <pid> /F
```

Replace `<pid>` with the number shown in the first command. This is also the fix for the `:eaddrinuse` error — which means a previous server session is still occupying port 4000.

---

## Optional — run the simulator (no hardware needed)

With the server already running, open a **second** PowerShell window and run:

```
cd C:\Users\Ramon\Downloads\nursery_hub
```

```
cmd /c "C:\Program Files\Elixir\bin\mix.bat" sim
```

This connects as a simulated ESP32 and populates 8 zones across 2 sites (Northcote + Fitzroy) with live sensor data. Press **Ctrl+C** to stop it. The server keeps running.

---

## Troubleshooting

**"running scripts is disabled" error in PowerShell**

Always use the full `cmd /c "C:\Program Files\Elixir\bin\mix.bat" ...` form. Do not use `mix` directly in PowerShell.

**Server starts but dashboard shows no zones**

No ESP32s have connected yet, or the simulator isn't running. Run `mix sim` in a second window to populate the dashboard with test data.

**MQTT connection error on startup**

Mosquitto isn't running. Run `net start mosquitto` in an Administrator Command Prompt first.

**"database not found" or Ecto error on first run**

Run setup first (one time only):

```
cmd /c "C:\Program Files\Elixir\bin\mix.bat" setup
```

Then start the server normally.

---

## Running as a Windows Service (always-on)

If you want NurseryHub to start automatically with Windows without keeping a PowerShell window open, you can wrap it in a Windows service using **NSSM** (Non-Sucking Service Manager):

1. Download NSSM from **nssm.cc**
2. Open Command Prompt as Administrator:
   ```
   nssm install NurseryHub
   ```
3. In the GUI that opens:
   - **Path:** `C:\Program Files\Elixir\bin\mix.bat`
   - **Startup directory:** `C:\Users\Ramon\Downloads\nursery_hub`
   - **Arguments:** `run -e ":timer.sleep(:infinity)"`
4. Click Install service
5. Start it:
   ```
   nssm start NurseryHub
   ```

From then on NurseryHub starts automatically on boot, alongside Mosquitto. To stop or restart it:

```
nssm stop NurseryHub
nssm restart NurseryHub
```
