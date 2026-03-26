defmodule NurseryHubWeb.SettingsLive do
  @moduledoc "System settings page — alerts, OTA firmware."

  use Phoenix.LiveView
  alias NurseryHub.{Settings, Alerting, AlertLog}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      settings:    Settings.all(),
      saved:       nil,
      error:       nil,
      test_result: nil
    )}
  end

  # ── Save handlers ───────────────────────────────────────────────────────────

  @impl true
  def handle_event("save_email", params, socket) do
    case check_password(params["settings_password"]) do
      :ok ->
        Settings.put_all(%{
          "email.enabled"       => params["enabled"] || "false",
          "email.smtp_host"     => params["smtp_host"],
          "email.smtp_port"     => params["smtp_port"],
          "email.smtp_username" => params["smtp_username"],
          "email.smtp_password" => params["smtp_password"],
          "email.from"          => params["from"],
          "email.to"            => params["to"]
        })
        AlertLog.log("system", "settings", :settings_changed, %{
          section: "email",
          smtp_host: params["smtp_host"],
          from: params["from"],
          to: params["to"],
          enabled: params["enabled"] || "false"
        })
        {:noreply, assign(socket, settings: Settings.all(), saved: :email, error: nil)}

      {:error, msg} ->
        {:noreply, assign(socket, saved: nil, error: {:email, msg})}
    end
  end

  @impl true
  def handle_event("save_sms", params, socket) do
    case check_password(params["settings_password"]) do
      :ok ->
        Settings.put_all(%{
          "sms.enabled"      => params["enabled"] || "false",
          "sms.account_sid"  => params["account_sid"],
          "sms.auth_token"   => params["auth_token"],
          "sms.from_number"  => params["from_number"],
          "sms.to_number"    => params["to_number"]
        })
        AlertLog.log("system", "settings", :settings_changed, %{
          section: "sms",
          from_number: params["from_number"],
          to_number: params["to_number"],
          enabled: params["enabled"] || "false"
        })
        {:noreply, assign(socket, settings: Settings.all(), saved: :sms, error: nil)}

      {:error, msg} ->
        {:noreply, assign(socket, saved: nil, error: {:sms, msg})}
    end
  end

  @impl true
  def handle_event("save_alert_routing", params, socket) do
    case check_password(params["settings_password"]) do
      :ok ->
        routing = %{
          "alerts.zone_offline"     => delivery_value(params, "zone_offline"),
          "alerts.valve_stuck_open" => delivery_value(params, "valve_stuck_open"),
          "alerts.sensor_fault"     => delivery_value(params, "sensor_fault"),
          "alerts.critical_dry"     => delivery_value(params, "critical_dry")
        }
        Settings.put_all(routing)
        AlertLog.log("system", "settings", :settings_changed, Map.merge(%{section: "alert_routing"}, routing))
        {:noreply, assign(socket, settings: Settings.all(), saved: :routing, error: nil)}

      {:error, msg} ->
        {:noreply, assign(socket, saved: nil, error: {:routing, msg})}
    end
  end

  @impl true
  def handle_event("save_ota", params, socket) do
    case check_password(params["settings_password"]) do
      :ok ->
        Settings.put("ota.firmware_version", params["firmware_version"])
        AlertLog.log("system", "settings", :settings_changed, %{
          section: "ota",
          firmware_version: params["firmware_version"]
        })
        {:noreply, assign(socket, settings: Settings.all(), saved: :ota, error: nil)}

      {:error, msg} ->
        {:noreply, assign(socket, saved: nil, error: {:ota, msg})}
    end
  end

  @impl true
  def handle_event("save_consumption", params, socket) do
    case check_password(params["settings_password"]) do
      :ok ->
        Settings.put_all(%{
          "consumption.flow_rate_lph" => params["flow_rate_lph"],
          "consumption.valve_watts"   => params["valve_watts"]
        })
        AlertLog.log("system", "settings", :settings_changed, %{
          section:        "consumption",
          flow_rate_lph:  params["flow_rate_lph"],
          valve_watts:    params["valve_watts"]
        })
        {:noreply, assign(socket, settings: Settings.all(), saved: :consumption, error: nil)}

      {:error, msg} ->
        {:noreply, assign(socket, saved: nil, error: {:consumption, msg})}
    end
  end

  # ── Test handlers ───────────────────────────────────────────────────────────

  @impl true
  def handle_event("test_email", _params, socket) do
    result = case Alerting.test_email() do
      :ok                       -> {:ok, "Test email sent successfully"}
      {:error, :not_configured} -> {:error, "Email not fully configured — fill in all fields above"}
      {:error, reason}          -> {:error, "Send failed: #{inspect(reason)}"}
    end
    {:noreply, assign(socket, test_result: {:email, result})}
  end

  @impl true
  def handle_event("test_sms", _params, socket) do
    result = case Alerting.test_sms() do
      :ok                       -> {:ok, "Test SMS sent successfully"}
      {:error, :not_configured} -> {:error, "SMS not fully configured — fill in all fields above"}
      {:error, reason}          -> {:error, "Send failed: #{inspect(reason)}"}
    end
    {:noreply, assign(socket, test_result: {:sms, result})}
  end

  # ── Render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-3xl mx-auto">

      <a href="/" class="text-sm text-gray-400 hover:text-white mb-6 inline-block">
        ← Dashboard
      </a>

      <h1 class="text-2xl font-bold text-white mb-2">System Settings</h1>

      <%= unless password_configured?() do %>
        <div class="bg-yellow-900/40 border border-yellow-700 rounded-lg px-4 py-3 mb-6 text-sm text-yellow-300">
          Settings password not configured — add
          <code class="text-yellow-200">config :nursery_hub, :settings_password, "..."</code>
          to <code class="text-yellow-200">config/config.exs</code> and restart before going live.
          Saves are currently unrestricted.
        </div>
      <% end %>

      <p class="text-gray-500 text-sm mb-8">
        All saves require the settings password defined in <code class="text-gray-400">config/config.exs</code>.
      </p>

      <%!-- Email alerts --%>
      <.section title="Email Alerts" saved={@saved == :email} error={@error} section={:email}>
        <form phx-submit="save_email" class="space-y-4">
          <.toggle name="enabled" label="Enable email alerts"
            checked={@settings["email.enabled"] == "true"} />
          <.field name="smtp_host"     label="SMTP host"     value={@settings["email.smtp_host"]}
            placeholder="smtp.gmail.com" />
          <.field name="smtp_port"     label="SMTP port"     value={@settings["email.smtp_port"]}
            placeholder="587" />
          <.field name="smtp_username" label="SMTP username" value={@settings["email.smtp_username"]}
            placeholder="you@gmail.com" />
          <.field name="smtp_password" label="SMTP password" value={@settings["email.smtp_password"]}
            type="password" placeholder="••••••••" />
          <.field name="from" label="From address" value={@settings["email.from"]}
            placeholder="nursery@yourdomain.com" />
          <.field name="to"   label="To address"   value={@settings["email.to"]}
            placeholder="alerts@yourdomain.com" />
          <.password_field />
          <div class="flex items-center gap-3">
            <.save_button />
            <button type="button" phx-click="test_email"
              class="text-sm bg-gray-700 hover:bg-gray-600 text-gray-300 px-4 py-2 rounded-lg">
              Send test email
            </button>
          </div>
        </form>
        <.test_result result={@test_result} channel={:email} />
      </.section>

      <%!-- SMS alerts --%>
      <.section title="SMS Alerts (Twilio)" saved={@saved == :sms} error={@error} section={:sms}>
        <form phx-submit="save_sms" class="space-y-4">
          <.toggle name="enabled" label="Enable SMS alerts"
            checked={@settings["sms.enabled"] == "true"} />
          <.field name="account_sid" label="Account SID"  value={@settings["sms.account_sid"]}
            placeholder="ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" />
          <.field name="auth_token"  label="Auth token"   value={@settings["sms.auth_token"]}
            type="password" placeholder="••••••••" />
          <.field name="from_number" label="From number"  value={@settings["sms.from_number"]}
            placeholder="+61400000000" />
          <.field name="to_number"   label="To number"    value={@settings["sms.to_number"]}
            placeholder="+61400000000" />
          <.password_field />
          <div class="flex items-center gap-3">
            <.save_button />
            <button type="button" phx-click="test_sms"
              class="text-sm bg-gray-700 hover:bg-gray-600 text-gray-300 px-4 py-2 rounded-lg">
              Send test SMS
            </button>
          </div>
        </form>
        <.test_result result={@test_result} channel={:sms} />
      </.section>

      <%!-- Alert routing --%>
      <.section title="Alert Routing" saved={@saved == :routing} error={@error} section={:routing}>
        <p class="text-sm text-gray-400 mb-4">
          Choose how each alert type is delivered. Check both for critical alerts.
        </p>
        <form phx-submit="save_alert_routing">
          <table class="w-full text-sm mb-4">
            <thead>
              <tr class="text-gray-400 text-xs border-b border-gray-700">
                <th class="text-left py-2">Alert type</th>
                <th class="text-center py-2 px-4">Email</th>
                <th class="text-center py-2 px-4">SMS</th>
              </tr>
            </thead>
            <tbody>
              <.routing_row key="zone_offline"     label="Zone offline"     settings={@settings} />
              <.routing_row key="valve_stuck_open" label="Valve stuck open" settings={@settings} />
              <.routing_row key="sensor_fault"     label="Sensor fault"     settings={@settings} />
              <.routing_row key="critical_dry"     label="Critically dry"   settings={@settings} />
            </tbody>
          </table>
          <.password_field />
          <div class="mt-4"><.save_button /></div>
        </form>
      </.section>

      <%!-- Consumption defaults --%>
      <.section title="Consumption Defaults" saved={@saved == :consumption} error={@error} section={:consumption}>
        <p class="text-sm text-gray-400 mb-4">
          Used to estimate water and electricity use on the zone history page.
          Set <strong class="text-gray-300">flow rate</strong> to the total dripper output for a
          typical zone (e.g. 5 × 2 L/hr drippers = 10). Set
          <strong class="text-gray-300">valve watts</strong> to your solenoid valve's rated draw
          while open (typically 5–10 W).
        </p>
        <form phx-submit="save_consumption" class="space-y-4">
          <.field name="flow_rate_lph" label="Dripper output per zone (L/hr)"
            value={@settings["consumption.flow_rate_lph"]} placeholder="2.0" />
          <.field name="valve_watts" label="Solenoid valve rated watts"
            value={@settings["consumption.valve_watts"]} placeholder="7.0" />
          <.password_field />
          <.save_button />
        </form>
      </.section>

      <%!-- OTA firmware --%>
      <.section title="OTA Firmware" saved={@saved == :ota} error={@error} section={:ota}>
        <p class="text-sm text-gray-400 mb-4">
          The version number here is what ESP32s compare against on boot.
          Upload a new <code class="text-gray-300">.bin</code> file to
          <code class="text-gray-300">priv/static/firmware/esp32_plant_monitor.bin</code>
          then increment this number and save — ESP32s will update automatically.
        </p>
        <form phx-submit="save_ota" class="space-y-4">
          <.field name="firmware_version" label="Current firmware version"
            value={@settings["ota.firmware_version"]} placeholder="42" />
          <.password_field />
          <.save_button label="Save & Deploy" />
        </form>
      </.section>

    </div>
    """
  end

  # ── Components ──────────────────────────────────────────────────────────────

  defp section(assigns) do
    error_here = case assigns.error do
      {section, _msg} -> section == assigns.section
      _               -> false
    end
    error_msg = case assigns.error do
      {section, msg} when section == assigns.section -> msg
      _ -> nil
    end
    assigns = assign(assigns, error_here: error_here, error_msg: error_msg)

    ~H"""
    <div class="bg-gray-900 border border-gray-700 rounded-xl p-6 mb-6">
      <div class="flex items-center justify-between mb-5">
        <h2 class="text-lg font-semibold text-white"><%= @title %></h2>
        <div>
          <%= if @saved do %>
            <span class="text-xs text-green-400">✓ Saved</span>
          <% end %>
          <%= if @error_here do %>
            <span class="text-xs text-red-400">✗ <%= @error_msg %></span>
          <% end %>
        </div>
      </div>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  defp password_field(assigns) do
    ~H"""
    <div class="border-t border-gray-700 pt-4">
      <label class="block text-xs text-gray-400 mb-1">Settings password</label>
      <input type="password" name="settings_password" placeholder="••••••••" autocomplete="off"
        class="w-full bg-gray-800 border border-gray-600 text-gray-200 text-sm
               rounded px-3 py-2 focus:outline-none focus:border-blue-500" />
    </div>
    """
  end

  defp field(assigns) do
    assigns = Map.put_new(assigns, :type, "text")
    ~H"""
    <div>
      <label class="block text-xs text-gray-400 mb-1"><%= @label %></label>
      <input type={@type} name={@name} value={@value || ""} placeholder={@placeholder}
        class="w-full bg-gray-800 border border-gray-600 text-gray-200 text-sm
               rounded px-3 py-2 focus:outline-none focus:border-blue-500" />
    </div>
    """
  end

  defp toggle(assigns) do
    ~H"""
    <label class="flex items-center gap-3 cursor-pointer">
      <input type="checkbox" name={@name} value="true" checked={@checked}
        class="w-4 h-4 accent-blue-500" />
      <span class="text-sm text-gray-300"><%= @label %></span>
    </label>
    """
  end

  defp routing_row(assigns) do
    delivery = Map.get(assigns.settings, "alerts.#{assigns.key}") || ""
    assigns  = assign(assigns,
      email_checked: String.contains?(delivery, "email"),
      sms_checked:   String.contains?(delivery, "sms")
    )
    ~H"""
    <tr class="border-b border-gray-800">
      <td class="py-2 text-gray-300"><%= @label %></td>
      <td class="py-2 text-center px-4">
        <input type="checkbox" name={"#{@key}_email"} value="true"
          checked={@email_checked} class="w-4 h-4 accent-blue-500" />
      </td>
      <td class="py-2 text-center px-4">
        <input type="checkbox" name={"#{@key}_sms"} value="true"
          checked={@sms_checked} class="w-4 h-4 accent-blue-500" />
      </td>
    </tr>
    """
  end

  defp save_button(assigns) do
    assigns = Map.put_new(assigns, :label, "Save")
    ~H"""
    <button type="submit"
      class="bg-blue-700 hover:bg-blue-600 text-white text-sm px-4 py-2 rounded-lg">
      <%= @label %>
    </button>
    """
  end

  defp test_result(%{result: {channel, _}} = assigns) when channel == assigns.channel do
    ~H"""
    <%= case @result do %>
      <% {_ch, {:ok, msg}}    -> %><p class="text-sm text-green-400 mt-2">✓ <%= msg %></p>
      <% {_ch, {:error, msg}} -> %><p class="text-sm text-red-400 mt-2">✗ <%= msg %></p>
    <% end %>
    """
  end
  defp test_result(assigns), do: ~H""

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp check_password(submitted) do
    expected = Application.get_env(:nursery_hub, :settings_password, "")
    cond do
      expected == ""         -> :ok   # not configured — allow during development
      submitted == expected  -> :ok
      true                   -> {:error, "Incorrect settings password"}
    end
  end

  defp password_configured? do
    Application.get_env(:nursery_hub, :settings_password, "") != ""
  end

  defp delivery_value(params, key) do
    email = if params["#{key}_email"] == "true", do: "email", else: nil
    sms   = if params["#{key}_sms"]   == "true", do: "sms",   else: nil
    [email, sms] |> Enum.reject(&is_nil/1) |> Enum.join(",")
  end
end
