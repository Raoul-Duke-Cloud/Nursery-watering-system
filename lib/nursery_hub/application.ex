defmodule NurseryHub.Application do
  @moduledoc """
  Starts everything in the correct order.

  Startup sequence:
    1. Database (Repo)        — must be up before anything tries to log data
    2. PubSub                 — zone processes broadcast updates through this
    3. Zone registry          — lookup table for zone processes
    4. Zone supervisor        — manages all zone processes
    5. MQTT connection        — starts receiving data from ESP32s
    6. Web endpoint           — serves the dashboard on port 4000
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    mqtt_host = Application.get_env(:nursery_hub, :mqtt_host, "localhost")
    mqtt_port = Application.get_env(:nursery_hub, :mqtt_port, 1883)

    Logger.info("NurseryHub starting...")

    children = [
      NurseryHub.Repo,
      {Phoenix.PubSub, name: NurseryHub.PubSub},
      {Registry, keys: :unique, name: NurseryHub.ZoneRegistry},
      {DynamicSupervisor, name: NurseryHub.ZoneSupervisor, strategy: :one_for_one},
      {NurseryHub.MQTTConnector, [host: mqtt_host, port: mqtt_port]},
      NurseryHubWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: NurseryHub.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
