defmodule NurseryHubWeb.CsvController do
  use NurseryHubWeb, :controller

  alias NurseryHub.SensorReading

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
end
