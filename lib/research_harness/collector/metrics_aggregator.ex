defmodule CrucibleHarness.Collector.MetricsAggregator do
  @moduledoc """
  Aggregates raw experiment results into statistical summaries.
  """

  @doc """
  Aggregates results by condition and computes summary statistics.
  """
  def aggregate(results, config) do
    results
    |> filter_successful_results()
    |> group_by_condition()
    |> Enum.map(fn {condition, condition_results} ->
      compute_statistics(condition, condition_results, config.metrics)
    end)
  end

  defp filter_successful_results(results) do
    Enum.filter(results, fn result ->
      is_map(result.result) and not match?({:error, _}, result.result)
    end)
  end

  defp group_by_condition(results) do
    Enum.group_by(results, & &1.condition)
  end

  defp compute_statistics(condition, condition_results, metric_names) do
    metrics = extract_metrics(condition_results, metric_names)

    metric_stats =
      Enum.map(metrics, fn {metric_name, values} ->
        {metric_name, compute_metric_stats(values)}
      end)
      |> Map.new()

    %{
      condition: condition,
      n: length(condition_results),
      metrics: metric_stats
    }
  end

  defp extract_metrics(results, metric_names) do
    Enum.map(metric_names, fn metric_name ->
      values =
        Enum.map(results, fn result ->
          get_metric_value(result.result, metric_name)
        end)
        |> Enum.filter(&(&1 != nil))

      {metric_name, values}
    end)
    |> Map.new()
  end

  defp get_metric_value(result, metric_name) do
    # Try to get metric from result map
    Map.get(result, metric_name)
  end

  defp compute_metric_stats(values) when length(values) == 0 do
    %{
      mean: nil,
      std: nil,
      median: nil,
      min: nil,
      max: nil,
      p25: nil,
      p75: nil,
      p95: nil,
      p99: nil,
      values: []
    }
  end

  defp compute_metric_stats(values) do
    sorted = Enum.sort(values)

    %{
      mean: mean(values),
      std: std_dev(values),
      median: percentile(sorted, 50),
      min: Enum.min(values),
      max: Enum.max(values),
      p25: percentile(sorted, 25),
      p75: percentile(sorted, 75),
      p95: percentile(sorted, 95),
      p99: percentile(sorted, 99),
      values: values
    }
  end

  defp mean([]), do: nil

  defp mean(values) do
    Enum.sum(values) / length(values)
  end

  defp std_dev([]), do: nil
  defp std_dev([_]), do: 0.0

  defp std_dev(values) do
    avg = mean(values)

    variance =
      Enum.map(values, fn x -> :math.pow(x - avg, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values) - 1)

    :math.sqrt(variance)
  end

  defp percentile([], _), do: nil

  defp percentile(sorted_values, p) do
    n = length(sorted_values)
    index = p / 100 * (n - 1)
    lower_index = floor(index)
    upper_index = ceil(index)

    if lower_index == upper_index do
      Enum.at(sorted_values, round(index))
    else
      lower = Enum.at(sorted_values, lower_index)
      upper = Enum.at(sorted_values, upper_index)
      lower + (upper - lower) * (index - lower_index)
    end
  end
end
