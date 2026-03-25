defmodule NurseryHub.Repo.Migrations.CreateWateringEvents do
  use Ecto.Migration

  def change do
    create table(:watering_events) do
      add :site_id,          :string,  null: false
      add :zone_id,          :string,  null: false
      add :trigger,          :string,  null: false  # "moisture_low", "emergency", "remote", "scheduled"
      add :started_at,       :utc_datetime, null: false
      add :stopped_at,       :utc_datetime           # nil = still running
      add :duration_ms,      :integer                # actual duration in ms
      add :moisture_before,  :integer                # moisture % when drip started
      add :moisture_after,   :integer                # moisture % checked after drip (DRIP_CHECK_DELAY)
      add :moisture_rise,    :integer                # moisture_after - moisture_before
      add :vpd_at_start,     :float                  # VPD when drip started
      add :lux_at_start,     :float                  # light level when drip started
      add :dripper_fault,    :boolean, default: false # fault detected for this event
      add :dripper_baseline, :float                  # baseline at time of event

      timestamps(type: :utc_datetime)
    end

    create index(:watering_events, [:site_id, :zone_id, :started_at])
    create index(:watering_events, [:site_id, :zone_id, :stopped_at])
  end
end
