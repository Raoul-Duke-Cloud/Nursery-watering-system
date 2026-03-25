defmodule NurseryHubWeb.FirmwareController do
  @moduledoc """
  Serves OTA firmware updates to ESP32s.

  ESP32s check /firmware/version on boot. If the server version is higher
  than their current firmware, they download /firmware/esp32_plant_monitor.bin
  and flash themselves, then reboot.

  To deploy a new firmware version:
    1. Compile in Arduino IDE: Sketch → Export Compiled Binary
    2. Copy the .bin file to priv/static/firmware/esp32_plant_monitor.bin
    3. Update :firmware_version in config/config.exs
    4. Restart NurseryHub — ESP32s will update on next boot
  """

  use NurseryHubWeb, :controller

  @firmware_dir Application.app_dir(:nursery_hub, "priv/static/firmware")

  def version(conn, _params) do
    version = Application.get_env(:nursery_hub, :firmware_version, 0)
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, to_string(version))
  end

  def binary(conn, _params) do
    bin_path = Path.join(@firmware_dir, "esp32_plant_monitor.bin")

    if File.exists?(bin_path) do
      conn
      |> put_resp_content_type("application/octet-stream")
      |> send_file(200, bin_path)
    else
      conn
      |> send_resp(404, "No firmware binary available")
    end
  end
end
