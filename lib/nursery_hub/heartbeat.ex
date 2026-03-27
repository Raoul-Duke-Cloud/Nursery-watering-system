defmodule NurseryHub.Heartbeat do
  @moduledoc """
  Sends a daily system-alive email at a configured UTC hour.

  If the email stops arriving, the system is dead — app crashed, server off,
  or email delivery broken. The absence of the heartbeat IS the alert.

  Also surfaces current zone health in the email body: total zones, offline
  count, zones with active alerts.
  """

  use GenServer
  require Logger

  alias NurseryHub.{ZoneSupervisor, ZoneServer, Alerting}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    ms = ms_until_next_heartbeat()
    Logger.info("[Heartbeat] Next heartbeat in #{round(ms / 3_600_000)}h #{round(rem(round(ms / 60_000), 60))}m")
    Process.send_after(self(), :send_heartbeat, ms)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:send_heartbeat, state) do
    summary = build_summary()
    Alerting.heartbeat(summary)
    Process.send_after(self(), :send_heartbeat, :timer.hours(24))
    {:noreply, state}
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp ms_until_next_heartbeat do
    hour = Application.get_env(:nursery_hub, :heartbeat_hour, 8)
    now  = DateTime.utc_now()

    target_today = %{now | hour: hour, minute: 0, second: 0, microsecond: {0, 0}}

    target =
      if DateTime.compare(target_today, now) == :gt do
        target_today
      else
        DateTime.add(target_today, 86_400, :second)
      end

    DateTime.diff(target, now, :millisecond)
  end

  defp build_summary do
    now             = DateTime.utc_now()
    timeout_minutes = Application.get_env(:nursery_hub, :zone_timeout_minutes, 30)

    zones =
      ZoneSupervisor.all_zones()
      |> Enum.flat_map(fn {site_id, zone_id} ->
        case ZoneServer.state(site_id, zone_id) do
          {:error, _} -> []
          state       -> [state]
        end
      end)

    offline =
      Enum.filter(zones, fn z ->
        z.last_seen != nil and
        DateTime.diff(now, z.last_seen, :minute) >= timeout_minutes
      end)

    alerting = Enum.filter(zones, fn z -> z.alerts != [] end)

    %{
      total:         length(zones),
      offline_count: length(offline),
      alert_count:   length(alerting),
      offline_zones: Enum.map(offline, &"#{&1.site_id}/#{&1.zone_id}"),
      alert_zones:   Enum.map(alerting, fn z ->
        alert_names = Enum.map_join(z.alerts, ", ", &to_string/1)
        "#{z.site_id}/#{z.zone_id} (#{alert_names})"
      end),
      sent_at: now
    }
  end
end
