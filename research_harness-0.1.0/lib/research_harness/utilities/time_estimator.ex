defmodule ResearchHarness.Utilities.TimeEstimator do
  @moduledoc """
  Estimates experiment duration based on configuration and sample runs.
  """

  @doc """
  Estimates the total time required to run an experiment.

  Returns a map with time estimates in milliseconds.
  """
  def estimate(config, _opts \\ []) do
    # Calculate total queries
    num_conditions = length(config.conditions)
    num_repeats = config.repeat
    dataset_size = config.dataset_config[:sample_size] || 100
    total_queries = num_conditions * num_repeats * dataset_size

    # Estimate average time per query
    avg_time_per_query = estimate_query_time(config)

    # Account for parallelization
    max_parallel = config.config[:max_parallel] || 10
    rate_limit = config.config[:rate_limit]

    # Calculate sequential time
    sequential_time = total_queries * avg_time_per_query

    # Calculate parallel time
    parallel_time = sequential_time / max_parallel

    # Rate limiting may increase time
    estimated_time =
      if rate_limit do
        # ms
        min_time = total_queries / rate_limit * 1000
        max(parallel_time, min_time)
      else
        parallel_time
      end

    %{
      total_queries: total_queries,
      avg_time_per_query: avg_time_per_query,
      sequential_estimate: sequential_time,
      parallel_estimate: parallel_time,
      estimated_duration: estimated_time,
      estimated_completion:
        DateTime.add(
          DateTime.utc_now(),
          round(estimated_time / 1000),
          :second
        )
    }
  end

  defp estimate_query_time(config) do
    # Use configured timeout as upper bound
    timeout = config.config[:timeout] || 30_000

    # Estimate based on typical LLM response times
    # For production, this could run a few sample queries
    # 2 seconds average
    base_latency = 2_000

    # Adjust based on expected complexity
    min(base_latency, timeout * 0.5)
  end
end
