defmodule NurseryHub.WateringEvent do
  @moduledoc """
  Records each individual watering event — when it started, stopped,
  what triggered it, and how much moisture change resulted.

  This is the primary training data for ML:
  - moisture_before + moisture_after → did the zone respond to watering?
  - duration_ms + moisture_rise → watering efficiency per zone
  - vpd_at_start + lux_at_start → environmental context for the decision
  - trigger → what caused the watering (for supervised learning)
  """

  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset

  alias NurseryHub.Repo

  schema "watering_events" do
    field :site_id,          :string
    field :zone_id,          :string
    field :trigger,          :string
    field :started_at,       :utc_datetime
    field :stopped_at,       :utc_datetime
    field :duration_ms,      :integer
    field :moisture_before,  :integer
    field :moisture_after,   :integer
    field :moisture_rise,    :integer
    field :vpd_at_start,     :float
    field :lux_at_start,     :float
    field :dripper_fault,    :boolean
    field :dripper_baseline, :float

    timestamps(type: :utc_datetime)
  end

  @doc "Open a new watering event when a drip starts."
  def open(site_id, zone_id, attrs) do
    %__MODULE__{}
    |> cast(Map.merge(%{site_id: site_id, zone_id: zone_id}, attrs),
        [:site_id, :zone_id, :trigger, :started_at, :moisture_before,
         :vpd_at_start, :lux_at_start, :dripper_baseline])
    |> Repo.insert()
  end

  @doc "Close an event when the drip stops — fills in duration and outcome."
  def close(id, attrs) do
    case Repo.get(__MODULE__, id) do
      nil -> {:error, :not_found}
      event ->
        event
        |> cast(attrs, [:stopped_at, :duration_ms, :moisture_after,
                        :moisture_rise, :dripper_fault])
        |> Repo.update()
    end
  end

  @doc "Last N watering events for a zone, most recent first."
  def recent(site_id, zone_id, limit \\ 20) do
    from(e in __MODULE__,
      where: e.site_id == ^site_id and e.zone_id == ^zone_id,
      order_by: [desc: e.started_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "All completed events for a zone — for ML export."
  def completed(site_id, zone_id) do
    from(e in __MODULE__,
      where: e.site_id == ^site_id and e.zone_id == ^zone_id
         and not is_nil(e.stopped_at)
         and not is_nil(e.moisture_rise),
      order_by: [asc: e.started_at]
    )
    |> Repo.all()
  end
end
