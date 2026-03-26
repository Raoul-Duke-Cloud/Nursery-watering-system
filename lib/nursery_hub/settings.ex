defmodule NurseryHub.Settings do
  @moduledoc """
  Key/value settings store backed by SQLite.

  All values are stored as strings. Use get/2 with a default for safe reads.

  Keys are namespaced by convention:
    email.*   — email alert configuration
    sms.*     — SMS alert configuration
    ota.*     — OTA firmware configuration
    alerts.*  — which alert types trigger which delivery methods
  """

  import Ecto.Query
  alias NurseryHub.Repo

  schema_mod = __MODULE__

  defmodule Entry do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:key, :string, []}
    schema "settings" do
      field :value, :string
      timestamps(type: :utc_datetime)
    end

    def changeset(entry, attrs) do
      cast(entry, attrs, [:key, :value])
    end
  end

  # ── Defaults ───────────────────────────────────────────────────────────────

  @defaults %{
    # Email
    "email.enabled"       => "false",
    "email.smtp_host"     => "",
    "email.smtp_port"     => "587",
    "email.smtp_username" => "",
    "email.smtp_password" => "",
    "email.from"          => "",
    "email.to"            => "",

    # SMS (Twilio)
    "sms.enabled"         => "false",
    "sms.account_sid"     => "",
    "sms.auth_token"      => "",
    "sms.from_number"     => "",
    "sms.to_number"       => "",

    # Alert routing — comma-separated list of delivery methods ("email", "sms")
    "alerts.zone_offline"     => "email",
    "alerts.valve_stuck_open" => "email,sms",
    "alerts.sensor_fault"     => "email",
    "alerts.critical_dry"     => "email,sms",

    # OTA
    "ota.firmware_version"    => "42",

    # Consumption estimates
    "consumption.flow_rate_lph" => "2.0",
    "consumption.valve_watts"   => "7.0"
  }

  # ── Public API ─────────────────────────────────────────────────────────────

  @doc "Get a setting value. Returns the default if not set in the database."
  def get(key, fallback \\ nil) do
    case Repo.get(Entry, key) do
      nil   -> Map.get(@defaults, key, fallback)
      entry -> entry.value
    end
  end

  @doc "Get all settings as a map, merging defaults with database values."
  def all do
    db_values =
      Repo.all(Entry)
      |> Enum.into(%{}, &{&1.key, &1.value})

    Map.merge(@defaults, db_values)
  end

  @doc "Save a setting. Creates or updates."
  def put(key, value) do
    entry = Repo.get(Entry, key) || %Entry{key: key}
    entry
    |> Entry.changeset(%{key: key, value: to_string(value)})
    |> Repo.insert_or_update()
  end

  @doc "Save multiple settings at once from a map."
  def put_all(map) do
    Enum.each(map, fn {k, v} -> put(k, v) end)
  end

  @doc "Convenience — returns true if a boolean setting is \"true\"."
  def enabled?(key), do: get(key) == "true"

  @doc "Returns the delivery methods for an alert type as a list of strings."
  def alert_delivery(alert_type) do
    get("alerts.#{alert_type}", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end
end
