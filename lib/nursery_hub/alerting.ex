defmodule NurseryHub.Alerting do
  @moduledoc """
  Handles alerts from zone processes.

  Reads delivery routing and credentials from Settings, then sends via
  email (gen_smtp) and/or SMS (Twilio) as configured.

  Alert types:
    :zone_offline     — zone stopped sending data
    :valve_stuck_open — valve open longer than safety limit
    :sensor_fault     — one or more sensors reporting failure
    :critical_dry     — moisture below emergency threshold
  """

  require Logger
  alias NurseryHub.Settings

  def alert(type, site_id, zone_id, detail) do
    subject = format_subject(type, site_id, zone_id)
    body    = format_body(type, site_id, zone_id, detail)

    log_alert(type, body)

    delivery = Settings.alert_delivery(Atom.to_string(type))

    if "email" in delivery and Settings.enabled?("email.enabled") do
      send_email(subject, body)
    end

    if "sms" in delivery and Settings.enabled?("sms.enabled") do
      send_sms(body)
    end
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

  defp format_body(type, site_id, zone_id, detail) do
    "Alert #{type} — #{site_id}/#{zone_id}\n#{inspect(detail)}"
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
    else
      message = build_mime(from, to, subject, body)
      opts = [relay: host, port: port, username: user, password: pass,
              tls: :always, auth: :always]

      case :gen_smtp_client.send_blocking({from, [to], message}, opts) do
        {:ok, _receipt} ->
          Logger.info("[Alerting] Email sent to #{to}")
        {:error, reason, _detail} ->
          Logger.error("[Alerting] Email failed: #{inspect(reason)}")
        {:error, reason} ->
          Logger.error("[Alerting] Email failed: #{inspect(reason)}")
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
        {:ok, {{_, status, _}, _headers, resp}} ->
          Logger.error("[Alerting] SMS failed (HTTP #{status}): #{resp}")
        {:error, reason} ->
          Logger.error("[Alerting] SMS failed: #{inspect(reason)}")
      end
    end
  end
end
