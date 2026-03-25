defmodule NurseryHub.Repo.Migrations.AddDripperFields do
  use Ecto.Migration

  def change do
    alter table(:sensor_readings) do
      add :dripper_fault,    :boolean, default: false
      add :dripper_baseline, :float                    # avg moisture rise % over last 5 events
    end
  end
end
