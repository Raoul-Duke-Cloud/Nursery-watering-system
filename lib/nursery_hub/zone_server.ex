defmodule NurseryHub.ZoneServer do
  @moduledoc """
  The brain for a single ESP32 zone.

  One of these runs for every active zone across all your sites.
  It holds the current state of that zone and watches for problems:

    - Did sensor data stop arriving? (zone went offline)
    - Is the valve stuck open? (potential flooding)
    - Did a sensor fail? (needs alert + mode change)
    - Is moisture critically low? (emergency alert)

  It also handles incoming commands from you (e.g. "manually water zone_a now").

  BEAM guarantees: if this process crashes, the ZoneSupervisor restarts it
  cleanly. Other zones are completely unaffected.
  """

  use GenServer
  require Logger

  alias NurseryHub.{Alerting, AlertLog, ZoneSupervisor, SensorReading, WateringEvent}

  # How often to check for timeouts and stuck valves (every 60 seconds)
  @watchdog_interval_ms 60_000

  # ── State ────────────────────────────────────────────────────────────────

  defstruct [
    :site_id,
    :zone_id,
    :node_id,                # Asset tag of the ESP32 this zone is on (e.g. "ESP-001")
    :last_seen,              # DateTime of last received message
    :moisture,
    :lux,
    :leaf_temp,
    :air_temp,
    :humidity,
    :vpd,
    :watering,               # true/false — is valve currently open?
    :valve_open_since,       # DateTime when valve opened (nil if closed)
    :mode,                   # "normal" | "no_vpd" | "no_moisture" | "local"
    :current_event_id,       # DB id of the open watering event (nil if not watering)
    :pending_check_event_id, # DB id of event waiting for post-drip moisture check
    :valve_closed_at,        # DateTime valve closed — used to match post-drip readings
    sensor_ok: %{},
    sensor_ids: %{},         # asset tags: %{"moisture" => "MST-001", "dht" => "DHT-001", "lux" => "LUX-001", "ir" => "IR-001"}
    alerts: [],              # list of active alert atoms
    faulted_sensors: [],          # sensors currently in fault — used to debounce sensor_fault alerts
    moisture_last_changed_at: nil, # DateTime when moisture last changed by >=2% — for stuck detection
    consecutive_dripper_faults: 0  # counter of back-to-back dripper_fault events — for scale/blockage detection
  ]

  # ── Public API ───────────────────────────────────────────────────────────

  def start_link({site_id, zone_id}) do
    GenServer.start_link(__MODULE__, {site_id, zone_id},
      name: via(site_id, zone_id))
  end

  @doc "Push new sensor data into this zone's process."
  def receive_data(site_id, zone_id, data) do
    case ZoneSupervisor.lookup(site_id, zone_id) do
      {:ok, pid} -> GenServer.cast(pid, {:data, data})
      :not_found -> :ok
    end
  end

  @doc "Send a command to the physical ESP32 for this zone."
  def send_command(site_id, zone_id, command) do
    topic   = "nursery/#{site_id}/#{zone_id}/cmd"
    payload = Jason.encode!(command)
    Tortoise311.publish("nursery_hub_server", topic, payload, qos: 0)
  end

  @doc "Get a snapshot of this zone's current state."
  def state(site_id, zone_id) do
    case ZoneSupervisor.lookup(site_id, zone_id) do
      {:ok, pid} -> GenServer.call(pid, :get_state)
      :not_found -> {:error, :not_found}
    end
  end

  # ── GenServer callbacks ──────────────────────────────────────────────────

  @impl true
  def init({site_id, zone_id}) do
    # Register so ZoneSupervisor can find us by {site_id, zone_id}
    Registry.register(NurseryHub.ZoneRegistry, {site_id, zone_id}, nil)

    # Start the watchdog — checks every minute for timeouts and stuck valves
    schedule_watchdog()

    state = %__MODULE__{
      site_id:  site_id,
      zone_id:  zone_id,
      last_seen: nil,
      mode:     "unknown",
      alerts:   []
    }

    Logger.info("[#{site_id}/#{zone_id}] Zone process started")
    {:ok, state}
  end

  # ── Handle incoming sensor data ──────────────────────────────────────────

  @impl true
  def handle_cast({:data, data}, state) do
    now = DateTime.utc_now()
    old_moisture = state.moisture
    {data, oob_fields} = validate_bounds(data)
    watering_now = data["watering"] == true

    new_state = %{state |
      last_seen:   now,
      node_id:     data["node_id"] || state.node_id,
      sensor_ids:  (if is_map(data["sensor_ids"]), do: data["sensor_ids"], else: state.sensor_ids),
      moisture:    data["moisture"],
      lux:         data["lux"],
      leaf_temp:   data["leaf_temp"],
      air_temp:    data["air_temp"],
      humidity:    data["humidity"],
      vpd:         data["vpd"],
      watering:    watering_now,
      mode:        data["mode"] || "unknown",
      sensor_ok:   data["sensor_ok"] || %{}
    }

    # Track valve transitions for stuck-open detection and watering events
    new_state = cond do
      # Valve just opened
      watering_now and is_nil(state.valve_open_since) ->
        event_id = open_watering_event(state, data, now)
        %{new_state | valve_open_since: now, current_event_id: event_id}

      # Valve just closed
      not watering_now and not is_nil(state.valve_open_since) ->
        close_watering_event(state, data, now)
        %{new_state | valve_open_since: nil, current_event_id: nil,
          pending_check_event_id: state.current_event_id, valve_closed_at: now}

      true ->
        new_state
    end

    # Post-drip moisture check — update event with moisture_after if enough time has passed
    new_state = maybe_record_moisture_after(new_state, data, now)

    new_state = track_moisture_change(new_state, old_moisture, data["moisture"], now)

    new_state = new_state
      |> check_out_of_bounds(oob_fields)
      |> maybe_clear_stuck_moisture(old_moisture)
      |> maybe_clear_freeze()
      |> check_sensor_faults()
      |> check_critical_moisture()
      |> check_dripper_degraded(data["dripper_fault"])
      |> clear_offline_alert()

    # Persist reading to database
    SensorReading.insert(state.site_id, state.zone_id, data)

    # Broadcast to dashboard (LiveView picks this up in real time)
    Phoenix.PubSub.broadcast(
      NurseryHub.PubSub,
      "zones:updates",
      {:zone_update, new_state}
    )

    {:noreply, new_state}
  end

  # ── Handle state query ───────────────────────────────────────────────────

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # ── Watchdog — runs every minute ─────────────────────────────────────────

  @impl true
  def handle_info(:watchdog, state) do
    new_state = state
      |> check_zone_timeout()
      |> check_valve_stuck_open()
      |> check_stuck_moisture()
      |> check_freeze_risk()

    schedule_watchdog()
    {:noreply, new_state}
  end

  # ── Checks ───────────────────────────────────────────────────────────────

  # Zone has gone quiet — no data for too long
  defp check_zone_timeout(%{last_seen: nil} = state), do: state
  defp check_zone_timeout(state) do
    timeout_minutes = Application.get_env(:nursery_hub, :zone_timeout_minutes, 30)
    minutes_silent  = DateTime.diff(DateTime.utc_now(), state.last_seen, :minute)

    if minutes_silent >= timeout_minutes and :offline not in state.alerts do
      Alerting.alert(:zone_offline, state.site_id, state.zone_id, %{
        silent_for_minutes: minutes_silent
      })
      %{state | alerts: [:offline | state.alerts]}
    else
      state
    end
  end

  # Valve has been open longer than the safety limit
  defp check_valve_stuck_open(%{valve_open_since: nil} = state), do: state
  defp check_valve_stuck_open(state) do
    max_seconds = Application.get_env(:nursery_hub, :valve_max_open_seconds, 120)
    open_seconds = DateTime.diff(DateTime.utc_now(), state.valve_open_since, :second)

    if open_seconds > max_seconds and :valve_stuck not in state.alerts do
      Alerting.alert(:valve_stuck_open, state.site_id, state.zone_id, %{
        open_for_seconds: open_seconds
      })
      # Command the ESP32 to stop watering immediately
      send_command(state.site_id, state.zone_id, %{cmd: "stop"})
      %{state | alerts: [:valve_stuck | state.alerts]}
    else
      state
    end
  end

  # One or more sensors reported as faulty — only alerts when the fault set changes
  defp check_sensor_faults(state) do
    current_faults =
      state.sensor_ok
      |> Enum.filter(fn {_sensor, ok} -> ok == false end)
      |> Enum.map(fn {sensor, _} -> sensor end)
      |> Enum.sort()

    prev_faults = Enum.sort(state.faulted_sensors)

    cond do
      # New faults or the set of faulted sensors has changed — alert
      current_faults != [] and current_faults != prev_faults ->
        Alerting.alert(:sensor_fault, state.site_id, state.zone_id, %{
          failed_sensors: current_faults,
          operating_mode: state.mode
        })
        new_alerts = [:sensor_fault | Enum.reject(state.alerts, &(&1 == :sensor_fault))]
        %{state | faulted_sensors: current_faults, alerts: new_alerts}

      # All sensors recovered — clear the fault
      current_faults == [] and prev_faults != [] ->
        %{state | faulted_sensors: [], alerts: Enum.reject(state.alerts, &(&1 == :sensor_fault))}

      true ->
        state
    end
  end

  # Moisture critically low — alert even if zone is in degraded mode
  defp check_critical_moisture(%{moisture: nil} = state), do: state
  defp check_critical_moisture(state) do
    if state.moisture <= 10 and :critical_dry not in state.alerts do
      Alerting.alert(:critical_dry, state.site_id, state.zone_id, %{
        moisture: state.moisture
      })
      %{state | alerts: [:critical_dry | state.alerts]}
    else
      state
    end
  end

  # Zone came back online — clear the offline alert and mark it resolved in the log
  defp clear_offline_alert(state) do
    if :offline in state.alerts do
      Logger.info("[#{state.site_id}/#{state.zone_id}] Zone back online")
      AlertLog.resolve(state.site_id, state.zone_id, :zone_offline)
      %{state | alerts: List.delete(state.alerts, :offline)}
    else
      state
    end
  end

  # ── Bounds validation ─────────────────────────────────────────────────────

  # Physical plausibility limits for each sensor field.
  # Out-of-bounds values are discarded (set to nil) and an alert is fired.
  # This catches calibration drift and sensor faults that sensor_ok misses.
  @bounds %{
    "air_temp"  => {-10, 60},
    "humidity"  => {0, 100},
    "vpd"       => {0, 10},
    "lux"       => {0, 150_000},
    "leaf_temp" => {-10, 80},
    "moisture"  => {0, 100}
  }

  defp validate_bounds(data) do
    Enum.reduce(@bounds, {data, []}, fn {field, {min, max}}, {d, oob} ->
      val = d[field]
      if is_number(val) and (val < min or val > max) do
        {Map.put(d, field, nil), [field | oob]}
      else
        {d, oob}
      end
    end)
  end

  # Fire alert if any fields were out of bounds. Clear it when a clean reading arrives.
  defp check_out_of_bounds(state, []) do
    if :out_of_bounds in state.alerts do
      AlertLog.resolve(state.site_id, state.zone_id, :sensor_out_of_bounds)
      %{state | alerts: List.delete(state.alerts, :out_of_bounds)}
    else
      state
    end
  end
  defp check_out_of_bounds(state, fields) do
    if :out_of_bounds not in state.alerts do
      Alerting.alert(:sensor_out_of_bounds, state.site_id, state.zone_id, %{fields: fields})
      %{state | alerts: [:out_of_bounds | state.alerts]}
    else
      state
    end
  end

  # ── Stuck moisture detection ───────────────────────────────────────────────

  # Update moisture_last_changed_at when moisture moves by >=2%.
  # Called on every incoming reading so the watchdog knows how long it's been stuck.
  defp track_moisture_change(state, old_moisture, new_moisture, now) do
    changed =
      is_number(old_moisture) and is_number(new_moisture) and
      abs(new_moisture - old_moisture) >= 2.0

    first_reading = is_nil(old_moisture) and is_number(new_moisture)

    if changed or first_reading do
      %{state | moisture_last_changed_at: now}
    else
      state
    end
  end

  # If moisture has been stuck and then changes, clear the alert.
  defp maybe_clear_stuck_moisture(state, old_moisture) do
    if :stuck_moisture in state.alerts do
      changed =
        is_number(old_moisture) and is_number(state.moisture) and
        abs(state.moisture - old_moisture) >= 2.0
      if changed do
        AlertLog.resolve(state.site_id, state.zone_id, :stuck_moisture)
        %{state | alerts: List.delete(state.alerts, :stuck_moisture)}
      else
        state
      end
    else
      state
    end
  end

  # Watchdog check — fire if moisture hasn't moved in configured hours while not watering.
  defp check_stuck_moisture(%{moisture: nil} = state), do: state
  defp check_stuck_moisture(%{moisture_last_changed_at: nil} = state), do: state
  defp check_stuck_moisture(state) do
    threshold_hours = Application.get_env(:nursery_hub, :stuck_moisture_hours, 6)
    hours_unchanged = DateTime.diff(DateTime.utc_now(), state.moisture_last_changed_at, :hour)

    if hours_unchanged >= threshold_hours and not state.watering and
       :stuck_moisture not in state.alerts do
      Alerting.alert(:stuck_moisture, state.site_id, state.zone_id, %{
        moisture:        state.moisture,
        hours_unchanged: hours_unchanged
      })
      %{state | alerts: [:stuck_moisture | state.alerts]}
    else
      state
    end
  end

  # ── Consecutive dripper fault detection ───────────────────────────────────

  # Tracks back-to-back dripper_fault events from the ESP32.
  # A single fault may be a one-off; consecutive faults indicate progressive
  # blockage (scale buildup, emitter fouling) or a stuck valve.
  # Counter resets on a clean dripper reading. Alert clears on recovery.
  defp check_dripper_degraded(state, true) do
    threshold = Application.get_env(:nursery_hub, :dripper_fault_alert_threshold, 3)
    count = state.consecutive_dripper_faults + 1
    state = %{state | consecutive_dripper_faults: count}

    if count >= threshold and :dripper_degraded not in state.alerts do
      Alerting.alert(:dripper_degraded, state.site_id, state.zone_id, %{
        consecutive_faults: count
      })
      %{state | alerts: [:dripper_degraded | state.alerts]}
    else
      state
    end
  end

  defp check_dripper_degraded(state, false) do
    state = %{state | consecutive_dripper_faults: 0}
    if :dripper_degraded in state.alerts do
      AlertLog.resolve(state.site_id, state.zone_id, :dripper_degraded)
      %{state | alerts: List.delete(state.alerts, :dripper_degraded)}
    else
      state
    end
  end

  defp check_dripper_degraded(state, _), do: state  # nil — no dripper data in this reading

  # ── Freeze protection ─────────────────────────────────────────────────────

  # Called from watchdog every 60s. Fires alert and sends stop command when
  # air_temp drops to or below freeze_alert_celsius. If freeze is already active
  # and the valve somehow opens, re-sends the stop command.
  defp check_freeze_risk(%{air_temp: nil} = state), do: state
  defp check_freeze_risk(state) do
    threshold = Application.get_env(:nursery_hub, :freeze_alert_celsius, 2)

    cond do
      state.air_temp <= threshold and :freeze_risk not in state.alerts ->
        Alerting.alert(:freeze_risk, state.site_id, state.zone_id, %{air_temp: state.air_temp})
        send_command(state.site_id, state.zone_id, %{cmd: "freeze"})
        %{state | alerts: [:freeze_risk | state.alerts]}

      :freeze_risk in state.alerts and state.watering ->
        # Freeze still active — re-send freeze if valve has somehow opened
        send_command(state.site_id, state.zone_id, %{cmd: "freeze"})
        state

      true ->
        state
    end
  end

  # Called on every incoming reading. Clears freeze alert once temp recovers
  # above freeze_clear_celsius (hysteresis prevents rapid alert flip-flopping).
  defp maybe_clear_freeze(%{air_temp: nil} = state), do: state
  defp maybe_clear_freeze(state) do
    clear_threshold = Application.get_env(:nursery_hub, :freeze_clear_celsius, 4)

    if :freeze_risk in state.alerts and state.air_temp >= clear_threshold do
      Logger.info("[#{state.site_id}/#{state.zone_id}] Freeze cleared — temp #{state.air_temp}°C")
      AlertLog.resolve(state.site_id, state.zone_id, :freeze_risk)
      send_command(state.site_id, state.zone_id, %{cmd: "unfreeze"})
      %{state | alerts: List.delete(state.alerts, :freeze_risk)}
    else
      state
    end
  end

  # ── Watering event helpers ────────────────────────────────────────────────

  defp open_watering_event(state, data, now) do
    case WateringEvent.open(state.site_id, state.zone_id, %{
      trigger:          data["trigger"] || "auto",
      started_at:       now,
      moisture_before:  state.moisture,
      vpd_at_start:     state.vpd,
      lux_at_start:     state.lux,
      dripper_baseline: data["dripper_baseline"]
    }) do
      {:ok, event} -> event.id
      {:error, _}  -> nil
    end
  end

  defp close_watering_event(state, data, now) do
    if state.current_event_id do
      duration_ms = DateTime.diff(now, state.valve_open_since, :millisecond)
      WateringEvent.close(state.current_event_id, %{
        stopped_at:   now,
        duration_ms:  duration_ms,
        dripper_fault: data["dripper_fault"]
      })
    end
  end

  # After the valve closes, watch for the post-drip moisture reading.
  # The ESP32 checks moisture ~2min after drip stops (DRIP_CHECK_DELAY).
  # We accept any reading between 1-5 minutes after close as the result.
  defp maybe_record_moisture_after(%{pending_check_event_id: nil} = state, _data, _now), do: state
  defp maybe_record_moisture_after(state, data, now) do
    seconds_since_close = DateTime.diff(now, state.valve_closed_at, :second)

    if seconds_since_close >= 60 and seconds_since_close <= 300 and data["moisture"] do
      WateringEvent.close(state.pending_check_event_id, %{
        moisture_after: data["moisture"],
        moisture_rise:  (data["moisture"] || 0) - (get_moisture_before(state.pending_check_event_id)),
        dripper_fault:  data["dripper_fault"]
      })
      %{state | pending_check_event_id: nil, valve_closed_at: nil}
    else
      state
    end
  end

  defp get_moisture_before(event_id) do
    case NurseryHub.Repo.get(WateringEvent, event_id) do
      nil   -> 0
      event -> event.moisture_before || 0
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp schedule_watchdog do
    Process.send_after(self(), :watchdog, @watchdog_interval_ms)
  end

  defp via(site_id, zone_id) do
    {:via, Registry, {NurseryHub.ZoneRegistry, {site_id, zone_id}}}
  end
end
