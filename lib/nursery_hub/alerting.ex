defmodule NurseryHub.Alerting do
  @moduledoc """
  Handles alerts from zone processes.

  Currently logs to the console. This is where you'd later add:
    - Email notifications
    - SMS (e.g. via Twilio)
    - Slack/Teams messages
    - Push notifications to a mobile app

  Alert types:
    :zone_offline     — zone stopped sending data
    :valve_stuck_open — valve open longer than safety limit
    :sensor_fault     — one or more sensors reporting failure
    :critical_dry     — moisture below emergency threshold
  """

  require Logger

  def alert(:zone_offline, site_id, zone_id, %{silent_for_minutes: mins}) do
    Logger.warning("""
    ⚠ ALERT: Zone offline
       Site: #{site_id}  Zone: #{zone_id}
       No data received for #{mins} minutes
       Check: WiFi at site, ESP32 power, 4G router
    """)
  end

  def alert(:valve_stuck_open, site_id, zone_id, %{open_for_seconds: secs}) do
    Logger.error("""
    🚨 ALERT: Valve may be stuck open
       Site: #{site_id}  Zone: #{zone_id}
       Valve open for #{secs} seconds — stop command sent
       Check: relay, solenoid valve, wiring
    """)
  end

  def alert(:sensor_fault, site_id, zone_id, %{failed_sensors: sensors, operating_mode: mode}) do
    sensor_list = Enum.join(sensors, ", ")
    Logger.warning("""
    ⚠ ALERT: Sensor fault
       Site: #{site_id}  Zone: #{zone_id}
       Failed sensors: #{sensor_list}
       Zone now running in mode: #{mode}
       Watering continues — check sensors when next on site
    """)
  end

  def alert(:critical_dry, site_id, zone_id, %{moisture: pct}) do
    Logger.error("""
    🚨 ALERT: Critically dry
       Site: #{site_id}  Zone: #{zone_id}
       Moisture at #{pct}% — ESP32 should be emergency watering
       If plants are not being watered, check valve and relay
    """)
  end

  def alert(type, site_id, zone_id, detail) do
    Logger.warning("ALERT: #{type} — #{site_id}/#{zone_id} — #{inspect(detail)}")
  end
end
