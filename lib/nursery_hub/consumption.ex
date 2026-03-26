defmodule NurseryHub.Consumption do
  @moduledoc """
  Estimates water and electricity consumption from watering event data.

  Calculations use configurable defaults stored in Settings:
    consumption.flow_rate_lph — total zone dripper output in litres/hour
    consumption.valve_watts   — solenoid valve power draw in watts

  Both can be changed in System Settings → Consumption Defaults.

  Formulas:
    litres = duration_ms / 3_600_000 * flow_rate_lph
    wh     = duration_ms / 3_600_000 * valve_watts
  """

  alias NurseryHub.Settings

  @default_flow_rate_lph 2.0
  @default_valve_watts   7.0

  # ── Public API ─────────────────────────────────────────────────────────────

  @doc """
  Annotates a list of WateringEvent structs with :estimated_litres and
  :estimated_wh, returning plain maps so the extra keys are accessible.
  Reads current flow rate and wattage from Settings once per call.
  """
  def annotate(events) do
    flow_rate = flow_rate_lph()
    watts     = valve_watts()

    Enum.map(events, fn e ->
      Map.from_struct(e)
      |> Map.put(:estimated_litres, estimate_litres(e.duration_ms, flow_rate))
      |> Map.put(:estimated_wh,     estimate_wh(e.duration_ms, watts))
    end)
  end

  @doc """
  Sums estimated_litres and estimated_wh across an already-annotated event list.
  Returns {total_litres, total_wh}, both rounded.
  """
  def totals(events) do
    litres = events |> Enum.map(& &1.estimated_litres) |> sum_floats()
    wh     = events |> Enum.map(& &1.estimated_wh)     |> sum_floats()
    {Float.round(litres, 2), Float.round(wh, 2)}
  end

  @doc "Current flow rate setting in L/hr (reads from Settings)."
  def flow_rate_lph do
    Settings.get("consumption.flow_rate_lph", "#{@default_flow_rate_lph}")
    |> parse_float(@default_flow_rate_lph)
  end

  @doc "Current valve wattage setting (reads from Settings)."
  def valve_watts do
    Settings.get("consumption.valve_watts", "#{@default_valve_watts}")
    |> parse_float(@default_valve_watts)
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp estimate_litres(nil, _), do: nil
  defp estimate_litres(duration_ms, flow_rate),
    do: Float.round(duration_ms / 3_600_000 * flow_rate, 2)

  defp estimate_wh(nil, _), do: nil
  defp estimate_wh(duration_ms, watts),
    do: Float.round(duration_ms / 3_600_000 * watts, 2)

  defp sum_floats(list), do: list |> Enum.reject(&is_nil/1) |> Enum.reduce(0.0, &+/2)

  defp parse_float(str, default) do
    case Float.parse(to_string(str)) do
      {v, _} -> v
      :error  -> default
    end
  end
end
