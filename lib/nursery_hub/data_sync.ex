defmodule NurseryHub.DataSync do
  @moduledoc """
  Syncs locally-buffered sensor readings to the central server.

  Only active when :central_url is configured (i.e. this node is a site Pi).
  On the central server (no :central_url), init/1 returns :ignore and the
  process is not started.

  Every 60s:
    - Pings the central server health endpoint to check WAN
    - If WAN is up: pushes all readings since last_synced_at in batches of 100
    - If WAN is down: logs and keeps buffering locally

  On sync failure: exponential backoff up to 30 minutes.
  last_synced_at is persisted in the settings table so it survives restarts.
  """

  use GenServer
  require Logger
  import Ecto.Query
  alias NurseryHub.{Repo, SensorReading, Settings}

  @poll_ms        60_000
  @batch_size     100
  @max_backoff_ms 30 * 60 * 1_000

  # ── Public API ─────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns current sync status — wan_up, last_synced_at, pending_count."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # ── Callbacks ──────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    case Application.get_env(:nursery_hub, :central_url) do
      nil ->
        Logger.info("[DataSync] No :central_url configured — inactive on this node")
        :ignore

      central_url ->
        Logger.info("[DataSync] Starting — central: #{central_url}")
        schedule_poll(0)

        {:ok, %{
          central_url:    central_url,
          wan_up:         false,
          backoff_ms:     @poll_ms,
          last_synced_at: load_last_synced_at()
        }}
    end
  end

  @impl true
  def handle_info(:poll, state) do
    {wan_up, state} = check_wan(state)

    state =
      if wan_up do
        case sync(state) do
          {:ok, state}    -> state
          {:error, state} -> state
        end
      else
        state
      end

    schedule_poll(@poll_ms)
    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    pending = count_pending(state.last_synced_at)
    {:reply, Map.put(state, :pending_count, pending), state}
  end

  # ── WAN check ──────────────────────────────────────────────────────────────

  defp check_wan(state) do
    url = String.to_charlist("#{state.central_url}/api/sync/health")

    result =
      :httpc.request(:get, {url, []}, [{:timeout, 10_000}], [])

    case result do
      {:ok, {{_, status, _}, _, _}} when status in 200..299 ->
        unless state.wan_up, do: Logger.info("[DataSync] WAN up")
        {true, %{state | wan_up: true}}

      _ ->
        if state.wan_up, do: Logger.warning("[DataSync] WAN down — buffering locally")
        {false, %{state | wan_up: false}}
    end
  end

  # ── Sync ───────────────────────────────────────────────────────────────────

  defp sync(state) do
    readings = fetch_unsynced(state.last_synced_at)

    if readings == [] do
      {:ok, state}
    else
      Logger.info("[DataSync] Pushing #{length(readings)} readings to central")

      case push_in_batches(readings, state.central_url) do
        {:ok, last_ts} ->
          save_last_synced_at(last_ts)
          Logger.info("[DataSync] Sync complete")
          {:ok, %{state | last_synced_at: last_ts, backoff_ms: @poll_ms}}

        {:error, reason} ->
          backoff = min(state.backoff_ms * 2, @max_backoff_ms)
          Logger.error("[DataSync] Sync failed (#{inspect(reason)}) — retry in #{div(backoff, 1_000)}s")
          {:error, %{state | backoff_ms: backoff}}
      end
    end
  end

  defp push_in_batches(readings, central_url) do
    readings
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce_while({:ok, nil}, fn batch, _acc ->
      case push_batch(batch, central_url) do
        :ok ->
          last_ts = batch |> List.last() |> Map.fetch!(:inserted_at)
          {:cont, {:ok, last_ts}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp push_batch(batch, central_url) do
    payload =
      Jason.encode!(Enum.map(batch, fn r ->
        %{
          site_id:          r.site_id,
          zone_id:          r.zone_id,
          inserted_at:      DateTime.to_iso8601(r.inserted_at),
          moisture:         r.moisture,
          lux:              r.lux,
          leaf_temp:        r.leaf_temp,
          air_temp:         r.air_temp,
          humidity:         r.humidity,
          vpd:              r.vpd,
          watering:         r.watering,
          mode:             r.mode,
          sensor_ok:        r.sensor_ok,
          dripper_fault:    r.dripper_fault,
          dripper_baseline: r.dripper_baseline
        }
      end))

    url     = String.to_charlist("#{central_url}/api/sync/readings")
    headers = [{~c"Content-Type", ~c"application/json"}]

    case :httpc.request(:post, {url, headers, ~c"application/json", payload},
                        [{:timeout, 30_000}, {:ssl, [{:verify, :verify_none}]}], []) do
      {:ok, {{_, status, _}, _, _}} when status in 200..299 ->
        :ok

      {:ok, {{_, status, _}, _, body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp fetch_unsynced(nil) do
    from(r in SensorReading, order_by: [asc: r.inserted_at])
    |> Repo.all()
  end

  defp fetch_unsynced(since) do
    from(r in SensorReading,
      where: r.inserted_at > ^since,
      order_by: [asc: r.inserted_at]
    )
    |> Repo.all()
  end

  defp count_pending(nil),  do: Repo.aggregate(SensorReading, :count)
  defp count_pending(since) do
    from(r in SensorReading, where: r.inserted_at > ^since)
    |> Repo.aggregate(:count)
  end

  defp load_last_synced_at do
    case Settings.get("datasync.last_synced_at") do
      nil -> nil
      ts  ->
        case DateTime.from_iso8601(ts) do
          {:ok, dt, _} -> dt
          _            -> nil
        end
    end
  end

  defp save_last_synced_at(nil), do: :ok
  defp save_last_synced_at(ts) do
    Settings.put("datasync.last_synced_at", DateTime.to_iso8601(ts))
  end

  defp schedule_poll(delay_ms) do
    Process.send_after(self(), :poll, delay_ms)
  end
end
