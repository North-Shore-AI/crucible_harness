defmodule CrucibleHarness.Reporter.JupyterGenerator do
  @moduledoc """
  Generates Jupyter notebooks (.ipynb) for interactive analysis.
  """

  @doc """
  Generates a Jupyter notebook with Python code for analysis.
  """
  def generate(config, analysis) do
    notebook = %{
      "cells" => [
        markdown_cell("# #{config.name}"),
        markdown_cell(
          "**Experiment ID:** #{config.experiment_id}\n\n**Date:** #{Date.utc_today()}"
        ),
        markdown_cell("## Abstract\n\n#{config.description}"),
        markdown_cell("## Setup"),
        code_cell(setup_code()),
        markdown_cell("## Load Results"),
        code_cell(load_results_code(config, analysis)),
        markdown_cell("## Summary Statistics"),
        code_cell(summary_stats_code()),
        markdown_cell("## Visualizations"),
        code_cell(visualization_code()),
        markdown_cell("## Statistical Tests"),
        code_cell(statistical_tests_code())
      ],
      "metadata" => notebook_metadata(),
      "nbformat" => 4,
      "nbformat_minor" => 5
    }

    Jason.encode!(notebook, pretty: true)
  end

  defp markdown_cell(content) do
    %{
      "cell_type" => "markdown",
      "metadata" => %{},
      "source" => [content]
    }
  end

  defp code_cell(code) do
    %{
      "cell_type" => "code",
      "execution_count" => nil,
      "metadata" => %{},
      "source" => [code],
      "outputs" => []
    }
  end

  defp notebook_metadata do
    %{
      "kernelspec" => %{
        "display_name" => "Python 3",
        "language" => "python",
        "name" => "python3"
      },
      "language_info" => %{
        "name" => "python",
        "version" => "3.8.0"
      }
    }
  end

  defp setup_code do
    """
    import pandas as pd
    import numpy as np
    import matplotlib.pyplot as plt
    import seaborn as sns
    from scipy import stats

    sns.set_style('whitegrid')
    %matplotlib inline
    """
  end

  defp load_results_code(config, analysis) do
    # Convert results to Python-friendly format
    results_data = format_results_for_python(analysis.aggregated_results)

    """
    # Experiment: #{config.name}
    # Results data
    data = #{results_data}

    df = pd.DataFrame(data)
    print(df.head())
    """
  end

  defp format_results_for_python(results) do
    if Enum.empty?(results) do
      "[]"
    else
      data =
        Enum.flat_map(results, fn result ->
          format_result_metrics(result)
        end)

      Jason.encode!(data)
    end
  end

  defp summary_stats_code do
    """
    # Summary statistics by condition and metric
    summary = df.groupby(['condition', 'metric'])['value'].agg(['mean', 'std', 'count', 'median'])
    print(summary)
    """
  end

  defp visualization_code do
    """
    # Create visualizations
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    # Box plot by condition
    df_pivot = df.pivot(columns='metric', values='value')
    df_with_condition = df[['condition']].join(df_pivot)

    if 'accuracy' in df['metric'].values:
        accuracy_data = df[df['metric'] == 'accuracy']
        sns.boxplot(data=accuracy_data, x='condition', y='value', ax=axes[0])
        axes[0].set_title('Accuracy by Condition')
        axes[0].set_ylabel('Accuracy')
        axes[0].tick_params(axis='x', rotation=45)

    if 'latency' in df['metric'].values:
        latency_data = df[df['metric'] == 'latency']
        sns.boxplot(data=latency_data, x='condition', y='value', ax=axes[1])
        axes[1].set_title('Latency by Condition')
        axes[1].set_ylabel('Latency (ms)')
        axes[1].tick_params(axis='x', rotation=45)

    plt.tight_layout()
    plt.show()
    """
  end

  defp statistical_tests_code do
    """
    # Pairwise statistical tests
    conditions = df['condition'].unique()
    metrics = df['metric'].unique()

    print("Pairwise t-tests:")
    for metric in metrics:
        print(f"\\n=== {metric} ===")
        metric_data = df[df['metric'] == metric]

        for i, cond1 in enumerate(conditions):
            for cond2 in conditions[i+1:]:
                values1 = metric_data[metric_data['condition'] == cond1]['value']
                values2 = metric_data[metric_data['condition'] == cond2]['value']

                if len(values1) > 0 and len(values2) > 0:
                    t_stat, p_value = stats.ttest_ind(values1, values2)
                    print(f"{cond1} vs {cond2}: t={t_stat:.4f}, p={p_value:.4f}")
    """
  end

  defp format_result_metrics(result) do
    Enum.flat_map(result.metrics, fn {metric, stats} ->
      format_metric_values(result, metric, stats)
    end)
  end

  defp format_metric_values(result, metric, stats) do
    if stats.values do
      Enum.map(stats.values, fn value ->
        %{
          "condition" => result.condition,
          "metric" => to_string(metric),
          "value" => value
        }
      end)
    else
      []
    end
  end
end
