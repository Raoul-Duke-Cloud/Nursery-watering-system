defmodule NurseryHubWeb.LogsLive do
  @moduledoc "Alert history page — shows all logged alerts with active/resolved filter."

  use Phoenix.LiveView
  alias NurseryHub.AlertLog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, logs: AlertLog.recent(), filter: "all")}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    logs = case status do
      "active"   -> AlertLog.active()
      "resolved" -> AlertLog.recent() |> Enum.filter(&(not is_nil(&1.resolved_at)))
      _          -> AlertLog.recent()
    end
    {:noreply, assign(socket, logs: logs, filter: status)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-5xl mx-auto">

      <a href="/" class="text-sm text-gray-400 hover:text-white mb-6 inline-block">
        ← Dashboard
      </a>

      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-white">Alert Log</h1>
        <div class="flex items-center gap-4">
          <span class="text-sm text-gray-500"><%= length(@logs) %> entries</span>
          <a href="/csv/logs"
            class="text-xs bg-green-800 hover:bg-green-700 text-green-300 px-3 py-1.5 rounded">
            ↓ Download CSV
          </a>
        </div>
      </div>

      <%!-- Filter --%>
      <form phx-change="filter" class="flex gap-3 mb-6">
        <label class="text-xs text-gray-500 self-center">Show</label>
        <select name="status"
          class="bg-gray-800 border border-gray-600 text-gray-200 text-sm rounded px-2 py-1.5">
          <option value="all"      selected={@filter == "all"}>All alerts</option>
          <option value="active"   selected={@filter == "active"}>Active only</option>
          <option value="resolved" selected={@filter == "resolved"}>Resolved only</option>
        </select>
      </form>

      <%= if @logs == [] do %>
        <div class="text-center py-24 text-gray-500">
          <div class="text-lg">No alerts logged yet</div>
          <div class="text-sm mt-2">Alerts will appear here as they fire</div>
        </div>
      <% else %>
        <div class="bg-gray-900 border border-gray-700 rounded-xl overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="text-xs text-gray-500 border-b border-gray-700 uppercase tracking-wide">
                  <th class="text-left px-4 py-2 font-normal">Time</th>
                  <th class="text-left px-4 py-2 font-normal">Site</th>
                  <th class="text-left px-4 py-2 font-normal">Zone</th>
                  <th class="text-left px-4 py-2 font-normal">Alert</th>
                  <th class="text-left px-4 py-2 font-normal">Detail</th>
                  <th class="text-left px-4 py-2 font-normal">Status</th>
                </tr>
              </thead>
              <tbody>
                <%= for log <- @logs do %>
                  <tr class={"border-b border-gray-800 hover:bg-gray-800/30 " <>
                              if(is_nil(log.resolved_at), do: "", else: "opacity-50")}>
                    <td class="px-4 py-2.5 text-gray-400 text-xs whitespace-nowrap">
                      <%= Calendar.strftime(log.inserted_at, "%d/%m/%Y %H:%M") %>
                    </td>
                    <td class="px-4 py-2.5 text-gray-300"><%= log.site_id %></td>
                    <td class="px-4 py-2.5 text-white font-medium"><%= log.zone_id %></td>
                    <td class="px-4 py-2.5">
                      <span class={"text-xs font-medium px-2 py-0.5 rounded-full " <>
                                   alert_badge_class(log.alert_type)}>
                        <%= alert_label(log.alert_type) %>
                      </span>
                    </td>
                    <td class="px-4 py-2.5 text-gray-400 text-xs">
                      <%= format_detail(log.detail) %>
                    </td>
                    <td class="px-4 py-2.5 text-xs">
                      <%= if is_nil(log.resolved_at) do %>
                        <span class="text-yellow-400">Active</span>
                      <% else %>
                        <span class="text-gray-500">
                          Resolved <%= Calendar.strftime(log.resolved_at, "%d/%m %H:%M") %>
                        </span>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>

    </div>
    """
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp alert_label("zone_offline"),     do: "Zone offline"
  defp alert_label("valve_stuck_open"), do: "Valve stuck open"
  defp alert_label("sensor_fault"),     do: "Sensor fault"
  defp alert_label("critical_dry"),     do: "Critically dry"
  defp alert_label("settings_changed"), do: "Settings saved"
  defp alert_label(other),              do: other

  defp alert_badge_class("valve_stuck_open"), do: "bg-red-900/60 text-red-300"
  defp alert_badge_class("critical_dry"),     do: "bg-red-900/60 text-red-300"
  defp alert_badge_class("zone_offline"),     do: "bg-orange-900/60 text-orange-300"
  defp alert_badge_class("sensor_fault"),     do: "bg-yellow-900/60 text-yellow-300"
  defp alert_badge_class("settings_changed"), do: "bg-blue-900/60 text-blue-300"
  defp alert_badge_class(_),                  do: "bg-gray-700 text-gray-300"

  defp format_detail(nil), do: ""
  defp format_detail(json) do
    case Jason.decode(json) do
      {:ok, map} ->
        map
        |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
        |> Enum.join(", ")
      _ -> json
    end
  end
end
