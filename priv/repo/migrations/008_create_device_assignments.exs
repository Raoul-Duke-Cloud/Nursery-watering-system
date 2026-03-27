defmodule NurseryHub.Repo.Migrations.CreateDeviceAssignments do
  use Ecto.Migration

  def change do
    create table(:device_assignments) do
      add :chip_id,     :string, null: false   # hardware MAC-derived ID from ESP32
      add :node_tag,    :string                # assigned asset tag e.g. "ESP-003"
      add :sensor_tags, :map                   # {"dht":"DHT-003","lux":"LUX-003","ir":"IR-003","moisture_0":"MST-009",...}
      timestamps()
    end

    create unique_index(:device_assignments, [:chip_id])
  end
end
