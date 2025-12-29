defmodule CrucibleHarness.Collector.ComparisonMatrix do
  @moduledoc """
  Generates comparison matrices for visualizing results across all conditions.
  """

  @doc """
  Generates a comparison matrix for a specific metric.
  """
  def generate(analysis, metric) do
    conditions = extract_conditions(analysis.comparisons)

    matrix =
      for c1 <- conditions do
        row =
          for c2 <- conditions do
            if c1 == c2 do
              %{type: :self, value: nil}
            else
              comp = find_comparison(analysis.comparisons, c1, c2)

              if comp do
                metric_result = comp.metrics[metric]

                %{
                  type: :comparison,
                  mean_diff: metric_result.mean_diff,
                  p_value: metric_result.p_value,
                  significant: metric_result.significant,
                  effect_size: metric_result.effect_size
                }
              else
                %{type: :missing, value: nil}
              end
            end
          end

        {c1, row}
      end
      |> Map.new()

    %{
      metric: metric,
      conditions: conditions,
      matrix: matrix
    }
  end

  defp extract_conditions(comparisons) do
    comparisons
    |> Enum.flat_map(fn comp ->
      [elem(comp.pair, 0), elem(comp.pair, 1)]
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp find_comparison(comparisons, c1, c2) do
    Enum.find(comparisons, fn comp ->
      comp.pair == {c1, c2} or comp.pair == {c2, c1}
    end)
  end
end
