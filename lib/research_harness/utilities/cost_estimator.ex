defmodule CrucibleHarness.Utilities.CostEstimator do
  @moduledoc """
  Estimates experiment costs before execution.
  """

  # Cost per 1K tokens for various models (as of 2024)
  @model_costs %{
    gpt4: %{input: 0.03, output: 0.06},
    gpt4_turbo: %{input: 0.01, output: 0.03},
    gpt35_turbo: %{input: 0.0015, output: 0.002},
    claude_opus: %{input: 0.015, output: 0.075},
    claude_sonnet: %{input: 0.003, output: 0.015},
    claude_haiku: %{input: 0.00025, output: 0.00125},
    gemini_pro: %{input: 0.00025, output: 0.0005},
    gemini_flash: %{input: 0.000125, output: 0.0003}
  }

  @doc """
  Estimates the total cost of running an experiment.

  Returns a map with cost breakdown and totals.
  """
  def estimate(config) do
    # Calculate total number of queries
    num_conditions = length(config.conditions)
    num_repeats = config.repeat
    dataset_size = config.dataset_config[:sample_size] || 100
    total_queries = num_conditions * num_repeats * dataset_size

    # Estimate tokens per query
    avg_input_tokens = estimate_avg_input_tokens()
    # Reasonable default estimate
    avg_output_tokens = 500

    # Estimate cost per condition
    condition_costs =
      Enum.map(config.conditions, fn condition ->
        model_cost = get_model_cost(condition)

        queries_per_condition = num_repeats * dataset_size

        cost =
          queries_per_condition *
            (avg_input_tokens / 1000 * model_cost.input +
               avg_output_tokens / 1000 * model_cost.output)

        {condition.name, cost}
      end)
      |> Map.new()

    total_cost = condition_costs |> Map.values() |> Enum.sum()

    estimate = %{
      total_queries: total_queries,
      avg_tokens_per_query: avg_input_tokens + avg_output_tokens,
      condition_costs: condition_costs,
      total_cost: total_cost,
      currency: :usd
    }

    # Check against budget
    if budget = config.cost_budget do
      max_total = budget[:max_total]

      if max_total && total_cost > max_total do
        {:warning, :exceeds_budget, estimate}
      else
        estimate
      end
    else
      estimate
    end
  end

  defp estimate_avg_input_tokens do
    # Default estimate based on typical MMLU questions
    # In production, this would sample actual queries
    250
  end

  defp get_model_cost(condition) do
    # Try to extract model from condition metadata
    model = condition[:model] || condition[:metadata][:model] || :gpt35_turbo
    @model_costs[model] || %{input: 0.001, output: 0.002}
  end
end
