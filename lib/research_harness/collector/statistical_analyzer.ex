defmodule CrucibleHarness.Collector.StatisticalAnalyzer do
  @moduledoc """
  Performs statistical comparisons between experimental conditions.
  """

  @doc """
  Performs comprehensive statistical analysis including pairwise comparisons
  and effect size calculations.
  """
  def analyze(aggregated_results, config) do
    %{
      comparisons: pairwise_comparisons(aggregated_results, config),
      effect_sizes: compute_effect_sizes(aggregated_results, config.metrics),
      confidence_intervals: compute_confidence_intervals(aggregated_results, config)
    }
  end

  defp pairwise_comparisons(results, config) do
    # Generate all pairs of conditions
    conditions = Enum.map(results, & &1.condition)
    pairs = for c1 <- conditions, c2 <- conditions, c1 < c2, do: {c1, c2}

    Enum.map(pairs, fn {c1, c2} ->
      result1 = Enum.find(results, &(&1.condition == c1))
      result2 = Enum.find(results, &(&1.condition == c2))

      comparisons =
        Enum.map(config.metrics, fn metric ->
          values1 = get_metric_values(result1, metric)
          values2 = get_metric_values(result2, metric)

          test_result = t_test(values1, values2, config.statistical_analysis)

          {metric,
           %{
             condition1: c1,
             condition2: c2,
             mean_diff: test_result.mean_diff,
             t_statistic: test_result.t_statistic,
             p_value: test_result.p_value,
             significant: test_result.significant,
             ci_lower: test_result.ci_lower,
             ci_upper: test_result.ci_upper,
             effect_size: cohens_d(values1, values2)
           }}
        end)
        |> Map.new()

      %{
        pair: {c1, c2},
        metrics: comparisons
      }
    end)
  end

  defp compute_effect_sizes(results, metrics) do
    Enum.map(results, fn result ->
      effect_sizes =
        Enum.map(metrics, fn metric ->
          values = get_metric_values(result, metric)
          {metric, compute_cohens_d_baseline(values)}
        end)
        |> Map.new()

      %{condition: result.condition, effect_sizes: effect_sizes}
    end)
  end

  defp compute_confidence_intervals(results, config) do
    level = config.statistical_analysis.confidence_interval

    Enum.map(results, fn result ->
      intervals =
        Enum.map(config.metrics, fn metric ->
          values = get_metric_values(result, metric)
          {metric, confidence_interval(values, level)}
        end)
        |> Map.new()

      %{condition: result.condition, intervals: intervals}
    end)
  end

  # Statistical Functions

  defp t_test(values1, values2, analysis_config) do
    n1 = length(values1)
    n2 = length(values2)
    mean1 = mean(values1)
    mean2 = mean(values2)
    var1 = variance(values1)
    var2 = variance(values2)

    if var1 == 0 and var2 == 0 do
      t_test_zero_variance(mean1, mean2, n1, n2)
    else
      t_test_welch(mean1, mean2, var1, var2, n1, n2, analysis_config)
    end
  end

  defp t_test_zero_variance(mean1, mean2, n1, n2) do
    %{
      t_statistic: if(mean1 == mean2, do: 0.0, else: :infinity),
      p_value: if(mean1 == mean2, do: 1.0, else: 0.0),
      df: n1 + n2 - 2,
      mean_diff: mean1 - mean2,
      ci_lower: mean1 - mean2,
      ci_upper: mean1 - mean2,
      significant: mean1 != mean2
    }
  end

  defp t_test_welch(mean1, mean2, var1, var2, n1, n2, analysis_config) do
    pooled_std = :math.sqrt(var1 / n1 + var2 / n2)
    t_statistic = calculate_t_statistic(mean1, mean2, pooled_std)
    df = calculate_degrees_of_freedom(var1, var2, n1, n2)
    p_value = calculate_p_value(t_statistic, mean1, mean2, df)

    ci_level = analysis_config.confidence_interval
    t_critical = t_inverse(1 - (1 - ci_level) / 2, df)
    margin = t_critical * pooled_std

    %{
      t_statistic: t_statistic,
      p_value: p_value,
      degrees_of_freedom: df,
      mean_diff: mean1 - mean2,
      ci_lower: mean1 - mean2 - margin,
      ci_upper: mean1 - mean2 + margin,
      significant: p_value < analysis_config.significance_level
    }
  end

  defp calculate_t_statistic(mean1, mean2, pooled_std) do
    if pooled_std > 0 do
      (mean1 - mean2) / pooled_std
    else
      if mean1 == mean2, do: 0.0, else: :infinity
    end
  end

  defp calculate_degrees_of_freedom(var1, var2, n1, n2) do
    if var1 > 0 or var2 > 0 do
      :math.pow(var1 / n1 + var2 / n2, 2) /
        (:math.pow(var1 / n1, 2) / (n1 - 1) + :math.pow(var2 / n2, 2) / (n2 - 1))
    else
      n1 + n2 - 2
    end
  end

  defp calculate_p_value(t_statistic, mean1, mean2, df) do
    if is_number(t_statistic) and t_statistic != :infinity do
      2 * (1 - t_cdf(abs(t_statistic), df))
    else
      if mean1 == mean2, do: 1.0, else: 0.0
    end
  end

  defp cohens_d(values1, values2) do
    mean1 = mean(values1)
    mean2 = mean(values2)

    n1 = length(values1)
    n2 = length(values2)

    var1 = variance(values1)
    var2 = variance(values2)

    # Pooled standard deviation
    pooled_var = ((n1 - 1) * var1 + (n2 - 1) * var2) / (n1 + n2 - 2)

    if pooled_var > 0 do
      pooled_std = :math.sqrt(pooled_var)
      (mean1 - mean2) / pooled_std
    else
      # If variance is zero, return 0 if means are equal, infinity otherwise
      if mean1 == mean2, do: 0.0, else: :infinity
    end
  end

  defp compute_cohens_d_baseline(_values) do
    # Placeholder for baseline comparison
    0.0
  end

  defp confidence_interval(values, _level) when length(values) < 2 do
    {nil, nil}
  end

  defp confidence_interval(values, level) do
    n = length(values)
    m = mean(values)
    std = std_dev(values)

    # Use t-distribution for small samples
    df = n - 1
    t_critical = t_inverse((1 + level) / 2, df)
    margin = t_critical * std / :math.sqrt(n)

    {m - margin, m + margin}
  end

  # Helper functions

  defp get_metric_values(result, metric) do
    result.metrics[metric][:values] || []
  end

  defp mean([]), do: 0.0

  defp mean(values) do
    Enum.sum(values) / length(values)
  end

  defp variance([]), do: 0.0
  defp variance([_]), do: 0.0

  defp variance(values) do
    m = mean(values)

    Enum.map(values, fn x -> :math.pow(x - m, 2) end)
    |> Enum.sum()
    |> Kernel./(length(values) - 1)
  end

  defp std_dev(values) do
    :math.sqrt(variance(values))
  end

  # Approximate t-distribution CDF (simplified)
  defp t_cdf(t, df) do
    # Simplified approximation using normal distribution for df > 30
    if df > 30 do
      normal_cdf(t)
    else
      # More complex approximation would go here
      normal_cdf(t * :math.sqrt(df / (df + t * t)))
    end
  end

  defp normal_cdf(x) do
    0.5 * (1 + :math.erf(x / :math.sqrt(2)))
  end

  # Approximate inverse t-distribution
  defp t_inverse(p, df) do
    # Simplified: use normal inverse for large df
    if df > 30 do
      normal_inverse(p)
    else
      # Rough approximation
      normal_inverse(p) * :math.sqrt((df + 1) / df)
    end
  end

  defp rational_approximation(r) do
    ((((0.3374754822 * r + 0.9761690190) * r + 0.1607979714) * r + 0.2765672646) * r +
       1.5707963050) * r + 0.3193815032
  end

  defp central_approximation(r) do
    (((-25.4410604963 * r + 41.3911977353) * r - 18.6150006252) * r + 2.5066282388) /
      ((((3.1308290983 * r - 21.0622410182) * r + 23.0833674374) * r - 8.4735109309) * r +
         1)
  end

  defp normal_inverse_tail(p, q) do
    r = if q > 0, do: 1 - p, else: p
    r = :math.log(-:math.log(r))
    sign = if q > 0, do: 1, else: -1
    sign * rational_approximation(r)
  end

  defp normal_inverse_central(q) do
    r = q * q
    q * central_approximation(r)
  end

  defp normal_inverse(p) do
    # Approximation using Beasley-Springer-Moro algorithm (simplified)
    cond do
      p <= 0.0 ->
        -999.0

      p >= 1.0 ->
        999.0

      p == 0.5 ->
        0.0

      true ->
        q = p - 0.5
        if abs(q) <= 0.42, do: normal_inverse_central(q), else: normal_inverse_tail(p, q)
    end
  end
end
