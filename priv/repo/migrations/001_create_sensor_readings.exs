defmodule NurseryHub.Repo.Migrations.CreateSensorReadings do
  use Ecto.Migration

  def change do
    create table(:sensor_readings) do
      add :site_id,   :string,  null: false
      add :zone_id,   :string,  null: false
      add :moisture,  :integer            # soil moisture %
      add :lux,       :float              # light level
      add :leaf_temp, :float              # leaf temperature °C
      add :air_temp,  :float              # air temperature °C
      add :humidity,  :float              # relative humidity %
      add :vpd,       :float              # vapour pressure deficit kPa
      add :watering,  :boolean            # valve open at time of reading
      add :mode,      :string             # operating mode (normal/no_vpd/etc)
      add :sensor_ok, :string            # JSON: which sensors were healthy

      timestamps(type: :utc_datetime)     # inserted_at, updated_at
    end

    # Index for fast queries: "give me the last 24h for site_01/zone_a"
    create index(:sensor_readings, [:site_id, :zone_id, :inserted_at])
  end
end
