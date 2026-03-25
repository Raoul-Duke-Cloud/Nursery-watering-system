defmodule NurseryHubWeb.ZoneLive do
  @moduledoc """
  Detail view for a single zone — shows history chart and recent readings table.
  """

  use Phoenix.LiveView
  alias NurseryHub.{SensorReading, ZoneServer}

  @impl true
  def mount(%{"site_id" => site_id, "zone_id" => zone_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NurseryHub.PubSub, "zones:updates")
    end

    readings = SensorReading.recent(site_id, zone_id, 48)
    current  = ZoneServer.state(site_id, zone_id)

    {:ok, assign(socket,
      site_id:  site_id,
      zone_id:  zone_id,
      readings: readings,
      current:  current
    )}
  end

  @impl true
  def handle_info({:zone_update, zone}, socket) do
    if zone.site_id == socket.assigns.site_id and zone.zone_id == socket.assigns.zone_id do
      readings = SensorReading.recent(socket.assigns.site_id, socket.assigns.zone_id, 48)
      {:noreply, assign(socket, current: zone, readings: readings)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("water_now", _, socket) do
    ZoneServer.send_command(socket.assigns.site_id, socket.assigns.zone_id,
      %{cmd: "water", duration: 15})
    {:noreply, socket}
  end

  @impl true
  def handle_event("stop_water", _, socket) do
    ZoneServer.send_command(socket.assigns.site_id, socket.assigns.zone_id, %{cmd: "stop"})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    # Prepare chart data — last 48 readings in chronological order
    chart_readings = Enum.reverse(assigns.readings)
    labels     = Enum.map(chart_readings, &Calendar.strftime(&1.inserted_at, "%H:%M"))
    moistures  = Enum.map(chart_readings, & &1.moisture)
    vpds       = Enum.map(chart_readings, &if(&1.vpd, do: Float.round(&1.vpd, 2), else: nil))

    assigns = assign(assigns,
      labels:    Jason.encode!(labels),
      moistures: Jason.encode!(moistures),
      vpds:      Jason.encode!(vpds)
    )

    ~H"""
    <div class="p-6 max-w-5xl mx-auto">

      <%!-- Back link --%>
      <a href="/" class="text-sm text-gray-400 hover:text-white mb-6 inline-block">
        ← All sites
      </a>

      <%!-- Header --%>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold text-white"><%= @zone_id %></h1>
          <div class="text-gray-400 text-sm"><%= @site_id %></div>
        </div>

        <%!-- Controls --%>
        <div class="flex gap-3">
          <button phx-click="water_now"
            class="bg-blue-700 hover:bg-blue-600 text-white text-sm px-4 py-2 rounded-lg">
            💧 Water now (15s)
          </button>
          <button phx-click="stop_water"
            class="bg-gray-700 hover:bg-gray-600 text-white text-sm px-4 py-2 rounded-lg">
            Stop
          </button>
        </div>
      </div>

      <%!-- Current readings --%>
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-8">
        <.stat label="Moisture" value={@current && @current.moisture} unit="%" />
        <.stat label="VPD"      value={@current && format_vpd(@current.vpd)} unit="kPa" />
        <.stat label="Air temp" value={@current && @current.air_temp} unit="°C" />
        <.stat label="Humidity" value={@current && @current.humidity} unit="%" />
      </div>

      <%!-- Charts --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
        <div class="bg-gray-900 border border-gray-700 rounded-xl p-4">
          <div class="text-sm text-gray-400 mb-3">Soil Moisture % (last 24h)</div>
          <canvas id="moisture-chart" phx-hook="MoistureChart"
            data-labels={@labels} data-values={@moistures}
            class="w-full" height="160"></canvas>
        </div>
        <div class="bg-gray-900 border border-gray-700 rounded-xl p-4">
          <div class="text-sm text-gray-400 mb-3">VPD kPa (last 24h)</div>
          <canvas id="vpd-chart" phx-hook="VPDChart"
            data-labels={@labels} data-values={@vpds}
            class="w-full" height="160"></canvas>
        </div>
      </div>

      <%!-- Recent readings table --%>
      <div class="bg-gray-900 border border-gray-700 rounded-xl overflow-hidden">
        <div class="px-4 py-3 border-b border-gray-700 text-sm font-medium text-gray-300">
          Recent readings
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="text-gray-400 text-xs border-b border-gray-800">
                <th class="px-4 py-2 text-left">Time</th>
                <th class="px-4 py-2 text-right">Moisture</th>
                <th class="px-4 py-2 text-right">VPD</th>
                <th class="px-4 py-2 text-right">Air temp</th>
                <th class="px-4 py-2 text-right">Humidity</th>
                <th class="px-4 py-2 text-right">Light</th>
                <th class="px-4 py-2 text-center">Watering</th>
                <th class="px-4 py-2 text-center">Mode</th>
              </tr>
            </thead>
            <tbody>
              <%= for r <- @readings do %>
                <tr class="border-b border-gray-800/50 hover:bg-gray-800/30">
                  <td class="px-4 py-2 text-gray-400">
                    <%= Calendar.strftime(r.inserted_at, "%d/%m %H:%M") %>
                  </td>
                  <td class={"px-4 py-2 text-right font-medium " <> moisture_class(r.moisture)}>
                    <%= r.moisture %>%
                  </td>
                  <td class="px-4 py-2 text-right text-gray-300">
                    <%= if r.vpd, do: "#{Float.round(r.vpd, 2)} kPa", else: "--" %>
                  </td>
                  <td class="px-4 py-2 text-right text-gray-300">
                    <%= if r.air_temp, do: "#{r.air_temp}°C", else: "--" %>
                  </td>
                  <td class="px-4 py-2 text-right text-gray-300">
                    <%= if r.humidity, do: "#{r.humidity}%", else: "--" %>
                  </td>
                  <td class="px-4 py-2 text-right text-gray-300">
                    <%= if r.lux, do: format_lux(r.lux), else: "--" %>
                  </td>
                  <td class="px-4 py-2 text-center">
                    <%= if r.watering, do: "💧", else: "" %>
                  </td>
                  <td class="px-4 py-2 text-center text-xs text-gray-500">
                    <%= r.mode %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>

    </div>

    <%!-- Chart initialisation --%>
    <script>
      function makeChart(id, label, color) {
        const el = document.getElementById(id)
        if (!el) return
        const labels = JSON.parse(el.dataset.labels)
        const values = JSON.parse(el.dataset.values)
        new Chart(el, {
          type: 'line',
          data: {
            labels,
            datasets: [{ label, data: values, borderColor: color,
              backgroundColor: color + '22', fill: true,
              tension: 0.3, pointRadius: 2 }]
          },
          options: {
            responsive: true,
            plugins: { legend: { display: false } },
            scales: {
              x: { ticks: { color: '#6b7280', maxTicksLimit: 8 }, grid: { color: '#1f2937' } },
              y: { ticks: { color: '#6b7280' }, grid: { color: '#1f2937' } }
            }
          }
        })
      }
      makeChart('moisture-chart', 'Moisture %', '#22c55e')
      makeChart('vpd-chart', 'VPD kPa', '#60a5fa')
    </script>
    """
  end

  defp stat(assigns) do
    ~H"""
    <div class="bg-gray-900 border border-gray-700 rounded-xl p-4">
      <div class="text-xs text-gray-400 mb-1"><%= @label %></div>
      <div class="text-2xl font-bold text-white">
        <%= if is_nil(@value), do: "--", else: "#{@value}#{@unit}" %>
      </div>
    </div>
    """
  end

  defp format_vpd(nil), do: nil
  defp format_vpd(v),   do: Float.round(v, 2)

  defp format_lux(v) when v >= 1000, do: "#{round(v / 1000)}k lux"
  defp format_lux(v),                do: "#{round(v)} lux"

  defp moisture_class(nil),              do: "text-gray-400"
  defp moisture_class(pct) when pct < 20, do: "text-red-400"
  defp moisture_class(pct) when pct < 40, do: "text-yellow-400"
  defp moisture_class(_),                 do: "text-green-400"
end
