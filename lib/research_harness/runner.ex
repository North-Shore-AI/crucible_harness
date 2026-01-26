defmodule CrucibleHarness.Runner do
  @moduledoc """
  Orchestrates the execution of research experiments.

  Supports two execution engines:
  - `:flow` (default) - Uses Flow/GenStage for parallel processing
  - `:async_stream` - Uses `Task.async_stream/3` for bounded concurrency

  ## Execution Engine Selection

  Configure the execution engine in your experiment's config:

      config %{
        execution_engine: :async_stream,
        max_parallel: 4,
        timeout: 60_000
      }

  The `:async_stream` engine is recommended for:
  - GPU-bound tasks with strict VRAM limits
  - Large datasets requiring streaming/lazy evaluation
  - Scenarios where memory pressure is a concern

  The `:flow` engine is recommended for:
  - CPU-bound tasks that benefit from parallel execution
  - Tasks that can scale across many CPU cores
  """

  alias CrucibleHarness.Runner.{AsyncStream, ProgressTracker, RateLimiter}

  @doc """
  Runs an experiment and returns the results.
  """
  def run_experiment(config, opts \\ []) do
    experiment_id = config.experiment_id

    # Initialize random seed for reproducibility
    initialize_random_seed(config)

    # Load dataset (may return a stream or list)
    dataset = load_dataset(config)

    # Generate all tasks (returns a stream)
    tasks = generate_tasks(config, dataset, opts)

    # Calculate estimated total tasks
    # For streams, we estimate based on config; for lists, we use actual count
    total_tasks = estimate_total_tasks(config, dataset)

    # Start progress tracker
    {:ok, _tracker} = ProgressTracker.start_link(experiment_id, total_tasks)

    # Start rate limiter if configured
    rate_limit = config.config[:rate_limit]

    if rate_limit do
      {:ok, _limiter} = RateLimiter.start_link(rate_limit)
    end

    # Execute tasks (handles both streams and lists)
    results = execute_tasks(tasks, config, opts)

    # Stop processes
    if rate_limit do
      GenServer.stop(RateLimiter)
    end

    GenServer.stop(ProgressTracker)

    {:ok, results}
  end

  defp estimate_total_tasks(config, dataset) do
    dataset_size = estimate_dataset_size(config, dataset)
    num_conditions = length(config.conditions)
    num_repeats = config.repeat || 1

    dataset_size * num_conditions * num_repeats
  end

  defp estimate_dataset_size(_config, dataset) when is_list(dataset) do
    length(dataset)
  end

  defp estimate_dataset_size(config, _dataset) do
    # For streams, use the configured sample_size or limit
    config.dataset_config[:sample_size] ||
      config.dataset_config[:limit] ||
      100
  end

  @doc """
  Resumes an experiment from a checkpoint.
  """
  def resume_experiment(checkpoint) do
    config = checkpoint.config
    remaining_tasks = checkpoint.remaining_tasks

    # Restore random state
    :rand.seed(checkpoint.random_state)

    # Continue execution
    results = checkpoint.completed_results ++ execute_tasks(remaining_tasks, config, [])

    {:ok, results}
  end

  # Private Functions

  defp initialize_random_seed(config) do
    seed = config.config[:random_seed] || :rand.uniform(1_000_000_000)
    :rand.seed(:exsplus, {seed, seed + 1, seed + 2})
  end

  defp load_dataset(config) do
    dataset = config.dataset
    dataset_config = config.dataset_config || %{}

    cond do
      # If dataset is already an enumerable/stream, use it directly
      is_list(dataset) or is_function(dataset, 2) ->
        apply_dataset_limit(dataset, dataset_config)

      # If dataset is a stream struct
      match?(%Stream{}, dataset) ->
        apply_dataset_limit(dataset, dataset_config)

      # If dataset_config contains a :data key with the actual data
      is_map(dataset_config) and Map.has_key?(dataset_config, :data) ->
        apply_dataset_limit(dataset_config.data, dataset_config)

      # Default: generate mock dataset for testing
      true ->
        generate_mock_dataset(config, dataset_config)
    end
  end

  defp apply_dataset_limit(data, dataset_config) do
    limit = dataset_config[:limit] || dataset_config[:sample_size]

    if limit do
      Stream.take(data, limit)
    else
      data
    end
  end

  defp generate_mock_dataset(_config, dataset_config) do
    # Generate mock dataset for testing
    size = dataset_config[:sample_size] || 100

    # Return as a stream for lazy evaluation
    Stream.map(1..size, fn i ->
      %{
        id: "query_#{i}",
        question: "Sample question #{i}",
        answer: "Sample answer #{i}"
      }
    end)
  end

  defp generate_tasks(config, dataset, opts) do
    lineage_source = Keyword.get(opts, :lineage, %{})
    timeout = config.config[:timeout] || 30_000

    # Generate tasks as a stream to support lazy evaluation
    # This allows large datasets to be processed without materializing all tasks
    dataset
    |> Stream.flat_map(fn query ->
      for condition <- config.conditions,
          repeat_num <- 1..config.repeat do
        %{
          experiment_id: config.experiment_id,
          condition: condition,
          repeat: repeat_num,
          query: query,
          timeout: timeout,
          lineage: lineage_source
        }
      end
    end)
  end

  defp execute_tasks(tasks, config, opts) do
    engine = get_execution_engine(config, opts)

    case engine do
      :async_stream ->
        execute_with_async_stream(tasks, config, opts)

      :flow ->
        execute_with_flow(tasks, config, opts)

      _ ->
        # Default to Flow for backwards compatibility
        execute_with_flow(tasks, config, opts)
    end
  end

  defp get_execution_engine(config, opts) do
    Keyword.get(opts, :execution_engine) ||
      get_in(config.config, [:execution_engine]) ||
      :flow
  end

  defp execute_with_async_stream(tasks, config, opts) do
    results = AsyncStream.run_tasks(tasks, config, opts)

    # Update progress tracker with total count
    if Process.whereis(ProgressTracker) do
      ProgressTracker.update(length(results))
    end

    results
  end

  defp execute_with_flow(tasks, config, _opts) do
    max_parallel = config.config[:max_parallel] || 10
    _checkpoint_interval = config.config[:checkpoint_interval] || 100

    # Execute tasks in parallel using Flow
    results =
      tasks
      |> Flow.from_enumerable(max_demand: max_parallel, stages: max_parallel)
      |> Flow.map(&execute_task/1)
      |> Enum.to_list()

    # Update progress tracker with total count
    ProgressTracker.update(length(results))

    results
  end

  defp execute_task(task) do
    # Rate limiting
    if Process.whereis(RateLimiter) do
      RateLimiter.acquire()
    end

    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        # Execute the condition function with timeout
        Task.async(fn -> task.condition.fn.(task.query) end)
        |> Task.await(task.timeout)
      rescue
        e -> {:error, Exception.message(e)}
      catch
        :exit, {:timeout, _} -> {:error, :timeout}
      end

    end_time = System.monotonic_time(:millisecond)
    elapsed_time = end_time - start_time

    # Emit telemetry event
    lineage = resolve_lineage(task)
    telemetry_meta = build_lineage_metadata(lineage)

    :telemetry.execute(
      [:research_harness, :task, :complete],
      %{duration: elapsed_time},
      Map.merge(
        %{
          experiment_id: task.experiment_id,
          condition: task.condition.name,
          repeat: task.repeat
        },
        telemetry_meta
      )
    )

    %{
      experiment_id: task.experiment_id,
      condition: task.condition.name,
      repeat: task.repeat,
      query_id: task.query.id,
      result: result,
      elapsed_time: elapsed_time,
      timestamp: DateTime.utc_now()
    }
  end

  defp resolve_lineage(%{lineage: lineage} = task) when is_function(lineage, 1) do
    lineage.(Map.delete(task, :lineage))
  end

  defp resolve_lineage(%{lineage: lineage}) when is_map(lineage), do: lineage
  defp resolve_lineage(_task), do: %{}

  defp build_lineage_metadata(lineage) do
    %{
      trace_id: Map.get(lineage, :trace_id),
      work_id: Map.get(lineage, :work_id),
      plan_id: Map.get(lineage, :plan_id),
      step_id: Map.get(lineage, :step_id)
    }
  end
end
