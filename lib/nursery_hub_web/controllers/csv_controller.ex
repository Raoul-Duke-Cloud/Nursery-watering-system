defmodule NurseryHubWeb.CsvController do
  use NurseryHubWeb, :controller

  alias NurseryHub.{SensorReading, WateringEvent, AlertLog, ZoneSupervisor, ZoneServer}

  # ── Dashboard snapshot CSV ─────────────────────────────────────────────────

  def download_dashboard(conn, params) do
    zones = load_all_zones()

    filtered =
      zones
      |> filter_by_site(params["site"])
      |> filter_by_zone(params["zone"])
      |> filter_by_status(params["status"])
      |> filter_by_mode(params["mode"])
      |> filter_by_range(:moisture, params["moisture_min"], params["moisture_max"])
      |> filter_by_range(:air_temp, params["temp_min"],     params["temp_max"])
      |> filter_by_range(:vpd,      params["vpd_min"],      params["vpd_max"])
      |> filter_by_range(:lux,      params["lux_min"],      params["lux_max"])
      |> Enum.sort_by(&{&1.site_id, &1.zone_id})

    header = "site,zone,status,moisture_%,air_temp_c,vpd_kpa,lux,mode,last_seen"

    rows = Enum.map(filtered, fn z ->
      [
        z.site_id,
        z.zone_id,
        dashboard_zone_status(z),
        z.moisture,
        z.air_temp,
        z.vpd && Float.round(z.vpd, 3),
        z.lux && round(z.lux),
        z.mode,
        z.last_seen && Calendar.strftime(z.last_seen, "%Y-%m-%d %H:%M:%S")
      ]
      |> Enum.map(&if(is_nil(&1), do: "", else: to_string(&1)))
      |> Enum.join(",")
    end)

    csv      = Enum.join([header | rows], "\n")
    filename = "nursery_dashboard_#{Date.to_iso8601(Date.utc_today())}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, csv)
  end

  defp load_all_zones do
    db_zones =
      SensorReading.latest_per_zone()
      |> Enum.reduce(%{}, fn reading, acc ->
        zone = %ZoneServer{
          site_id:   reading.site_id,
          zone_id:   reading.zone_id,
          last_seen: reading.inserted_at,
          moisture:  reading.moisture,
          lux:       reading.lux,
          leaf_temp: reading.leaf_temp,
          air_temp:  reading.air_temp,
          humidity:  reading.humidity,
          vpd:       reading.vpd,
          watering:  false,
          mode:      reading.mode || "unknown",
          sensor_ok: %{},
          alerts:    [:offline]
        }
        Map.put(acc, {zone.site_id, zone.zone_id}, zone)
      end)

    ZoneSupervisor.all_zones()
    |> Enum.reduce(db_zones, fn {site_id, zone_id}, acc ->
      case ZoneServer.state(site_id, zone_id) do
        state when is_struct(state) -> Map.put(acc, {site_id, zone_id}, state)
        _                           -> acc
      end
    end)
    |> Map.values()
  end

  defp filter_by_site(zones, nil),    do: zones
  defp filter_by_site(zones, "all"),  do: zones
  defp filter_by_site(zones, site),   do: Enum.filter(zones, &(&1.site_id == site))

  defp filter_by_zone(zones, nil),   do: zones
  defp filter_by_zone(zones, ""),    do: zones
  defp filter_by_zone(zones, query), do: Enum.filter(zones, &String.contains?(&1.zone_id, query))

  defp filter_by_status(zones, nil),       do: zones
  defp filter_by_status(zones, "all"),     do: zones
  defp filter_by_status(zones, "online"),  do: Enum.filter(zones, &(:offline not in &1.alerts and not &1.watering))
  defp filter_by_status(zones, "offline"), do: Enum.filter(zones, &(:offline in &1.alerts))
  defp filter_by_status(zones, "watering"),do: Enum.filter(zones, & &1.watering)
  defp filter_by_status(zones, "alert"),   do: Enum.filter(zones, &(&1.alerts != [] and :offline not in &1.alerts))
  defp filter_by_status(zones, _),         do: zones

  defp filter_by_mode(zones, nil),    do: zones
  defp filter_by_mode(zones, "all"),  do: zones
  defp filter_by_mode(zones, mode),   do: Enum.filter(zones, &(&1.mode == mode))

  defp filter_by_range(zones, _field, nil, nil),  do: zones
  defp filter_by_range(zones, _field, "",  ""),   do: zones
  defp filter_by_range(zones, field, min_s, max_s) do
    Enum.filter(zones, fn zone ->
      val = Map.get(zone, field)
      if is_nil(val) do
        false
      else
        min_ok = is_nil(min_s) or min_s == "" or val >= parse_csv_number(min_s)
        max_ok = is_nil(max_s) or max_s == "" or val <= parse_csv_number(max_s)
        min_ok and max_ok
      end
    end)
  end

  defp parse_csv_number(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp dashboard_zone_status(zone) do
    cond do
      :offline in zone.alerts -> "offline"
      zone.watering            -> "watering"
      zone.alerts != []        -> "alert"
      true                     -> "online"
    end
  end

  # ── Sensor readings CSV ────────────────────────────────────────────────────

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
