defmodule NurseryHubWeb.CsvController do
  use NurseryHubWeb, :controller

  alias NurseryHub.{SensorReading, WateringEvent, AlertLog}

  def download(conn, %{"site_id" => site_id, "zone_id" => zone_id} = params) do
    from_str = Map.get(params, "from", Date.to_iso8601(Date.add(Date.utc_today(), -7)))
    to_str   = Map.get(params, "to",   Date.to_iso8601(Date.utc_today()))

    with {:ok, from_date} <- Date.from_iso8601(from_str),
         {:ok, to_date}   <- Date.from_iso8601(to_str) do
      from_dt = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")
      to_dt   = DateTime.new!(to_date,   ~T[23:59:59], "Etc/UTC")

      readings = SensorReading.range(site_id, zone_id, from_dt, to_dt)

      csv = [csv_header() | Enum.map(readings, &csv_row/1)]
            |> Enum.join("\n")

      filename = "#{site_id}_#{zone_id}_#{from_str}_#{to_str}.csv"

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, csv)
    else
      _ ->
        conn
        |> put_status(400)
        |> text("Invalid date format — use YYYY-MM-DD")
    end
  end

  # ── Watering events ────────────────────────────────────────────────────────

  def download_events(conn, %{"site_id" => site_id, "zone_id" => zone_id} = params) do
    from_str = Map.get(params, "from", Date.to_iso8601(Date.add(Date.utc_today(), -7)))
    to_str   = Map.get(params, "to",   Date.to_iso8601(Date.utc_today()))

    with {:ok, from_date} <- Date.from_iso8601(from_str),
         {:ok, to_date}   <- Date.from_iso8601(to_str) do
      from_dt = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")
      to_dt   = DateTime.new!(to_date,   ~T[23:59:59], "Etc/UTC")

      events = WateringEvent.range(site_id, zone_id, from_dt, to_dt)

      csv = [events_header() | Enum.map(events, &events_row/1)]
            |> Enum.join("\n")

      filename = "#{site_id}_#{zone_id}_events_#{from_str}_#{to_str}.csv"

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, csv)
    else
      _ ->
        conn
        |> put_status(400)
        |> text("Invalid date format — use YYYY-MM-DD")
    end
  end

  # ── Alert log ──────────────────────────────────────────────────────────────

  def download_logs(conn, _params) do
    logs = AlertLog.recent(500)

    csv = [logs_header() | Enum.map(logs, &logs_row/1)]
          |> Enum.join("\n")

    filename = "nursery_alert_log_#{Date.to_iso8601(Date.utc_today())}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, csv)
  end

  # ── Sensor readings CSV helpers ────────────────────────────────────────────

  defp csv_header do
    "time,moisture_%,vpd_kpa,air_temp_c,humidity_%,lux,leaf_temp_c,watering,mode,dripper_fault"
  end

  defp csv_row(r) do
    [
      Calendar.strftime(r.inserted_at, "%Y-%m-%d %H:%M:%S"),
      r.moisture,
      r.vpd && Float.round(r.vpd, 3),
      r.air_temp,
      r.humidity,
      r.lux && round(r.lux),
      r.leaf_temp,
      r.watering,
      r.mode,
      r.dripper_fault
    ]
    |> Enum.map(&if(is_nil(&1), do: "", else: to_string(&1)))
    |> Enum.join(",")
  end

  # ── Watering events CSV helpers ────────────────────────────────────────────

  defp events_header do
    "started_at,stopped_at,duration_s,trigger,moisture_before_%,moisture_after_%," <>
    "moisture_rise_%,vpd_at_start_kpa,lux_at_start,dripper_fault,dripper_baseline"
  end

  defp events_row(e) do
    [
      Calendar.strftime(e.started_at, "%Y-%m-%d %H:%M:%S"),
      e.stopped_at && Calendar.strftime(e.stopped_at, "%Y-%m-%d %H:%M:%S"),
      e.duration_ms && round(e.duration_ms / 1000),
      e.trigger,
      e.moisture_before,
      e.moisture_after,
      e.moisture_rise,
      e.vpd_at_start && Float.round(e.vpd_at_start, 3),
      e.lux_at_start && round(e.lux_at_start),
      e.dripper_fault,
      e.dripper_baseline && Float.round(e.dripper_baseline, 3)
    ]
    |> Enum.map(&if(is_nil(&1), do: "", else: to_string(&1)))
    |> Enum.join(",")
  end

  # ── Alert log CSV helpers ──────────────────────────────────────────────────

  defp logs_header do
    "time,site,zone,alert_type,detail,status,resolved_at"
  end

  defp logs_row(log) do
    [
      Calendar.strftime(log.inserted_at, "%Y-%m-%d %H:%M:%S"),
      log.site_id,
      log.zone_id,
      log.alert_type,
      log.detail || "",
      if(is_nil(log.resolved_at), do: "active", else: "resolved"),
      log.resolved_at && Calendar.strftime(log.resolved_at, "%Y-%m-%d %H:%M:%S")
    ]
    |> Enum.map(&if(is_nil(&1), do: "", else: to_string(&1)))
    |> Enum.join(",")
  end
end
