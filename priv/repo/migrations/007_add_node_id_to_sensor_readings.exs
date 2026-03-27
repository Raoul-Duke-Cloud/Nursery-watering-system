defmodule NurseryHub.Repo.Migrations.AddNodeIdToSensorReadings do
  use Ecto.Migration

  def change do
    alter table(:sensor_readings) do
      add :node_id, :string
    end
  end
end
