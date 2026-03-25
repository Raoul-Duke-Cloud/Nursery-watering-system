defmodule NurseryHub.Repo do
  use Ecto.Repo,
    otp_app: :nursery_hub,
    adapter: Ecto.Adapters.SQLite3
end
