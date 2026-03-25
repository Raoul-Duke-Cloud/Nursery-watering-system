defmodule NurseryHubWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :nursery_hub

  @session_options [
    store: :cookie,
    key: "_nursery_hub_key",
    signing_salt: "nursery_salt"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :nursery_hub,
    gzip: false

  plug Plug.RequestId
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.Session, @session_options
  plug NurseryHubWeb.Router
end
