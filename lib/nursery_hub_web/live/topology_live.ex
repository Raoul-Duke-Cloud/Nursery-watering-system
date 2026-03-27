defmodule NurseryHubWeb.TopologyLive do
  @moduledoc """
  Topology page — shows the full equipment hierarchy as a visual map.

  Central server → sites → zones. Each element is colour-coded by status.
  Click any zone to go to its detail page. Use this to locate the physical
  source of a fault: find the zone on screen, read the node label, go to
  the field and positively ID the hardware by its label.

  Live updates via PubSub — same as the main dashboard.
  """

  use Phoenix.LiveView
  alias NurseryHub.{ZoneSupervisor, ZoneServer, SensorReading, DataSync}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NurseryHub.PubSub, "zones:updates")
    end

    {:ok, assign(socket,
      zones:        load_zones(),
      last_refresh: DateTime.utc_now()
    )}
  end

  @impl true
  def handle_info({:zone_update, updated_zone}, socket) do
    zones = Map.put(socket.assigns.zones, zone_key(updated_zone), updated_zone)
    {:noreply, assign(socket, zones: zones, last_refresh: DateTime.utc_now())}
  end

  # ── Rendering ──────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    all_zones = Map.values(assigns.zones)

    # Group: site_id -> node_id -> [zones]
    # Zones with no node_id yet (old data or no firmware update) go under "unknown"
    sites =
      all_zones
      |> Enum.group_by(& &1.site_id)
      |> Enum.sort_by(fn {site_id, _} -> site_id end)
      |> Enum.map(fn {site_id, zones} ->
        nodes =
          zones
          |> Enum.group_by(&(&1.node_id || "unknown"))
          |> Enum.sort_by(fn {node_id, _} -> node_id end)
        {site_id, nodes}
      end)

    total    = length(all_zones)
    n_ok     = Enum.count(all_zones, &(zone_status(&1) == :online))
    n_alert  = Enum.count(all_zones, &(zone_status(&1) == :alert))
    n_off    = Enum.count(all_zones, &(zone_status(&1) == :offline))

    wan_up = datasync_wan_up?()

    assigns = assign(assigns,
      sites:   sites,
      total:   total,
      n_ok:    n_ok,
      n_alert: n_alert,
      n_off:   n_off,
      wan_up:  wan_up
    )

    ~H"""
    <div class="p-6 max-w-screen-xl mx-auto">

      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold text-white">Topology</h1>
          <p class="text-gray-400 text-sm mt-1">
            <%= @total %> zones &middot;
            <span class="text-green-400"><%= @n_ok %> online</span>
            <%= if @n_alert > 0 do %>
              &middot; <span class="text-yellow-400"><%= @n_alert %> alert</span>
            <% end %>
            <%= if @n_off > 0 do %>
              &middot; <span class="text-red-400"><%= @n_off %> offline</span>
            <% end %>
          </p>
        </div>
        <div class="flex items-center gap-3">
          <div class="text-right">
            <div class="text-xs text-gray-500">Updated</div>
            <div class="text-sm text-gray-300"><%= format_time(@last_refresh) %></div>
          </div>
          <a href="/"
            class="text-xs bg-gray-800 hover:bg-gray-700 text-gray-400 px-3 py-2 rounded-lg">
            ← Dashboard
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

      <%!-- Topology tree --%>
      <div class="space-y-4">

        <%!-- Central server node --%>
        <div class="flex items-start gap-4">
          <div class="flex flex-col items-center">
            <div class="w-3 h-3 rounded-full bg-green-500 mt-3 flex-shrink-0"></div>
            <%= if @sites != [] do %>
              <div class="w-px flex-1 bg-gray-700 mt-1"></div>
            <% end %>
          </div>
          <div class="bg-gray-800 border border-gray-600 rounded-lg px-4 py-3 mb-1">
            <div class="flex items-center gap-3">
              <span class="text-white font-semibold text-sm">Central Server</span>
              <span class="text-xs text-green-400">running</span>
              <%= if @wan_up != nil do %>
                <span class={"text-xs px-2 py-0.5 rounded-full " <>
                  if(@wan_up, do: "bg-green-900 text-green-300", else: "bg-red-900 text-red-300")}>
                  WAN <%= if @wan_up, do: "up", else: "down" %>
                </span>
              <% end %>
            </div>
            <div class="text-xs text-gray-500 mt-0.5">NurseryHub · MQTT broker · Dashboard</div>
          </div>
        </div>

        <%!-- Site blocks --%>
        <%= for {site_id, nodes} <- @sites do %>
          <.site_block site_id={site_id} nodes={nodes} />
        <% end %>

      </div>

      <%!-- Empty state --%>
      <%= if @total == 0 do %>
        <div class="text-center py-24 text-gray-500">
          <div class="text-4xl mb-4">📡</div>
          <div class="text-lg">No zones connected yet</div>
          <div class="text-sm mt-2">ESP32s will appear here as they send data</div>
        </div>
      <% end %>

    </div>
    """
  end

  # ── Site block ─────────────────────────────────────────────────────────────

  defp site_block(assigns) do
    all_zones = assigns.nodes |> Enum.flat_map(fn {_, zones} -> zones end)
    n_ok      = Enum.count(all_zones, &(zone_status(&1) == :online))
    n_alert   = Enum.count(all_zones, &(zone_status(&1) == :alert))
    n_off     = Enum.count(all_zones, &(zone_status(&1) == :offline))
    n_water   = Enum.count(all_zones, &(&1.watering))
    worst     = worst_status(all_zones)

    assigns = assign(assigns,
      n_ok:      n_ok,
      n_alert:   n_alert,
      n_off:     n_off,
      n_water:   n_water,
      worst:     worst,
      all_zones: all_zones
    )

    ~H"""
    <div class="flex items-start gap-4 ml-7">
      <%!-- Connector --%>
      <div class="flex flex-col items-center">
        <div class="w-px h-4 bg-gray-700 flex-shrink-0"></div>
        <div class={"w-3 h-3 rounded-full flex-shrink-0 " <> site_dot_class(@worst)}></div>
        <div class="w-px flex-1 bg-gray-700 mt-1"></div>
      </div>

      <%!-- Site card --%>
      <div class="flex-1 mb-2">
        <div class={"border rounded-lg overflow-hidden " <> site_border_class(@worst)}>

          <%!-- Site header --%>
          <div class={"px-4 py-2 flex items-center justify-between " <> site_header_class(@worst)}>
            <div class="flex items-center gap-3">
              <span class="font-semibold text-sm text-white"><%= @site_id %></span>
              <span class="text-xs text-gray-400">
                <%= length(@nodes) %> node<%= if length(@nodes) != 1, do: "s" %> ·
                <%= length(@all_zones) %> zone<%= if length(@all_zones) != 1, do: "s" %>
              </span>
            </div>
            <div class="flex items-center gap-2 text-xs">
              <%= if @n_ok > 0 do %><span class="text-green-400"><%= @n_ok %> online</span><% end %>
              <%= if @n_water > 0 do %><span class="text-blue-400">💦 <%= @n_water %></span><% end %>
              <%= if @n_alert > 0 do %><span class="text-yellow-400">⚠ <%= @n_alert %></span><% end %>
              <%= if @n_off > 0 do %><span class="text-red-400">✕ <%= @n_off %></span><% end %>
            </div>
          </div>

          <%!-- Node blocks --%>
          <div class="divide-y divide-gray-700">
            <%= for {node_id, zones} <- @nodes do %>
              <.node_block node_id={node_id} zones={zones} />
            <% end %>
          </div>

        </div>
      </div>
    </div>
    """
  end

  # ── Node block ─────────────────────────────────────────────────────────────

  defp node_block(assigns) do
    worst = worst_status(assigns.zones)
    assigns = assign(assigns, worst: worst)

    ~H"""
    <div class="px-3 py-2">
      <%!-- Node header --%>
      <div class="flex items-center gap-2 mb-2">
        <div class={"w-2 h-2 rounded-full flex-shrink-0 " <> site_dot_class(@worst)}></div>
        <span class="font-mono text-xs font-semibold text-gray-300"><%= @node_id %></span>
        <span class="text-xs text-gray-600">ESP32 · <%= length(@zones) %> zone<%= if length(@zones) != 1, do: "s" %></span>
      </div>

      <%!-- Zone cards --%>
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-px bg-gray-700 rounded overflow-hidden ml-4">
        <%= for zone <- Enum.sort_by(@zones, & &1.zone_id) do %>
          <.zone_card zone={zone} />
        <% end %>
      </div>
    </div>
    """
  end

  # ── Zone card ──────────────────────────────────────────────────────────────

  defp zone_card(assigns) do
    status = zone_status(assigns.zone)
    assigns = assign(assigns, status: status)

    ~H"""
    <a href={"/zone/#{@zone.site_id}/#{@zone.zone_id}"}
      class={"block p-3 hover:brightness-110 transition-all cursor-pointer " <>
             zone_card_bg(@status)}>

      <%!-- Zone ID + status --%>
      <div class="flex items-center justify-between mb-2">
        <span class="font-mono font-bold text-sm text-white"><%= @zone.zone_id %></span>
        <div class="flex items-center gap-1.5">
          <%= if @zone.watering do %>
            <span class="text-blue-300 text-xs">💦</span>
          <% end %>
          <div class={"w-2.5 h-2.5 rounded-full " <> zone_dot_class(@status)}></div>
        </div>
      </div>

      <%!-- Moisture bar --%>
      <%= if is_integer(@zone.moisture) do %>
        <div class="mb-2">
          <div class="flex items-center justify-between mb-0.5">
            <span class="text-xs text-gray-400">moisture</span>
            <span class="text-xs text-gray-200"><%= @zone.moisture %>%</span>
          </div>
          <div class="w-full bg-gray-700 rounded-full h-1.5">
            <div class={"h-1.5 rounded-full " <> moisture_bar_class(@zone.moisture)}
                 style={"width: #{@zone.moisture}%"}></div>
          </div>
        </div>
      <% end %>

      <%!-- Sensor readings --%>
      <div class="grid grid-cols-2 gap-x-2 text-xs text-gray-400 mb-2">
        <%= if @zone.air_temp do %>
          <span>🌡 <%= @zone.air_temp %>°C</span>
        <% end %>
        <%= if @zone.vpd do %>
          <span>VPD <%= Float.round(@zone.vpd, 2) %></span>
        <% end %>
        <%= if @zone.lux do %>
          <span>☀ <%= format_lux(@zone.lux) %></span>
        <% end %>
        <%= if @zone.leaf_temp do %>
          <span>🌿 <%= @zone.leaf_temp %>°C</span>
        <% end %>
      </div>

      <%!-- Alerts --%>
      <%= if @zone.alerts != [] do %>
        <div class="space-y-0.5">
          <%= for alert <- @zone.alerts do %>
            <div class={"text-xs px-1.5 py-0.5 rounded " <> alert_chip_class(alert)}>
              <%= alert_label(alert) %>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Last seen --%>
      <div class="mt-2 text-xs text-gray-600">
        <%= time_ago(@zone.last_seen) %>
      </div>

      <%!-- Mode badge (if not normal) --%>
      <%= if @zone.mode not in ["normal", "unknown", nil] do %>
        <div class={"mt-1 text-xs px-1.5 py-0.5 rounded inline-block " <>
                    mode_chip_class(@zone.mode)}>
          <%= mode_label(@zone.mode) %>
        </div>
      <% end %>

    </a>
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

  # DataSync WAN status — only meaningful on a site Pi, returns nil on central
  defp datasync_wan_up? do
    case Process.whereis(NurseryHub.DataSync) do
      nil -> nil
      _   ->
        try do
          state = :sys.get_state(NurseryHub.DataSync)
          Map.get(state, :wan_up)
        rescue
          _ -> nil
        end
    end
  end

  # ── Status helpers ─────────────────────────────────────────────────────────

  defp zone_status(zone) do
    cond do
      :offline in zone.alerts -> :offline
      zone.watering            -> :watering
      zone.alerts != []        -> :alert
      true                     -> :online
    end
  end

  defp worst_status(zones) do
    statuses = Enum.map(zones, &zone_status/1)
    cond do
      :offline  in statuses -> :offline
      :alert    in statuses -> :alert
      :watering in statuses -> :watering
      true                  -> :online
    end
  end

  # ── Styling ────────────────────────────────────────────────────────────────

  defp zone_dot_class(:online),   do: "bg-green-500"
  defp zone_dot_class(:offline),  do: "bg-red-500"
  defp zone_dot_class(:alert),    do: "bg-yellow-400 animate-pulse"
  defp zone_dot_class(:watering), do: "bg-blue-400 animate-pulse"

  defp zone_card_bg(:online),   do: "bg-gray-900"
  defp zone_card_bg(:offline),  do: "bg-gray-900/60"
  defp zone_card_bg(:alert),    do: "bg-yellow-950/60"
  defp zone_card_bg(:watering), do: "bg-blue-950/60"

  defp site_dot_class(:online),   do: "bg-green-500"
  defp site_dot_class(:offline),  do: "bg-red-500"
  defp site_dot_class(:alert),    do: "bg-yellow-400 animate-pulse"
  defp site_dot_class(:watering), do: "bg-blue-400 animate-pulse"

  defp site_border_class(:online),   do: "border-gray-700"
  defp site_border_class(:offline),  do: "border-red-800"
  defp site_border_class(:alert),    do: "border-yellow-700"
  defp site_border_class(:watering), do: "border-blue-800"

  defp site_header_class(:online),   do: "bg-gray-800"
  defp site_header_class(:offline),  do: "bg-red-950"
  defp site_header_class(:alert),    do: "bg-yellow-950"
  defp site_header_class(:watering), do: "bg-blue-950"

  defp moisture_bar_class(pct) when pct < 20, do: "bg-red-500"
  defp moisture_bar_class(pct) when pct < 40, do: "bg-yellow-400"
  defp moisture_bar_class(pct) when pct < 70, do: "bg-green-500"
  defp moisture_bar_class(_),                 do: "bg-blue-400"

  defp alert_chip_class(:offline),      do: "bg-red-900 text-red-300"
  defp alert_chip_class(:critical_dry), do: "bg-orange-900 text-orange-300"
  defp alert_chip_class(:valve_stuck),  do: "bg-red-900 text-red-300"
  defp alert_chip_class(:sensor_fault), do: "bg-yellow-900 text-yellow-300"
  defp alert_chip_class(_),             do: "bg-gray-700 text-gray-300"

  defp mode_chip_class("local"),       do: "bg-blue-900 text-blue-300"
  defp mode_chip_class("no_vpd"),      do: "bg-yellow-900 text-yellow-300"
  defp mode_chip_class("no_moisture"), do: "bg-orange-900 text-orange-300"
  defp mode_chip_class(_),             do: "bg-gray-700 text-gray-300"

  defp alert_label(:offline),       do: "Offline"
  defp alert_label(:valve_stuck),   do: "Valve stuck"
  defp alert_label(:critical_dry),  do: "Critical dry"
  defp alert_label(:sensor_fault),  do: "Sensor fault"
  defp alert_label(other),          do: to_string(other)

  defp mode_label("local"),       do: "Local mode"
  defp mode_label("no_vpd"),      do: "No VPD"
  defp mode_label("no_moisture"), do: "No moisture"
  defp mode_label(m),             do: m

  defp format_lux(nil), do: nil
  defp format_lux(v) when v >= 1000, do: "#{round(v / 1000)}k"
  defp format_lux(v),                do: "#{round(v)}"

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
