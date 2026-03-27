defmodule NurseryHubWeb.SyncController do
  @moduledoc """
  Sync API — accepts batches of sensor readings from site Pi DataSync modules.

  Endpoints:
    GET  /api/sync/health    — health check; DataSync pings this to detect WAN
    POST /api/sync/readings  — accepts a batch of readings, de-duplicates by
                               (site_id, zone_id, inserted_at)
  """

  use NurseryHubWeb, :controller

  alias NurseryHub.{Repo, SensorReading}
  require Logger

  def health(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def readings(conn, params) do
    if authorized?(conn) do
      do_readings(conn, params)
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "invalid or missing X-Sync-Key"})
    end
  end

  defp do_readings(conn, %{"readings" => readings}) when is_list(readings) do
    records = Enum.flat_map(readings, &parse_reading/1)
    invalid = length(readings) - length(records)

    {accepted, _} =
      Repo.insert_all(SensorReading, records,
        on_conflict: :nothing,
        conflict_target: [:site_id, :zone_id, :inserted_at]
      )

    duplicates = length(records) - accepted

    if invalid > 0 do
      Logger.warning("[SyncAPI] #{invalid} readings skipped (missing site_id/zone_id/inserted_at)")
    end

    Logger.info("[SyncAPI] Received #{length(readings)} — accepted #{accepted}, duplicates #{duplicates}, invalid #{invalid}")

    json(conn, %{accepted: accepted, duplicates: duplicates})
  end

  defp do_readings(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: ~s(expected {"readings": [...]})})
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp authorized?(conn) do
    expected = Application.get_env(:nursery_hub, :sync_api_key, "")
    provided = conn |> get_req_header("x-sync-key") |> List.first()
    expected != "" and provided == expected
  end

  defp parse_reading(r) do
    with site_id  when is_binary(site_id) <- r["site_id"],
         zone_id  when is_binary(zone_id) <- r["zone_id"],
         ts_str   when is_binary(ts_str)  <- r["inserted_at"],
         {:ok, dt, _}                     <- DateTime.from_iso8601(ts_str) do
      [%{
        site_id:          site_id,
        zone_id:          zone_id,
        inserted_at:      dt,
        updated_at:       dt,
        moisture:         r["moisture"],
        lux:              r["lux"],
        leaf_temp:        r["leaf_temp"],
        air_temp:         r["air_temp"],
        humidity:         r["humidity"],
        vpd:              r["vpd"],
        watering:         r["watering"],
        mode:             r["mode"],
        sensor_ok:        r["sensor_ok"],
        dripper_fault:    r["dripper_fault"],
        dripper_baseline: r["dripper_baseline"]
      }]
    else
      _ -> []
    end
  end
end
