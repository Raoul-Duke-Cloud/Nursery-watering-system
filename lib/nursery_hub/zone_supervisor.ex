defmodule NurseryHub.ZoneSupervisor do
  @moduledoc """
  Manages zone processes — starts new ones, and restarts crashed ones.

  Each zone (one ESP32) gets its own ZoneServer process.
  This supervisor keeps track of them all.

  If a zone process crashes (e.g. due to unexpected data), BEAM restarts
  it automatically here — no manual intervention needed.
  """

  require Logger

  @doc """
  Ensures a ZoneServer process is running for the given site/zone.
  If it already exists, does nothing. If it's new, starts one.
  Called automatically when a message arrives from a zone we haven't seen before.
  """
  def ensure_zone(site_id, zone_id) do
    case lookup(site_id, zone_id) do
      {:ok, _pid} ->
        # Already running — nothing to do
        :ok

      :not_found ->
        Logger.info("New zone discovered: #{site_id}/#{zone_id} — starting process")
        start_zone(site_id, zone_id)
    end
  end

  @doc """
  Returns the PID of a zone process, or :not_found.
  """
  def lookup(site_id, zone_id) do
    case Registry.lookup(NurseryHub.ZoneRegistry, {site_id, zone_id}) do
      [{pid, _}] -> {:ok, pid}
      []         -> :not_found
    end
  end

  @doc """
  Returns a list of all currently active zones as {site_id, zone_id} pairs.
  """
  def all_zones do
    Registry.select(NurseryHub.ZoneRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Returns all zones belonging to a specific site.
  """
  def zones_for_site(site_id) do
    all_zones()
    |> Enum.filter(fn {sid, _} -> sid == site_id end)
  end

  # ── Private ─────────────────────────────────────────────────────────────

  defp start_zone(site_id, zone_id) do
    child_spec = {NurseryHub.ZoneServer, {site_id, zone_id}}

    case DynamicSupervisor.start_child(NurseryHub.ZoneSupervisor, child_spec) do
      {:ok, _pid} ->
        Logger.info("Started zone process: #{site_id}/#{zone_id}")
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to start zone #{site_id}/#{zone_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
