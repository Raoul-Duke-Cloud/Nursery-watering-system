defmodule NurseryHub.SensorReading do
  @moduledoc "Database schema for sensor readings."
  use Ecto.Schema
  import Ecto.Query

  alias NurseryHub.Repo

  schema "sensor_readings" do
    field :site_id,          :string
    field :zone_id,          :string
    field :moisture,         :integer
    field :lux,              :float
    field :leaf_temp,        :float
    field :air_temp,         :float
    field :humidity,         :float
    field :vpd,              :float
    field :watering,         :boolean
    field :mode,             :string
    field :sensor_ok,        :string    # stored as JSON string
    field :dripper_fault,    :boolean
    field :dripper_baseline, :float

    timestamps(type: :utc_datetime)
  end

  @doc "Save a reading from a zone to the database."
  def insert(site_id, zone_id, data) do
    %__MODULE__{}
    |> Ecto.Changeset.cast(%{
      site_id:          site_id,
      zone_id:          zone_id,
      moisture:         data["moisture"],
      lux:              data["lux"],
      leaf_temp:        data["leaf_temp"],
      air_temp:         data["air_temp"],
      humidity:         data["humidity"],
      vpd:              data["vpd"],
      watering:         data["watering"],
      mode:             data["mode"],
      sensor_ok:        Jason.encode!(data["sensor_ok"] || %{}),
      dripper_fault:    data["dripper_fault"],
      dripper_baseline: data["dripper_baseline"]
    }, [:site_id, :zone_id, :moisture, :lux, :leaf_temp, :air_temp,
        :humidity, :vpd, :watering, :mode, :sensor_ok,
        :dripper_fault, :dripper_baseline])
    |> Repo.insert()
  end

  @doc "Last N readings for a zone, most recent first."
  def recent(site_id, zone_id, limit \\ 48) do
    from(r in __MODULE__,
      where: r.site_id == ^site_id and r.zone_id == ^zone_id,
      order_by: [desc: r.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "Latest single reading per zone — used by the dashboard overview."
  def latest_per_zone do
    # Subquery: find the max id per site/zone combination
    latest_ids =
      from(r in __MODULE__,
        group_by: [r.site_id, r.zone_id],
        select: %{max_id: max(r.id)}
      )

    from(r in __MODULE__,
      join: l in subquery(latest_ids), on: r.id == l.max_id,
      order_by: [r.site_id, r.zone_id]
    )
    |> Repo.all()
  end
end
