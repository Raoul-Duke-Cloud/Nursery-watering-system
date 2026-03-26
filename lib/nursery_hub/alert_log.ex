defmodule NurseryHub.AlertLog do
  @moduledoc """
  Persistent log of every alert that has fired.

  Each row is one alert event — when it fired, what triggered it,
  and when it resolved (nil = still active).

  Written by Alerting.alert/4 on every alert.
  Resolved by ZoneServer when the condition clears (e.g. zone comes back online).
  """

  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset

  alias NurseryHub.Repo

  schema "alert_logs" do
    field :site_id,     :string
    field :zone_id,     :string
    field :alert_type,  :string
    field :detail,      :string       # JSON-encoded detail map
    field :resolved_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Write a new alert to the log."
  def log(site_id, zone_id, alert_type, detail) do
    %__MODULE__{}
    |> cast(%{
      site_id:    site_id,
      zone_id:    zone_id,
      alert_type: to_string(alert_type),
      detail:     Jason.encode!(detail)
    }, [:site_id, :zone_id, :alert_type, :detail])
    |> Repo.insert()
  end

  @doc "Mark all open alerts of a given type for a zone as resolved."
  def resolve(site_id, zone_id, alert_type) do
    from(a in __MODULE__,
      where: a.site_id    == ^site_id
         and a.zone_id    == ^zone_id
         and a.alert_type == ^to_string(alert_type)
         and is_nil(a.resolved_at)
    )
    |> Repo.update_all(set: [resolved_at: DateTime.utc_now()])
  end

  @doc "Most recent N alerts across all zones, newest first."
  def recent(limit \\ 200) do
    from(a in __MODULE__,
      order_by: [desc: a.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "All currently active (unresolved) alerts."
  def active do
    from(a in __MODULE__,
      where: is_nil(a.resolved_at),
      order_by: [desc: a.inserted_at]
    )
    |> Repo.all()
  end
end
