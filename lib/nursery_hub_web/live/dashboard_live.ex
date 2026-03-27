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
      zones:               load_zones(),
      last_refresh:        DateTime.utc_now(),
      filter_site:         "all",
      filter_zone:         "",
      filter_status:       "all",
      filter_mode:         "all",
      filter_moisture_min: "",
      filter_moisture_max: "",
      filter_temp_min:     "",
      filter_temp_max:     "",
      filter_vpd_min:      "",
      filter_vpd_max:      "",
      filter_lux_min:      "",
      filter_lux_max:      ""
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
      filter_site:         params["site"]         || "all",
      filter_zone:         params["zone"]         || "",
      filter_status:       params["status"]       || "all",
      filter_mode:         params["mode"]         || "all",
      filter_moisture_min: params["moisture_min"] || "",
      filter_moisture_max: params["moisture_max"] || "",
      filter_temp_min:     params["temp_min"]     || "",
      filter_temp_max:     params["temp_max"]     || "",
      filter_vpd_min:      params["vpd_min"]      || "",
      filter_vpd_max:      params["vpd_max"]      || "",
      filter_lux_min:      params["lux_min"]      || "",
      filter_lux_max:      params["lux_max"]      || ""
    )}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply, assign(socket,
      filter_site:         "all",
      filter_zone:         "",
      filter_status:       "all",
      filter_mode:         "all",
      filter_moisture_min: "",
      filter_moisture_max: "",
      filter_temp_min:     "",
      filter_temp_max:     "",
      filter_vpd_min:      "",
      filter_vpd_max:      "",
      filter_lux_min:      "",
      filter_lux_max:      ""
    )}
  end

  # ── Rendering ──────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    all_zones   = Map.values(assigns.zones)
    sites       = all_zones |> Enum.map(& &1.site_id) |> Enum.uniq() |> Enum.sort()
    filtered    = apply_filters(all_zones, assigns)
    offline_ct  = Enum.count(all_zones, &(:offline in &1.alerts))
    alert_zones = Enum.filter(all_zones, &(&1.alerts != []))

    assigns = assign(assigns,
      sites:       sites,
      filtered:    filtered,
      total:       length(all_zones),
      offline_ct:  offline_ct,
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
          <a href="/topology"
            class="text-xs bg-gray-800 hover:bg-gray-700 text-gray-400 px-3 py-2 rounded-lg">
            Topology
          </a>
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
      <form phx-change="filter" class="bg-gray-900 border border-gray-700 rounded-lg p-4 mb-4 space-y-3">

        <%!-- Row 1: categorical filters --%>
        <div class="flex flex-wrap items-center gap-3">
          <div class="flex items-center gap-1.5">
            <label class="text-xs text-gray-500 w-8">Site</label>
            <select name="site"
              class="bg-gray-800 border border-gray-600 text-gray-200 text-sm rounded px-2 py-1">
              <option value="all" selected={@filter_site == "all"}>All</option>
              <%= for site <- @sites do %>
                <option value={site} selected={@filter_site == site}><%= site %></option>
              <% end %>
            </select>
          </div>
          <div class="flex items-center gap-1.5">
            <label class="text-xs text-gray-500 w-8">Zone</label>
            <input type="text" name="zone" value={@filter_zone} placeholder="search…"
              class="bg-gray-800 border border-gray-600 text-gray-200 text-sm rounded px-2 py-1 w-28" />
          </div>
          <div class="flex items-center gap-1.5">
            <label class="text-xs text-gray-500 w-10">Status</label>
            <select name="status"
              class="bg-gray-800 border border-gray-600 text-gray-200 text-sm rounded px-2 py-1">
              <option value="all"      selected={@filter_status == "all"}>All</option>
              <option value="online"   selected={@filter_status == "online"}>Online</option>
              <option value="offline"  selected={@filter_status == "offline"}>Offline</option>
              <option value="watering" selected={@filter_status == "watering"}>Watering</option>
              <option value="alert"    selected={@filter_status == "alert"}>Alert</option>
            </select>
          </div>
          <div class="flex items-center gap-1.5">
            <label class="text-xs text-gray-500 w-8">Mode</label>
            <select name="mode"
              class="bg-gray-800 border border-gray-600 text-gray-200 text-sm rounded px-2 py-1">
              <option value="all"         selected={@filter_mode == "all"}>All</option>
              <option value="normal"      selected={@filter_mode == "normal"}>Normal</option>
              <option value="local"       selected={@filter_mode == "local"}>Local</option>
              <option value="no_vpd"      selected={@filter_mode == "no_vpd"}>No VPD</option>
              <option value="no_moisture" selected={@filter_mode == "no_moisture"}>No moisture</option>
            </select>
          </div>
        </div>

        <%!-- Row 2: numeric range filters --%>
        <div class="flex flex-wrap items-center gap-4">
          <div class="flex items-center gap-1.5">
            <label class="text-xs text-gray-500">Moisture %</label>
            <input type="number" name="moisture_min" value={@filter_moisture_min} placeholder="min"
              min="0" max="100"
              class="bg-gray-800 border border-gray-600 text-gray-200 text-xs rounded px-2 py-1 w-16" />
            <span class="text-gray-600 text-xs">–</span>
            <input type="number" name="moisture_max" value={@filter_moisture_max} placeholder="max"
              min="0" max="100"
              class="bg-gray-800 border border-gray-600 text-gray-200 text-xs rounded px-2 py-1 w-16" />
          </div>
          <div class="flex items-center gap-1.5">
            <label class="text-xs text-gray-500">Temp °C</label>
            <input type="number" name="temp_min" value={@filter_temp_min} placeholder="min"
              class="bg-gray-800 border border-gray-600 text-gray-200 text-xs rounded px-2 py-1 w-16" />
            <span class="text-gray-600 text-xs">–</span>
            <input type="number" name="temp_max" value={@filter_temp_max} placeholder="max"
              class="bg-gray-800 border border-gray-600 text-gray-200 text-xs rounded px-2 py-1 w-16" />
          </div>
          <div class="flex items-center gap-1.5">
            <label class="text-xs text-gray-500">VPD kPa</label>
            <input type="number" name="vpd_min" value={@filter_vpd_min} placeholder="min"
              step="0.01"
              class="bg-gray-800 border border-gray-600 text-gray-200 text-xs rounded px-2 py-1 w-16" />
            <span class="text-gray-600 text-xs">–</span>
            <input type="number" name="vpd_max" value={@filter_vpd_max} placeholder="max"
              step="0.01"
              class="bg-gray-800 border border-gray-600 text-gray-200 text-xs rounded px-2 py-1 w-16" />
          </div>
          <div class="flex items-center gap-1.5">
            <label class="text-xs text-gray-500">Lux</label>
            <input type="number" name="lux_min" value={@filter_lux_min} placeholder="min"
              class="bg-gray-800 border border-gray-600 text-gray-200 text-xs rounded px-2 py-1 w-20" />
            <span class="text-gray-600 text-xs">–</span>
            <input type="number" name="lux_max" value={@filter_lux_max} placeholder="max"
              class="bg-gray-800 border border-gray-600 text-gray-200 text-xs rounded px-2 py-1 w-20" />
          </div>
        </div>

        <%!-- Filter footer: count + clear + download --%>
        <div class="flex items-center justify-between pt-1">
          <span class="text-xs text-gray-500">
            Showing <%= length(@filtered) %> of <%= @total %> zones
          </span>
          <div class="flex items-center gap-2">
            <button type="button" phx-click="clear_filters"
              class="text-xs text-gray-400 hover:text-gray-200 px-2 py-1 rounded border border-gray-700 hover:border-gray-500">
              Clear filters
            </button>
            <a href={csv_url(assigns)}
              class="text-xs bg-green-800 hover:bg-green-700 text-green-200 px-3 py-1 rounded">
              ↓ Download CSV
            </a>
          </div>
        </div>
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
                <th class="text-left pb-2 pr-4 font-normal">Status</th>
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

      <%!-- Status text --%>
      <td class="py-3 pr-4">
        <span class={"text-xs font-medium " <> status_text_class(@zone)}>
          <%= zone_status(@zone) %>
        </span>
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
    db_zones =
      SensorReading.latest_per_zone()
      |> Enum.reduce(%{}, fn reading, acc ->
        zone = zone_from_reading(reading)
        Map.put(acc, {zone.site_id, zone.zone_id}, zone)
      end)

    ZoneSupervisor.all_zones()
    |> Enum.reduce(db_zones, fn {site_id, zone_id}, acc ->
      case ZoneServer.state(site_id, zone_id) do
        state when is_struct(state) -> Map.put(acc, {site_id, zone_id}, state)
        _                           -> acc
      end
    end)
  end

  defp zone_from_reading(r) do
    %ZoneServer{
      site_id:   r.site_id,
      zone_id:   r.zone_id,
      node_id:   r.node_id,
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

  defp apply_filters(zones, assigns) do
    zones
    |> Enum.filter(fn zone ->
      site_ok     = assigns.filter_site == "all" or zone.site_id == assigns.filter_site
      zone_ok     = assigns.filter_zone == "" or String.contains?(zone.zone_id, assigns.filter_zone)
      status_ok   = status_matches?(zone, assigns.filter_status)
      mode_ok     = assigns.filter_mode == "all" or zone.mode == assigns.filter_mode
      moisture_ok = range_matches?(zone.moisture,  assigns.filter_moisture_min, assigns.filter_moisture_max)
      temp_ok     = range_matches?(zone.air_temp,  assigns.filter_temp_min,     assigns.filter_temp_max)
      vpd_ok      = range_matches?(zone.vpd,       assigns.filter_vpd_min,      assigns.filter_vpd_max)
      lux_ok      = range_matches?(zone.lux,       assigns.filter_lux_min,      assigns.filter_lux_max)

      site_ok and zone_ok and status_ok and mode_ok and moisture_ok and temp_ok and vpd_ok and lux_ok
    end)
    |> Enum.sort_by(&{&1.site_id, &1.zone_id})
  end

  defp status_matches?(zone, filter) do
    case filter do
      "all"      -> true
      "online"   -> :offline not in zone.alerts and not zone.watering
      "offline"  -> :offline in zone.alerts
      "watering" -> zone.watering
      "alert"    -> zone.alerts != [] and :offline not in zone.alerts
      _          -> true
    end
  end

  defp range_matches?(_val, "", ""), do: true
  defp range_matches?(nil, _min, _max), do: false
  defp range_matches?(val, min_str, max_str) do
    min_ok = min_str == "" or val >= parse_number(min_str)
    max_ok = max_str == "" or val <= parse_number(max_str)
    min_ok and max_ok
  end

  defp parse_number(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  # ── CSV URL builder ────────────────────────────────────────────────────────

  defp csv_url(assigns) do
    params =
      [
        {"site",         assigns.filter_site},
        {"zone",         assigns.filter_zone},
        {"status",       assigns.filter_status},
        {"mode",         assigns.filter_mode},
        {"moisture_min", assigns.filter_moisture_min},
        {"moisture_max", assigns.filter_moisture_max},
        {"temp_min",     assigns.filter_temp_min},
        {"temp_max",     assigns.filter_temp_max},
        {"vpd_min",      assigns.filter_vpd_min},
        {"vpd_max",      assigns.filter_vpd_max},
        {"lux_min",      assigns.filter_lux_min},
        {"lux_max",      assigns.filter_lux_max}
      ]
      |> Enum.reject(fn {_, v} -> v == "" or v == "all" end)
      |> URI.encode_query()

    if params == "", do: "/csv/dashboard", else: "/csv/dashboard?#{params}"
  end

  # ── Styling helpers ────────────────────────────────────────────────────────

  defp zone_status(zone) do
    cond do
      :offline in zone.alerts -> "offline"
      zone.watering            -> "watering"
      zone.alerts != []        -> "alert"
      true                     -> "online"
    end
  end

  defp status_text_class(zone) do
    cond do
      :offline in zone.alerts -> "text-red-400"
      zone.watering            -> "text-blue-400"
      zone.alerts != []        -> "text-yellow-400"
      true                     -> "text-green-400"
    end
  end

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
