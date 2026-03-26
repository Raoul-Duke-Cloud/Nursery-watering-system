defmodule NurseryHubWeb.DashboardLive do
  @moduledoc """
  Main dashboard — shows all sites and zones in a filterable table.

  Zones are persistent: once a zone appears in the database it remains
  visible even after a server restart or ESP32 going offline.  The live
  ZoneServer state is overlaid on top of the DB snapshot, so the row
  transitions seamlessly between offline (DB stub) and live data.
  """

  use Phoenix.LiveView
  alias NurseryHub.{ZoneSupervisor, ZoneServer, SensorReading}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NurseryHub.PubSub, "zones:updates")
    end

    {:ok, assign(socket,
      zones:         load_zones(),
      last_refresh:  DateTime.utc_now(),
      filter_site:   "all",
      filter_status: "all"
    )}
  end

  @impl true
  def handle_info({:zone_update, updated_zone}, socket) do
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

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, assign(socket,
      filter_site:   params["site"]   || "all",
      filter_status: params["status"] || "all"
    )}
  end

  # ── Rendering ──────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    all_zones   = Map.values(assigns.zones)
    sites       = all_zones |> Enum.map(& &1.site_id) |> Enum.uniq() |> Enum.sort()
    filtered    = apply_filters(all_zones, assigns.filter_site, assigns.filter_status)
    offline_ct  = Enum.count(all_zones, &(:offline in &1.alerts))
    alert_zones = Enum.filter(all_zones, &(&1.alerts != []))

    assigns = assign(assigns,
      sites:      sites,
      filtered:   filtered,
      total:      length(all_zones),
      offline_ct: offline_ct,
      alert_zones: alert_zones
    )

    ~H"""
    <div class="p-6">

      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold text-white">NurseryHub</h1>
          <p class="text-gray-400 text-sm mt-1">
            <%= @total %> zones
            <%= if @offline_ct > 0 do %>
              &middot; <span class="text-red-400"><%= @offline_ct %> offline</span>
            <% end %>
          </p>
        </div>
        <div class="flex items-center gap-4">
          <div class="text-right">
            <div class="text-xs text-gray-500">Last update</div>
            <div class="text-sm text-gray-300"><%= format_time(@last_refresh) %></div>
          </div>
          <a href="/logs"
            class="text-xs bg-gray-800 hover:bg-gray-700 text-gray-400 px-3 py-2 rounded-lg">
            Alert Log
          </a>
          <a href="/settings"
            class="text-xs bg-gray-800 hover:bg-gray-700 text-gray-400 px-3 py-2 rounded-lg">
            ⚙ Settings
          </a>
        </div>
      </div>

      <%!-- Alert bar --%>
      <%= if @alert_zones != [] do %>
        <div class="bg-red-900/50 border border-red-700 rounded-lg p-4 mb-6">
          <div class="font-semibold text-red-300 mb-2">Active Alerts</div>
          <%= for zone <- @alert_zones do %>
            <div class="text-sm text-red-200">
              <%= zone.site_id %> / <%= zone.zone_id %> —
              <%= zone.alerts |> Enum.map(&alert_label/1) |> Enum.join(", ") %>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Filters --%>
      <form phx-change="filter" class="flex flex-wrap items-center gap-4 mb-4">
        <div class="flex items-center gap-2">
          <label class="text-xs text-gray-500">Site</label>
          <select name="site"
            class="bg-gray-800 border border-gray-600 text-gray-200 text-sm rounded px-2 py-1.5">
            <option value="all" selected={@filter_site == "all"}>All sites</option>
            <%= for site <- @sites do %>
              <option value={site} selected={@filter_site == site}><%= site %></option>
            <% end %>
          </select>
        </div>
        <div class="flex items-center gap-2">
          <label class="text-xs text-gray-500">Status</label>
          <select name="status"
            class="bg-gray-800 border border-gray-600 text-gray-200 text-sm rounded px-2 py-1.5">
            <option value="all"     selected={@filter_status == "all"}>All</option>
            <option value="online"  selected={@filter_status == "online"}>Online</option>
            <option value="offline" selected={@filter_status == "offline"}>Offline</option>
            <option value="alerts"  selected={@filter_status == "alerts"}>Alerts</option>
          </select>
        </div>
        <%= if length(@filtered) != @total do %>
          <span class="text-xs text-gray-500">
            Showing <%= length(@filtered) %> of <%= @total %>
          </span>
        <% end %>
      </form>

      <%!-- Empty state --%>
      <%= if @total == 0 do %>
        <div class="text-center py-24 text-gray-500">
          <div class="text-4xl mb-4">📡</div>
          <div class="text-lg">Waiting for zones to connect...</div>
          <div class="text-sm mt-2">ESP32s will appear here as they send data</div>
        </div>

      <%!-- Zone table --%>
      <% else %>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="text-xs text-gray-500 border-b border-gray-700 uppercase tracking-wide">
                <th class="text-left pb-2 pr-3 font-normal"></th>
                <th class="text-left pb-2 pr-4 font-normal">Site</th>
                <th class="text-left pb-2 pr-4 font-normal">Zone</th>
                <th class="text-left pb-2 pr-6 font-normal">Moisture</th>
                <th class="text-left pb-2 pr-4 font-normal">Air temp</th>
                <th class="text-left pb-2 pr-4 font-normal">VPD</th>
                <th class="text-left pb-2 pr-4 font-normal">Light</th>
                <th class="text-left pb-2 pr-4 font-normal">Mode</th>
                <th class="text-left pb-2 pr-4 font-normal">Last seen</th>
                <th class="text-left pb-2 font-normal">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for zone <- @filtered do %>
                <.zone_row zone={zone} />
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>

    </div>
    """
  end

  # ── Table row ──────────────────────────────────────────────────────────────

  defp zone_row(assigns) do
    offline = :offline in assigns.zone.alerts
    assigns = assign(assigns, offline: offline)

    ~H"""
    <tr class={"border-b border-gray-800 transition-colors " <>
                if(@offline, do: "opacity-50", else: "hover:bg-gray-900/40")}>

      <%!-- Status dot --%>
      <td class="py-3 pr-3">
        <div class="flex items-center gap-1.5">
          <div class={"w-2.5 h-2.5 rounded-full flex-shrink-0 " <> status_dot_class(@zone)}></div>
          <%= if @zone.watering do %>
            <span class="text-blue-400 text-xs">💦</span>
          <% end %>
        </div>
      </td>

      <%!-- Site --%>
      <td class="py-3 pr-4 text-gray-400"><%= @zone.site_id %></td>

      <%!-- Zone --%>
      <td class="py-3 pr-4 text-white font-medium"><%= @zone.zone_id %></td>

      <%!-- Moisture --%>
      <td class="py-3 pr-6">
        <%= if is_integer(@zone.moisture) do %>
          <div class="flex items-center gap-2">
            <div class="w-14 bg-gray-700 rounded-full h-1.5 flex-shrink-0">
              <div class={"h-1.5 rounded-full " <> moisture_bar_class(@zone.moisture)}
                   style={"width: #{@zone.moisture}%"}></div>
            </div>
            <span class="text-gray-200"><%= @zone.moisture %>%</span>
          </div>
        <% else %>
          <span class="text-gray-600">—</span>
        <% end %>
      </td>

      <%!-- Air temp --%>
      <td class="py-3 pr-4 text-gray-200">
        <%= if @zone.air_temp, do: "#{@zone.air_temp}°C", else: "—" %>
      </td>

      <%!-- VPD --%>
      <td class="py-3 pr-4 text-gray-200">
        <%= if @zone.vpd, do: "#{format_vpd(@zone.vpd)} kPa", else: "—" %>
      </td>

      <%!-- Light --%>
      <td class="py-3 pr-4 text-gray-200">
        <%= if @zone.lux, do: format_lux(@zone.lux), else: "—" %>
      </td>

      <%!-- Mode --%>
      <td class="py-3 pr-4">
        <span class={"text-xs " <> mode_text_class(@zone.mode)}>
          <%= mode_label(@zone.mode) %>
        </span>
      </td>

      <%!-- Last seen --%>
      <td class="py-3 pr-4 text-gray-500 text-xs whitespace-nowrap">
        <%= time_ago(@zone.last_seen) %>
      </td>

      <%!-- Actions --%>
      <td class="py-3">
        <div class="flex gap-1">
          <button phx-click="water_now"
            phx-value-site={@zone.site_id} phx-value-zone={@zone.zone_id}
            class="text-xs bg-blue-700 hover:bg-blue-600 text-white rounded px-2.5 py-1">
            Water
          </button>
          <button phx-click="stop_water"
            phx-value-site={@zone.site_id} phx-value-zone={@zone.zone_id}
            class="text-xs bg-gray-700 hover:bg-gray-600 text-white rounded px-2.5 py-1">
            Stop
          </button>
          <a href={"/zone/#{@zone.site_id}/#{@zone.zone_id}"}
            class="text-xs bg-gray-800 hover:bg-gray-700 text-gray-300 rounded px-2.5 py-1">
            History
          </a>
        </div>
      </td>
    </tr>
    """
  end

  # ── Data loading ───────────────────────────────────────────────────────────

  defp load_zones do
    # Seed from DB — every zone ever seen starts as offline
    db_zones =
      SensorReading.latest_per_zone()
      |> Enum.reduce(%{}, fn reading, acc ->
        zone = zone_from_reading(reading)
        Map.put(acc, {zone.site_id, zone.zone_id}, zone)
      end)

    # Overlay with live ZoneServer state — clears the :offline stub for active zones
    ZoneSupervisor.all_zones()
    |> Enum.reduce(db_zones, fn {site_id, zone_id}, acc ->
      case ZoneServer.state(site_id, zone_id) do
        state when is_struct(state) -> Map.put(acc, {site_id, zone_id}, state)
        _                           -> acc
      end
    end)
  end

  # Build a ZoneServer-shaped struct from a DB reading so the table renders uniformly
  defp zone_from_reading(r) do
    %ZoneServer{
      site_id:   r.site_id,
      zone_id:   r.zone_id,
      last_seen: r.inserted_at,
      moisture:  r.moisture,
      lux:       r.lux,
      leaf_temp: r.leaf_temp,
      air_temp:  r.air_temp,
      humidity:  r.humidity,
      vpd:       r.vpd,
      watering:  false,
      mode:      r.mode || "unknown",
      sensor_ok: %{},
      alerts:    [:offline]
    }
  end

  defp zone_key(zone), do: {zone.site_id, zone.zone_id}

  defp apply_filters(zones, site_filter, status_filter) do
    zones
    |> Enum.filter(fn zone ->
      site_ok = site_filter == "all" or zone.site_id == site_filter

      status_ok = case status_filter do
        "all"     -> true
        "online"  -> :offline not in zone.alerts
        "offline" -> :offline in zone.alerts
        "alerts"  -> zone.alerts != [] and :offline not in zone.alerts
        _         -> true
      end

      site_ok and status_ok
    end)
    |> Enum.sort_by(&{&1.site_id, &1.zone_id})
  end

  # ── Styling helpers ────────────────────────────────────────────────────────

  defp status_dot_class(zone) do
    cond do
      :offline in zone.alerts -> "bg-red-500"
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
      "normal"      -> "Normal"
      "local"       -> "Local mode"
      "no_vpd"      -> "No VPD"
      "no_moisture" -> "No moisture"
      _             -> "Unknown"
    end
  end

  defp moisture_bar_class(pct) when pct < 20, do: "bg-red-500"
  defp moisture_bar_class(pct) when pct < 40, do: "bg-yellow-400"
  defp moisture_bar_class(pct) when pct < 70, do: "bg-green-500"
  defp moisture_bar_class(_),                 do: "bg-blue-400"

  defp alert_label(:offline),       do: "Offline"
  defp alert_label(:valve_stuck),   do: "Valve stuck open"
  defp alert_label(:critical_dry),  do: "Critically dry"
  defp alert_label(:sensor_fault),  do: "Sensor fault"
  defp alert_label(other),          do: to_string(other)

  defp format_vpd(nil), do: nil
  defp format_vpd(v),   do: Float.round(v, 2)

  defp format_lux(nil), do: nil
  defp format_lux(v) when v >= 1000, do: "#{round(v / 1000)}k lux"
  defp format_lux(v),                do: "#{round(v)} lux"

  defp format_time(dt), do: Calendar.strftime(dt, "%H:%M:%S")

  defp time_ago(nil), do: "never"
  defp time_ago(dt) do
    secs = DateTime.diff(DateTime.utc_now(), dt, :second)
    cond do
      secs < 60   -> "#{secs}s ago"
      secs < 3600 -> "#{div(secs, 60)}m ago"
      true        -> "#{div(secs, 3600)}h ago"
    end
  end
end
