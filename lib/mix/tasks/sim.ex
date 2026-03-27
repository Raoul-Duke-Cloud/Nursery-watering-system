defmodule Mix.Tasks.Sim do
  @moduledoc """
  Publishes synthetic MQTT messages to the running NurseryHub server so you
  can see the dashboard populated without real hardware.

  Usage:
      mix sim

  Simulates 2 sites × 4 zones each = 8 zone cards on the dashboard.
  Data updates every 5 seconds with slowly drifting values.
  Press Ctrl+C to stop.

  The server must already be running (mix run -e ":timer.sleep(:infinity)").
  """

  use Mix.Task
  import Bitwise

  @client_id "nursery_sim"

  @sites [
    {"northcote", ["zone_a", "zone_b", "zone_c", "zone_d"]},
    {"fitzroy",   ["zone_a", "zone_b", "zone_c", "zone_d"]}
  ]

  # Simulated node (ESP32) asset tags — matches the physical labelling convention
  @zone_nodes %{
    {"northcote", "zone_a"} => "ESP-001",
    {"northcote", "zone_b"} => "ESP-001",
    {"northcote", "zone_c"} => "ESP-001",
    {"northcote", "zone_d"} => "ESP-001",
    {"fitzroy",   "zone_a"} => "ESP-002",
    {"fitzroy",   "zone_b"} => "ESP-002",
    {"fitzroy",   "zone_c"} => "ESP-002",
    {"fitzroy",   "zone_d"} => "ESP-002"
  }

  @zone_seeds %{
    {"northcote", "zone_a"} => %{moisture: 62, air_temp: 22.5, humidity: 58.0, lux: 4200, leaf_temp: 21.0, vpd: 0.82},
    {"northcote", "zone_b"} => %{moisture: 18, air_temp: 23.1, humidity: 55.0, lux: 4100, leaf_temp: 21.8, vpd: 0.91},
    {"northcote", "zone_c"} => %{moisture: 75, air_temp: 22.8, humidity: 60.0, lux: 3900, leaf_temp: 20.5, vpd: 0.74},
    {"northcote", "zone_d"} => %{moisture: 41, air_temp: 22.5, humidity: 58.0, lux: 4200, leaf_temp: 21.0, vpd: 0.82},
    {"fitzroy",   "zone_a"} => %{moisture: 55, air_temp: 24.0, humidity: 52.0, lux: 5800, leaf_temp: 23.5, vpd: 1.12},
    {"fitzroy",   "zone_b"} => %{moisture: 30, air_temp: 24.2, humidity: 51.0, lux: 5700, leaf_temp: 24.0, vpd: 1.18},
    {"fitzroy",   "zone_c"} => %{moisture: 88, air_temp: 23.8, humidity: 53.0, lux: 5900, leaf_temp: 23.2, vpd: 1.08},
    {"fitzroy",   "zone_d"} => %{moisture: 12, air_temp: 24.0, humidity: 52.0, lux: 5800, leaf_temp: 23.5, vpd: 1.12}
  }

  @impl Mix.Task
  def run(_args) do
    # Only need Jason for JSON encoding — start it without the full app
    Application.ensure_all_started(:jason)

    {:ok, socket} = connect()
    IO.puts("\nNurseryHub simulator connected to MQTT")
    IO.puts("Open http://localhost:4000 to see the dashboard")
    IO.puts("Press Ctrl+C to stop\n")

    loop(socket, @zone_seeds, 0)
  end

  # ── MQTT connection ────────────────────────────────────────────────────────

  defp connect do
    host     = Application.get_env(:nursery_hub, :mqtt_host,     "localhost")
    port     = Application.get_env(:nursery_hub, :mqtt_port,     1883)
    username = Application.get_env(:nursery_hub, :mqtt_username, "nursery_hub")
    password = Application.get_env(:nursery_hub, :mqtt_password, "")

    {:ok, socket} = :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false])
    send_connect(socket, username, password)
    {:ok, _connack} = :gen_tcp.recv(socket, 0, 5000)
    IO.puts("MQTT connected as #{@client_id}")
    {:ok, socket}
  end

  defp send_connect(socket, username, password) do
    client_id = @client_id

    client_id_len = byte_size(client_id)
    username_len  = byte_size(username)
    password_len  = byte_size(password)

    # CONNECT flags: username + password = 0b11000000 = 192
    connect_flags = 192
    # Protocol name "MQTT", level 4 (3.1.1), keepalive 60s
    payload =
      <<0, 4, "MQTT", 4, connect_flags, 0, 60>> <>
      <<0, client_id_len>> <> client_id <>
      <<0, username_len>>  <> username  <>
      <<0, password_len>>  <> password

    remaining = byte_size(payload)
    :gen_tcp.send(socket, <<1::4, 0::4, remaining, payload::binary>>)
  end

  defp publish(socket, topic, payload) do
    topic_bin    = topic
    topic_len    = byte_size(topic_bin)
    payload_bin  = payload
    remaining    = 2 + topic_len + byte_size(payload_bin)
    packet       = <<3::4, 0::4>> <> encode_remaining(remaining) <>
                   <<0, topic_len>> <> topic_bin <> payload_bin
    :gen_tcp.send(socket, packet)
  end

  # MQTT variable-length encoding
  defp encode_remaining(n) when n < 128, do: <<n>>
  defp encode_remaining(n) do
    <<(n &&& 0x7F) ||| 0x80>> <> encode_remaining(n >>> 7)
  end

  # ── Simulation loop ────────────────────────────────────────────────────────

  defp loop(socket, state, tick) do
    state = Enum.reduce(state, %{}, fn {{site_id, zone_id} = key, vals}, acc ->
      moisture  = clamp(vals.moisture  + jitter(1.5), 0, 100)
      air_temp  = clamp(vals.air_temp  + jitter(0.3), 15, 40)
      humidity  = clamp(vals.humidity  + jitter(0.8), 20, 95)
      lux       = clamp(vals.lux       + jitter(150),  0, 100_000)
      leaf_temp = clamp(vals.leaf_temp + jitter(0.2), 10, 45)
      vpd       = clamp(vals.vpd       + jitter(0.04), 0, 5)

      moisture = if key == {"northcote", "zone_d"} and tick > 5, do: clamp(moisture, 0, 15), else: moisture
      moisture = if key == {"northcote", "zone_b"}, do: clamp(moisture, 10, 25), else: moisture

      watering = key == {"fitzroy", "zone_b"} and rem(tick, 30) in 0..4

      mode = if key == {"fitzroy", "zone_d"} and rem(tick, 20) < 5, do: "no_vpd", else: "normal"

      payload = Jason.encode!(%{
        "node_id"   => Map.get(@zone_nodes, {site_id, zone_id}, "unknown"),
        "moisture"  => round(moisture),
        "air_temp"  => Float.round(air_temp, 1),
        "humidity"  => Float.round(humidity, 1),
        "lux"       => Float.round(lux, 0),
        "leaf_temp" => Float.round(leaf_temp, 1),
        "vpd"       => Float.round(vpd, 2),
        "watering"  => watering,
        "mode"      => mode,
        "sensor_ok" => %{"dht" => true, "bh1750" => true, "mlx" => true}
      })

      topic = "nursery/#{site_id}/#{zone_id}/data"
      publish(socket, topic, payload)

      Map.put(acc, key, %{vals | moisture: moisture, air_temp: air_temp,
        humidity: humidity, lux: lux, leaf_temp: leaf_temp, vpd: vpd})
    end)

    IO.write(".")
    Process.sleep(5_000)
    loop(socket, state, tick + 1)
  end

  defp jitter(max), do: ((:rand.uniform() * 2) - 1) * max
  defp clamp(val, lo, hi), do: val |> max(lo) |> min(hi)
end
