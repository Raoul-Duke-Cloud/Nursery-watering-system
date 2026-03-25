defmodule NurseryHub.MQTTConnector do
  @moduledoc """
  Starts the MQTT connection and subscribes to all sensor topics.

  Connects to Mosquitto using the credentials set in config/config.exs.
  The broker must be configured to require authentication — see SECURITY_SETUP.md.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    host     = Keyword.get(opts, :host, "localhost")
    port     = Keyword.get(opts, :port, 1883)
    username = Application.get_env(:nursery_hub, :mqtt_username, "")
    password = Application.get_env(:nursery_hub, :mqtt_password, "")

    tortoise_opts = [
      client_id: "nursery_hub_server",
      handler:   {NurseryHub.MQTTHandler, []},
      server:    {Tortoise311.Transport.Tcp, host: to_charlist(host), port: port},
      user_name: username,
      password:  password,
      subscriptions: [{"nursery/#", 0}]
    ]

    case Tortoise311.Supervisor.start_child(tortoise_opts) do
      {:ok, _pid} ->
        Logger.info("MQTT connected to #{host}:#{port} as #{username}")
        {:ok, %{host: host, port: port}}

      {:error, reason} ->
        Logger.error("MQTT connection failed: #{inspect(reason)}")
        {:ok, %{host: host, port: port}}
    end
  end
end
