defmodule NurseryHub.Repo.Migrations.CreateAlertLogs do
  use Ecto.Migration

  def change do
    create table(:alert_logs) do
      add :site_id,     :string, null: false
      add :zone_id,     :string, null: false
      add :alert_type,  :string, null: false   # "zone_offline", "valve_stuck_open", etc.
      add :detail,      :string                # JSON: extra info about the alert
      add :resolved_at, :utc_datetime          # nil = still active

      timestamps(type: :utc_datetime)
    end

    create index(:alert_logs, [:site_id, :zone_id])
    create index(:alert_logs, [:resolved_at])   # quickly find unresolved alerts
  end
end
