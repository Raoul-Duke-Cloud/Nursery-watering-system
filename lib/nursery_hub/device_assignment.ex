defmodule NurseryHub.DeviceAssignment do
  @moduledoc """
  Maps a physical ESP32 (identified by chip_id derived from its MAC address) to
  human-readable asset tags assigned through the Topology page.

  chip_id   — immutable hardware identity published by the firmware
  node_tag  — assigned label e.g. "ESP-003" (shown in topology + fault reports)
  sensor_tags — JSON map of assigned sensor labels:
    "dht"        → "DHT-003"   (shared per node — DHT22)
    "lux"        → "LUX-003"   (shared per node — BH1750)
    "ir"         → "IR-003"    (shared per node — MLX90614)
    "moisture_0" → "MST-009"   (per zone slot — index matches ZONE_IDS[] order)
    "moisture_1" → "MST-010"
    "moisture_2" → "MST-011"
    "moisture_3" → "MST-012"
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias NurseryHub.Repo

  schema "device_assignments" do
    field :chip_id,     :string
    field :node_tag,    :string
    field :sensor_tags, :map, default: %{}
    timestamps()
  end

  # ── Queries ──────────────────────────────────────────────────────────────

  @doc "Fetch assignment for a chip_id, or nil if unregistered."
  def get_by_chip_id(chip_id) when is_binary(chip_id) do
    Repo.get_by(__MODULE__, chip_id: chip_id)
  end

  @doc "All assignments indexed by chip_id — for fast lookup in topology rendering."
  def all_indexed do
    Repo.all(__MODULE__)
    |> Map.new(&{&1.chip_id, &1})
  end

  # ── Mutations ─────────────────────────────────────────────────────────────

  @doc "Create or update the assignment for a chip_id."
  def upsert(chip_id, attrs) do
    record = get_by_chip_id(chip_id) || %__MODULE__{chip_id: chip_id}
    record
    |> changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp changeset(record, attrs) do
    record
    |> cast(attrs, [:chip_id, :node_tag, :sensor_tags])
    |> validate_required([:chip_id])
  end
end
