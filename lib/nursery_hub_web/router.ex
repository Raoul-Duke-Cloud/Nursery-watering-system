defmodule NurseryHubWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers

    # Dashboard login disabled for local development
    # Re-enable before deploying to VPS: plug Plug.BasicAuth, Application.compile_env!(:nursery_hub, :dashboard_auth)

    plug :put_root_layout, html: {NurseryHubWeb.Layouts, :root}
  end

  scope "/", NurseryHubWeb do
    pipe_through :browser

    live "/",                       DashboardLive, :overview
    live "/site/:site_id",          DashboardLive, :site
    live "/zone/:site_id/:zone_id", ZoneLive,      :detail

    get "/csv/:site_id/:zone_id",   CsvController, :download
  end

  # OTA firmware endpoints — no auth, accessed directly by ESP32s
  scope "/firmware", NurseryHubWeb do
    get "/version",                  FirmwareController, :version
    get "/esp32_plant_monitor.bin",  FirmwareController, :binary
  end
end
