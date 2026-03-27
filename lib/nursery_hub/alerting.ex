defmodule NurseryHub.Alerting do
  @moduledoc """
  Handles alerts from zone processes.

  Every alert is written to the alert_logs table regardless of delivery method.
  Delivery (email/SMS) is then routed based on Settings.

  Alert types:
    :zone_offline     — zone stopped sending data
    :valve_stuck_open — valve open longer than safety limit
    :sensor_fault     — one or more sensors reporting failure
    :critical_dry     — moisture below emergency threshold
  """

  require Logger
  alias NurseryHub.{Settings, AlertLog}

  def alert(type, site_id, zone_id, detail) do
    subject = format_subject(type, site_id, zone_id)
    body    = format_body(type, site_id, zone_id, detail)

    log_alert(type, body)
    AlertLog.log(site_id, zone_id, type, detail)

    delivery = Settings.alert_delivery(Atom.to_string(type))

    if "email" in delivery and Settings.enabled?("email.enabled") do
      send_email(subject, body)
    end

    if "sms" in delivery and Settings.enabled?("sms.enabled") do
      send_sms(body)
    end
  end

  @doc "Send a test email using current settings. Returns :ok or {:error, reason}."
  def test_email do
    send_email("[NurseryHub] Test alert", "This is a test alert from NurseryHub. Email delivery is working correctly.")
  end

  @doc "Send a test SMS using current settings. Returns :ok or {:error, reason}."
  def test_sms do
    send_sms("NurseryHub test alert — SMS delivery is working.")
  end

  @doc "Send the daily system-alive heartbeat email with a zone summary."
  def heartbeat(summary) do
    subject = "[NurseryHub] Daily heartbeat — system alive"
    body    = format_heartbeat(summary)
    Logger.info("[Alerting] Sending daily heartbeat email")
    send_email(subject, body)
  end

  # ── Formatting ─────────────────────────────────────────────────────────────

  defp format_subject(:valve_stuck_open, site_id, zone_id),
    do: "[NurseryHub] URGENT: Valve stuck open — #{site_id}/#{zone_id}"
  defp format_subject(:critical_dry, site_id, zone_id),
    do: "[NurseryHub] URGENT: Critically dry — #{site_id}/#{zone_id}"
  defp format_subject(:zone_offline, site_id, zone_id),
    do: "[NurseryHub] Zone offline — #{site_id}/#{zone_id}"
  defp format_subject(:sensor_fault, site_id, zone_id),
    do: "[NurseryHub] Sensor fault — #{site_id}/#{zone_id}"
  defp format_subject(:dripper_degraded, site_id, zone_id),
    do: "[NurseryHub] Dripper degraded — #{site_id}/#{zone_id}"
  defp format_subject(:freeze_risk, site_id, zone_id),
    do: "[NurseryHub] URGENT: Freeze risk — #{site_id}/#{zone_id}"
  defp format_subject(:sensor_out_of_bounds, site_id, zone_id),
    do: "[NurseryHub] Sensor out-of-bounds reading — #{site_id}/#{zone_id}"
  defp format_subject(:stuck_moisture, site_id, zone_id),
    do: "[NurseryHub] Moisture reading stuck — #{site_id}/#{zone_id}"
  defp format_subject(type, site_id, zone_id),
    do: "[NurseryHub] Alert: #{type} — #{site_id}/#{zone_id}"

  defp format_body(:zone_offline, site_id, zone_id, %{silent_for_minutes: mins}) do
    """
    Zone offline: #{site_id} / #{zone_id}
    No data received for #{mins} minutes.

    Check: WiFi at site, ESP32 power, 4G router.
    """
  end

  defp format_body(:valve_stuck_open, site_id, zone_id, %{open_for_seconds: secs}) do
    """
    Valve may be stuck open: #{site_id} / #{zone_id}
    Valve has been open for #{secs} seconds — a stop command has been sent.

    Check: relay, solenoid valve, wiring.
    """
  end

  defp format_body(:sensor_fault, site_id, zone_id, %{failed_sensors: sensors, operating_mode: mode}) do
    """
    Sensor fault: #{site_id} / #{zone_id}
    Failed sensors: #{Enum.join(sensors, ", ")}
    Zone now running in degraded mode: #{mode}

    Watering continues on a fallback schedule. Check sensors when next on site.
    """
  end

  defp format_body(:critical_dry, site_id, zone_id, %{moisture: pct}) do
    """
    Critically dry: #{site_id} / #{zone_id}
    Moisture at #{pct}% — ESP32 should be emergency watering now.

    If plants are not being watered, check valve and relay immediately.
    """
  end

  defp format_body(:dripper_degraded, site_id, zone_id, %{consecutive_faults: count}) do
    """
    Dripper degraded: #{site_id} / #{zone_id}
    #{count} consecutive watering events with no significant moisture rise.

    Likely causes (especially with hard water): emitter scale/blockage; valve not opening fully;
    supply pressure drop; moisture sensor face fouled with calcium deposits.

    Inspect emitters and flush drip line with citric acid solution. Check valve and sensor.
    Alert clears automatically when dripper performance recovers.
    """
  end

  defp format_body(:freeze_risk, site_id, zone_id, %{air_temp: temp}) do
    """
    Freeze risk: #{site_id} / #{zone_id}
    Air temperature: #{temp}°C — at or below freeze threshold.
    Watering has been suspended and a stop command sent to the valve.

    Action required: inspect exposed pipework and valves for ice damage.
    Watering resumes automatically when temperature rises above 4°C.
    """
  end

  defp format_body(:sensor_out_of_bounds, site_id, zone_id, %{fields: fields}) do
    """
    Out-of-bounds sensor reading: #{site_id} / #{zone_id}
    Affected fields: #{Enum.join(fields, ", ")}
    The bad reading has been discarded. Previous known-good value retained.

    Check sensor calibration and wiring. Alert clears automatically on next clean reading.
    """
  end

  defp format_body(:stuck_moisture, site_id, zone_id, %{moisture: pct, hours_unchanged: hours}) do
    """
    Moisture reading stuck: #{site_id} / #{zone_id}
    Moisture has read #{pct}% without significant change for #{hours} hours.
    Zone has not been watering during this period.

    Possible causes: sensor corrosion, salt buildup on capacitive plates, calibration drift.
    Check sensor and replace if needed. Alert clears when reading changes.
    """
  end

  defp format_body(type, site_id, zone_id, detail) do
    "Alert #{type} — #{site_id}/#{zone_id}\n#{inspect(detail)}"
  end

  defp format_heartbeat(%{
    total:        total,
    offline_count: offline,
    alert_count:  alert_count,
    offline_zones: offline_zones,
    alert_zones:  alert_zones,
    sent_at:      sent_at
  }) do
    offline_text = if offline == 0, do: "  None", else: Enum.map_join(offline_zones, "\n", &"  #{&1}")
    alert_text   = if alert_count == 0, do: "  None", else: Enum.map_join(alert_zones, "\n", &"  #{&1}")

    """
    NurseryHub is alive. Daily status report.

    Sent: #{DateTime.to_string(sent_at)} UTC

    Zones monitored:   #{total}
    Zones offline:     #{offline}
    Zones with alerts: #{alert_count}

    Offline zones:
    #{offline_text}

    Active alerts:
    #{alert_text}

    ----
    If you do not receive this email tomorrow at the same time, check that NurseryHub is running.
    """
  end

  defp log_alert(type, body) when type in [:valve_stuck_open, :critical_dry],
    do: Logger.error(body)
  defp log_alert(_type, body),
    do: Logger.warning(body)

  # ── Email ───────────────────────────────────────────────────────────────────

  defp send_email(subject, body) do
    from = Settings.get("email.from", "")
    to   = Settings.get("email.to", "")
    host = Settings.get("email.smtp_host", "")
    port = Settings.get("email.smtp_port", "587") |> String.to_integer()
    user = Settings.get("email.smtp_username", "")
    pass = Settings.get("email.smtp_password", "")

    if Enum.any?([from, to, host, user, pass], &(&1 == "")) do
      Logger.warning("[Alerting] Email credentials incomplete — skipping email")
      {:error, :not_configured}
    else
      message = build_mime(from, to, subject, body)
      opts = [relay: host, port: port, username: user, password: pass,
              tls: :always, auth: :always]

      case :gen_smtp_client.send_blocking({from, [to], message}, opts) do
        {:ok, _receipt} ->
          Logger.info("[Alerting] Email sent to #{to}")
          :ok
        {:error, reason, _detail} ->
          Logger.error("[Alerting] Email failed: #{inspect(reason)}")
          {:error, reason}
        {:error, reason} ->
          Logger.error("[Alerting] Email failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp build_mime(from, to, subject, body) do
    """
    From: #{from}\r
    To: #{to}\r
    Subject: #{subject}\r
    Content-Type: text/plain; charset=UTF-8\r
    \r
    #{body}
    """
  end

  # ── SMS (Twilio) ────────────────────────────────────────────────────────────

  defp send_sms(body) do
    sid   = Settings.get("sms.account_sid", "")
    token = Settings.get("sms.auth_token", "")
    from  = Settings.get("sms.from_number", "")
    to    = Settings.get("sms.to_number", "")

    if Enum.any?([sid, token, from, to], &(&1 == "")) do
      Logger.warning("[Alerting] SMS credentials incomplete — skipping SMS")
      {:error, :not_configured}
    else
      url      = "https://api.twilio.com/2010-04-01/Accounts/#{sid}/Messages.json"
      sms_body = URI.encode_query(%{"From" => from, "To" => to, "Body" => String.slice(body, 0, 160)})
      auth     = Base.encode64("#{sid}:#{token}")

      request = {
        String.to_charlist(url),
        [{~c"Authorization", String.to_charlist("Basic #{auth}")}],
        ~c"application/x-www-form-urlencoded",
        sms_body
      }

      case :httpc.request(:post, request, [{:ssl, [{:verify, :verify_none}]}], []) do
        {:ok, {{_, status, _}, _headers, _resp}} when status in 200..299 ->
          Logger.info("[Alerting] SMS sent to #{to}")
          :ok
        {:ok, {{_, status, _}, _headers, resp}} ->
          Logger.error("[Alerting] SMS failed (HTTP #{status}): #{resp}")
          {:error, {:http_error, status}}
        {:error, reason} ->
          Logger.error("[Alerting] SMS failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
