defmodule NurseryHubWeb.DashboardLive do
  @moduledoc """
  Main dashboard — shows all sites and zones in real time.

  Updates automatically every time an ESP32 sends a reading.
  No page refresh needed — Phoenix LiveView pushes updates via WebSocket.
  """

  use Phoenix.LiveView
  alias NurseryHub.{ZoneSupervisor, ZoneServer, SensorReading}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to live zone updates — dashboard re-renders on each new reading
      Phoenix.PubSub.subscribe(NurseryHub.PubSub, "zones:updates")
    end

    {:ok, assign(socket, zones: load_zones(), last_refresh: DateTime.utc_now())}
  end

  @impl true
  def handle_info({:zone_update, updated_zone}, socket) do
    # A zone sent new data — update just that zone in our map
    zones = Map.put(socket.assigns.zones, zone_key(updated_zone), updated_zone)
    {:noreply, assign(socket, zones: zones, last_refresh: DateTime.utc_now())}
  end

  @impl true
  def handle_event("water_now", %{"site" => site, "zone" => zone}, socket) do
    ZoneServer.send_command(site, zone, %{cmd: "water", duration: 15})
    {:noreply, socket}
  end

  @impl true
  def handle_event("stop_water", %{"site" => site, "zone" => zone}, socket) do
    ZoneServer.send_command(site, zone, %{cmd: "stop"})
    {:noreply, socket}
  end

  # ── Rendering ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    sites = assigns.zones |> Map.values() |> Enum.group_by(& &1.site_id)

    assigns = assign(assigns, sites: sites)

    ~H"""
    <div class="p-6">

      <%!-- Header --%>
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-2xl font-bold text-white">NurseryHub</h1>
          <p class="text-gray-400 text-sm mt-1">
            <%= map_size(@zones) %> active zones across <%= map_size(@sites) %> sites
          </p>
        </div>
        <div class="text-right">
          <div class="text-xs text-gray-500">Last update</div>
          <div class="text-sm text-gray-300"><%= format_time(@last_refresh) %></div>
        </div>
      </div>

      <%!-- Alert bar — show any zones with active alerts --%>
      <%= if zones_with_alerts(@zones) != [] do %>
        <div class="bg-red-900/50 border border-red-700 rounded-lg p-4 mb-6">
          <div class="font-semibold text-red-300 mb-2">Active Alerts</div>
          <%= for zone <- zones_with_alerts(@zones) do %>
            <div class="text-sm text-red-200">
              <%= zone.site_id %> / <%= zone.zone_id %> —
              <%= Enum.join(Enum.map(zone.alerts, &alert_label/1), ", ") %>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Sites --%>
      <%= for {site_id, zones} <- Enum.sort(@sites) do %>
        <div class="mb-8">
          <div class="flex items-center gap-3 mb-4">
            <h2 class="text-lg font-semibold text-white"><%= site_id %></h2>
            <span class={"text-xs px-2 py-0.5 rounded-full " <> site_status_class(zones)}>
              <%= site_status_label(zones) %>
            </span>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
            <%= for zone <- Enum.sort_by(zones, & &1.zone_id) do %>
              <.zone_card zone={zone} />
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- Empty state --%>
      <%= if map_size(@zones) == 0 do %>
        <div class="text-center py-24 text-gray-500">
          <div class="text-4xl mb-4">📡</div>
          <div class="text-lg">Waiting for zones to connect...</div>
          <div class="text-sm mt-2">ESP32s will appear here as they send data</div>
        </div>
      <% end %>

    </div>
    """
  end

  # ── Zone card component ──────────────────────────────────────────────────

  defp zone_card(assigns) do
    ~H"""
    <div class={"rounded-xl border p-4 " <> zone_card_class(@zone)}>

      <%!-- Zone header --%>
      <div class="flex items-center justify-between mb-3">
        <div>
          <div class="font-semibold text-white"><%= @zone.zone_id %></div>
          <div class={"text-xs mt-0.5 " <> mode_text_class(@zone.mode)}>
            <%= mode_label(@zone.mode) %>
          </div>
        </div>
        <div class={"w-3 h-3 rounded-full " <> status_dot_class(@zone)}></div>
      </div>

      <%!-- Readings --%>
      <div class="space-y-2 text-sm mb-4">
        <.reading icon="💧" label="Moisture" value={@zone.moisture} unit="%" bar={true} />
        <.reading icon="🌡" label="Air temp"  value={@zone.air_temp}  unit="°C" />
        <.reading icon="💨" label="VPD"       value={format_vpd(@zone.vpd)} unit="kPa" />
        <.reading icon="💡" label="Light"     value={format_lux(@zone.lux)} unit="" />
      </div>

      <%!-- Watering indicator --%>
      <%= if @zone.watering do %>
        <div class="text-xs text-blue-300 bg-blue-900/40 rounded px-2 py-1 mb-3 text-center">
          💦 Dripping now
        </div>
      <% end %>

      <%!-- Last seen --%>
      <div class="text-xs text-gray-500 mb-3">
        Last seen: <%= time_ago(@zone.last_seen) %>
      </div>

      <%!-- Controls --%>
      <div class="flex gap-2">
        <button
          phx-click="water_now"
          phx-value-site={@zone.site_id}
          phx-value-zone={@zone.zone_id}
          class="flex-1 text-xs bg-blue-700 hover:bg-blue-600 text-white rounded px-2 py-1.5">
          Water now
        </button>
        <button
          phx-click="stop_water"
          phx-value-site={@zone.site_id}
          phx-value-zone={@zone.zone_id}
          class="flex-1 text-xs bg-gray-700 hover:bg-gray-600 text-white rounded px-2 py-1.5">
          Stop
        </button>
        <a
          href={"/zone/#{@zone.site_id}/#{@zone.zone_id}"}
          class="flex-1 text-xs bg-gray-800 hover:bg-gray-700 text-gray-300 rounded px-2 py-1.5 text-center">
          History
        </a>
      </div>
    </div>
    """
  end

  defp reading(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <span class="text-gray-400"><%= @icon %> <%= @label %></span>
      <div class="flex items-center gap-2">
        <%= if Map.get(assigns, :bar) && is_integer(@value) do %>
          <div class="w-16 bg-gray-700 rounded-full h-1.5">
            <div
              class={"h-1.5 rounded-full " <> moisture_bar_class(@value)}
              style={"width: #{@value}%"}>
            </div>
          </div>
        <% end %>
        <span class="text-white font-medium">
          <%= if is_nil(@value), do: "--", else: "#{@value}#{@unit}" %>
        </span>
      </div>
    </div>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp load_zones do
    ZoneSupervisor.all_zones()
    |> Enum.reduce(%{}, fn {site_id, zone_id}, acc ->
      case ZoneServer.state(site_id, zone_id) do
        state when is_struct(state) ->
          Map.put(acc, zone_key(state), state)
        _ ->
          acc
      end
    end)
  end

  defp zone_key(zone), do: {zone.site_id, zone.zone_id}

  defp zones_with_alerts(zones) do
    zones |> Map.values() |> Enum.filter(&(&1.alerts != []))
  end

  defp zone_card_class(zone) do
    cond do
      :offline in zone.alerts     -> "bg-red-950/60 border-red-800"
      zone.alerts != []           -> "bg-yellow-950/60 border-yellow-700"
      zone.mode in ["no_vpd", "no_moisture"] -> "bg-yellow-950/40 border-yellow-800/50"
      true                        -> "bg-gray-900 border-gray-700"
    end
  end

  defp status_dot_class(zone) do
    cond do
      :offline in zone.alerts -> "bg-red-500 animate-pulse"
      zone.alerts != []       -> "bg-yellow-400 animate-pulse"
      zone.watering           -> "bg-blue-400 animate-pulse"
      true                    -> "bg-green-500"
    end
  end

  defp mode_text_class(mode) do
    case mode do
      "normal"      -> "text-green-400"
      "local"       -> "text-blue-400"
      "no_vpd"      -> "text-yellow-400"
      "no_moisture" -> "text-orange-400"
      _             -> "text-gray-400"
    end
  end

  defp mode_label(mode) do
    case mode do
      "normal"      -> "● Normal"
      "local"       -> "● Local mode"
      "no_vpd"      -> "⚠ No VPD sensors"
      "no_moisture" -> "⚠ No moisture sensor"
      _             -> "○ Unknown"
    end
  end

  defp moisture_bar_class(pct) when pct < 20, do: "bg-red-500"
  defp moisture_bar_class(pct) when pct < 40, do: "bg-yellow-400"
  defp moisture_bar_class(pct) when pct < 70, do: "bg-green-500"
  defp moisture_bar_class(_),                 do: "bg-blue-400"

  defp site_status_label(zones) do
    offline = Enum.count(zones, &(:offline in &1.alerts))
    alerts  = Enum.count(zones, &(&1.alerts != []))
    cond do
      offline > 0 -> "#{offline} offline"
      alerts  > 0 -> "#{alerts} alert"
      true        -> "All online"
    end
  end

  defp site_status_class(zones) do
    offline = Enum.count(zones, &(:offline in &1.alerts))
    alerts  = Enum.count(zones, &(&1.alerts != []))
    cond do
      offline > 0 -> "bg-red-900/50 text-red-300"
      alerts  > 0 -> "bg-yellow-900/50 text-yellow-300"
      true        -> "bg-green-900/50 text-green-300"
    end
  end

  defp alert_label(:offline),      do: "Offline"
  defp alert_label(:valve_stuck),  do: "Valve stuck open"
  defp alert_label(:critical_dry), do: "Critically dry"
  defp alert_label(other),         do: to_string(other)

  defp format_vpd(nil), do: nil
  defp format_vpd(v),   do: Float.round(v, 2)

  defp format_lux(nil), do: nil
  defp format_lux(v) when v >= 1000, do: "#{round(v / 1000)}k"
  defp format_lux(v),   do: round(v)

  defp format_time(dt), do: Calendar.strftime(dt, "%H:%M:%S")

  defp time_ago(nil), do: "never"
  defp time_ago(dt) do
    secs = DateTime.diff(DateTime.utc_now(), dt, :second)
    cond do
      secs < 60    -> "#{secs}s ago"
      secs < 3600  -> "#{div(secs, 60)}m ago"
      true         -> "#{div(secs, 3600)}h ago"
    end
  end
end
