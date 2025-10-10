defmodule ResearchHarness.Reporter.MarkdownGenerator do
  @moduledoc """
  Generates Markdown reports suitable for papers and documentation.
  """

  @doc """
  Generates a complete Markdown report.
  """
  def generate(config, analysis) do
    [
      header(config),
      methodology(config),
      results_summary(analysis),
      statistical_tests(analysis),
      comparison_tables(analysis, config),
      conclusions()
    ]
    |> Enum.join("\n\n")
  end

  defp header(config) do
    """
    # #{config.name}

    **Experiment ID:** #{config.experiment_id}
    **Date:** #{Date.utc_today()}
    **Author:** #{config.author}
    **Version:** #{config.version}

    ## Abstract

    #{config.description}
    """
  end

  defp methodology(config) do
    """
    ## Methodology

    ### Dataset

    - **Name:** #{config.dataset}
    - **Configuration:** #{inspect(config.dataset_config)}

    ### Experimental Conditions

    #{format_conditions(config.conditions)}

    ### Metrics

    #{format_metrics(config.metrics)}

    ### Statistical Analysis

    - **Significance Level:** #{config.statistical_analysis.significance_level}
    - **Multiple Testing Correction:** #{config.statistical_analysis.multiple_testing_correction}
    - **Confidence Interval:** #{config.statistical_analysis.confidence_interval}
    - **Repetitions per Condition:** #{config.repeat}
    """
  end

  defp format_conditions(conditions) do
    conditions
    |> Enum.map(fn condition ->
      "- **#{condition.name}**: #{Map.get(condition, :description, "No description")}"
    end)
    |> Enum.join("\n")
  end

  defp format_metrics(metrics) do
    metrics
    |> Enum.map(fn metric -> "- #{metric}" end)
    |> Enum.join("\n")
  end

  defp results_summary(analysis) do
    """
    ## Results

    ### Summary Statistics

    #{format_summary_table(analysis.aggregated_results)}
    """
  end

  defp format_summary_table(results) do
    if Enum.empty?(results) do
      "No results to display."
    else
      # Get all metrics from first result
      first_result = List.first(results)
      metrics = Map.keys(first_result.metrics)

      # Create header
      header =
        "| Condition | N | " <> Enum.map_join(metrics, " | ", &format_metric_name/1) <> " |"

      separator = "|" <> String.duplicate("---|", 2 + length(metrics))

      # Create rows
      rows =
        Enum.map(results, fn result ->
          metric_cells =
            Enum.map(metrics, fn metric ->
              stats = result.metrics[metric]

              if stats && stats.mean do
                "#{Float.round(stats.mean, 3)} ± #{Float.round(stats.std || 0, 3)}"
              else
                "N/A"
              end
            end)

          "| #{result.condition} | #{result.n} | " <> Enum.join(metric_cells, " | ") <> " |"
        end)

      [header, separator | rows]
      |> Enum.join("\n")
    end
  end

  defp format_metric_name(metric) do
    metric
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp statistical_tests(analysis) do
    """
    ## Statistical Analysis

    ### Pairwise Comparisons

    #{format_pairwise_comparisons(analysis.statistical_analysis.comparisons)}

    ### Confidence Intervals

    #{format_confidence_intervals(analysis.statistical_analysis.confidence_intervals)}
    """
  end

  defp format_pairwise_comparisons(comparisons) do
    if Enum.empty?(comparisons) do
      "No comparisons available (need at least 2 conditions)."
    else
      Enum.map(comparisons, fn comp ->
        {c1, c2} = comp.pair

        """
        #### #{c1} vs #{c2}

        #{format_comparison_metrics(comp.metrics)}
        """
      end)
      |> Enum.join("\n")
    end
  end

  defp format_comparison_metrics(metrics) do
    header = "| Metric | Mean Diff | t-statistic | p-value | Significant? | Effect Size |"
    separator = "|---|---|---|---|---|---|"

    rows =
      Enum.map(metrics, fn {metric, stats} ->
        sig = if stats.significant, do: "**Yes**", else: "No"

        "| #{metric} | #{Float.round(stats.mean_diff, 4)} | " <>
          "#{Float.round(stats.t_statistic, 4)} | #{Float.round(stats.p_value, 4)} | " <>
          "#{sig} | #{Float.round(stats.effect_size, 4)} |"
      end)

    [header, separator | rows]
    |> Enum.join("\n")
  end

  defp format_confidence_intervals(intervals) do
    Enum.map(intervals, fn interval ->
      """
      **#{interval.condition}**

      #{format_interval_table(interval.intervals)}
      """
    end)
    |> Enum.join("\n\n")
  end

  defp format_interval_table(intervals) do
    header = "| Metric | 95% Confidence Interval |"
    separator = "|---|---|"

    rows =
      Enum.map(intervals, fn {metric, {lower, upper}} ->
        if lower && upper do
          "| #{metric} | [#{Float.round(lower, 4)}, #{Float.round(upper, 4)}] |"
        else
          "| #{metric} | N/A |"
        end
      end)

    [header, separator | rows]
    |> Enum.join("\n")
  end

  defp comparison_tables(analysis, _config) do
    matrices = analysis.comparison_matrices

    if map_size(matrices) > 0 do
      """
      ## Comparison Matrices

      #{Enum.map(matrices, fn {metric, matrix} -> """
        ### #{format_metric_name(metric)}

        #{format_comparison_matrix(matrix)}
        """ end) |> Enum.join("\n\n")}
      """
    else
      ""
    end
  end

  defp format_comparison_matrix(matrix) do
    conditions = matrix.conditions

    if length(conditions) < 2 do
      "Not enough conditions for matrix comparison."
    else
      header = "| | " <> Enum.join(conditions, " | ") <> " |"
      separator = "|" <> String.duplicate("---|", length(conditions) + 1)

      rows =
        Enum.map(conditions, fn c1 ->
          row_data = matrix.matrix[c1]

          cells =
            Enum.zip(conditions, row_data)
            |> Enum.map(fn {_c2, cell} -> format_matrix_cell(cell) end)

          "| #{c1} | " <> Enum.join(cells, " | ") <> " |"
        end)

      [header, separator | rows]
      |> Enum.join("\n")
    end
  end

  defp format_matrix_cell(%{type: :self}), do: "-"
  defp format_matrix_cell(%{type: :missing}), do: "N/A"

  defp format_matrix_cell(%{type: :comparison} = cell) do
    if cell.significant do
      "**#{format_diff(cell.mean_diff)}** (p=#{Float.round(cell.p_value, 4)})"
    else
      "#{format_diff(cell.mean_diff)} (ns)"
    end
  end

  defp format_diff(diff) when diff > 0, do: "+#{Float.round(diff, 3)}"
  defp format_diff(diff), do: "#{Float.round(diff, 3)}"

  defp conclusions do
    """
    ## Conclusions

    [Add your conclusions here based on the results above]

    ---
    *Report generated by ResearchHarness*
    """
  end
end
