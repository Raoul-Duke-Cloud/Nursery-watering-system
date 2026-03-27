defmodule NurseryHub.Repo.Migrations.AddSyncUniqueIndex do
  use Ecto.Migration

  def up do
    # Remove duplicate rows before adding the unique constraint.
    # Keeps the row with the highest rowid for each (site_id, zone_id, inserted_at).
    execute """
    DELETE FROM sensor_readings
    WHERE rowid NOT IN (
      SELECT MAX(rowid)
      FROM sensor_readings
      GROUP BY site_id, zone_id, inserted_at
    )
    """

    # De-duplicate synced readings from site Pis by (site_id, zone_id, inserted_at).
    # insert_all with on_conflict: :nothing relies on this constraint.
    create unique_index(:sensor_readings, [:site_id, :zone_id, :inserted_at],
             name: :sensor_readings_site_zone_time_unique)
  end

  def down do
    drop_if_exists index(:sensor_readings, [:site_id, :zone_id, :inserted_at],
                     name: :sensor_readings_site_zone_time_unique)
  end
end
