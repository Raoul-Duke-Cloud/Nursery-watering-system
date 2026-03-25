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

  alias NurseryHub.{Alerting, ZoneSupervisor, SensorReading}

  # How often to check for timeouts and stuck valves (every 60 seconds)
  @watchdog_interval_ms 60_000

  # ── State ────────────────────────────────────────────────────────────────

  defstruct [
    :site_id,
    :zone_id,
    :last_seen,         # DateTime of last received message
    :moisture,
    :lux,
    :leaf_temp,
    :air_temp,
    :humidity,
    :vpd,
    :watering,          # true/false — is valve currently open?
    :valve_open_since,  # DateTime when valve opened (nil if closed)
    :mode,              # "normal" | "no_vpd" | "no_moisture" | "local"
    sensor_ok: %{},
    alerts: []          # list of active alert types
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

    new_state = %{state |
      last_seen:   now,
      moisture:    data["moisture"],
      lux:         data["lux"],
      leaf_temp:   data["leaf_temp"],
      air_temp:    data["air_temp"],
      humidity:    data["humidity"],
      vpd:         data["vpd"],
      watering:    data["watering"] == true,
      mode:        data["mode"] || "unknown",
      sensor_ok:   data["sensor_ok"] || %{}
    }

    # Track when valve opened (for stuck-open detection)
    new_state = cond do
      new_state.watering and is_nil(state.valve_open_since) ->
        %{new_state | valve_open_since: now}

      not new_state.watering ->
        %{new_state | valve_open_since: nil}

      true ->
        new_state
    end

    new_state = new_state
      |> check_sensor_faults()
      |> check_critical_moisture()
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

  # One or more sensors reported as faulty
  defp check_sensor_faults(state) do
    faults = state.sensor_ok
      |> Enum.filter(fn {_sensor, ok} -> ok == false end)
      |> Enum.map(fn {sensor, _} -> sensor end)

    if faults != [] do
      Alerting.alert(:sensor_fault, state.site_id, state.zone_id, %{
        failed_sensors: faults,
        operating_mode: state.mode
      })
    end

    state
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

  # Zone came back online — clear the offline alert
  defp clear_offline_alert(state) do
    if :offline in state.alerts do
      Logger.info("[#{state.site_id}/#{state.zone_id}] Zone back online")
      %{state | alerts: List.delete(state.alerts, :offline)}
    else
      state
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
