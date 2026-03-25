defmodule NurseryHub.MQTTHandler do
  @moduledoc """
  Handles incoming MQTT messages and routes them to the right zone process.

  When an ESP32 sends a sensor reading, it arrives here first.
  We work out which site and zone it's from (using the topic),
  make sure that zone has a running process, then pass the data to it.

  Topic format:  nursery/{site_id}/{zone_id}/data
  Example:       nursery/site_01/zone_a/data
  """

  use Tortoise311.Handler
  require Logger

  alias NurseryHub.{ZoneServer, ZoneSupervisor}

  def init(_opts), do: {:ok, %{}}

  # ── Sensor data message ─────────────────────────────────────────────────
  # Matches: nursery/{site_id}/{zone_id}/data
  def handle_message(["nursery", site_id, zone_id, "data"], payload, state) do
    case Jason.decode(payload) do
      {:ok, data} ->
        # Make sure this zone has a running process (start one if new)
        ZoneSupervisor.ensure_zone(site_id, zone_id)
        # Send the data to the zone's process
        ZoneServer.receive_data(site_id, zone_id, data)

      {:error, reason} ->
        Logger.warning("Bad JSON from #{site_id}/#{zone_id}: #{inspect(reason)}")
    end

    {:ok, state}
  end

  # ── Ignore any other topics ─────────────────────────────────────────────
  def handle_message(_topic, _payload, state), do: {:ok, state}
end
