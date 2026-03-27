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

  @doc """
  Suggest the next sequential tag for a given prefix (e.g. "ESP", "MST").
  Scans all existing node_tag and sensor_tags values across all assignments
  to find the highest number in use, then returns the next one.

      DeviceAssignment.next_tag("ESP")        # => "ESP-003"
      DeviceAssignment.next_tags("MST", 4)    # => ["MST-009", "MST-010", "MST-011", "MST-012"]
  """
  def next_tag(prefix), do: format_tag(prefix, next_number(prefix))

  def next_tags(prefix, count) do
    base = next_number(prefix)
    Enum.map(0..(count - 1), &format_tag(prefix, base + &1))
  end

  defp next_number(prefix) do
    all_tag_values =
      Repo.all(__MODULE__)
      |> Enum.flat_map(fn a ->
        [a.node_tag | Map.values(a.sensor_tags || %{})]
      end)
      |> Enum.filter(&is_binary/1)

    all_tag_values
    |> Enum.filter(&String.starts_with?(&1, prefix <> "-"))
    |> Enum.map(fn tag ->
      case Integer.parse(String.replace_prefix(tag, prefix <> "-", "")) do
        {n, ""} -> n
        _       -> 0
      end
    end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp format_tag(prefix, n) do
    "#{prefix}-#{String.pad_leading(to_string(n), 3, "0")}"
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
