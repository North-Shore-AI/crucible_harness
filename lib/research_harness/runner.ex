defmodule CrucibleHarness.Runner do
  @moduledoc """
  Orchestrates the execution of research experiments using GenStage pipeline.
  """

  alias CrucibleHarness.Runner.{ProgressTracker, RateLimiter}

  @doc """
  Runs an experiment and returns the results.
  """
  def run_experiment(config, opts \\ []) do
    experiment_id = config.experiment_id

    # Initialize random seed for reproducibility
    initialize_random_seed(config)

    # Load dataset
    dataset = load_dataset(config)

    # Generate all tasks
    tasks = generate_tasks(config, dataset)
    total_tasks = length(tasks)

    # Start progress tracker
    {:ok, _tracker} = ProgressTracker.start_link(experiment_id, total_tasks)

    # Start rate limiter if configured
    rate_limit = config.config[:rate_limit]

    if rate_limit do
      {:ok, _limiter} = RateLimiter.start_link(rate_limit)
    end

    # Execute tasks in parallel
    results = execute_tasks(tasks, config, opts)

    # Stop processes
    if rate_limit do
      GenServer.stop(RateLimiter)
    end

    GenServer.stop(ProgressTracker)

    {:ok, results}
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
    # For now, return a mock dataset
    # In production, this would integrate with dataset_manager
    _dataset_name = config.dataset
    size = config.dataset_config[:sample_size] || 100

    Enum.map(1..size, fn i ->
      %{
        id: "query_#{i}",
        question: "Sample question #{i}",
        answer: "Sample answer #{i}"
      }
    end)
  end

  defp generate_tasks(config, dataset) do
    for condition <- config.conditions,
        repeat_num <- 1..config.repeat,
        query <- dataset do
      %{
        experiment_id: config.experiment_id,
        condition: condition,
        repeat: repeat_num,
        query: query,
        timeout: config.config[:timeout] || 30_000
      }
    end
  end

  defp execute_tasks(tasks, config, _opts) do
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
    :telemetry.execute(
      [:research_harness, :task, :complete],
      %{duration: elapsed_time},
      %{
        experiment_id: task.experiment_id,
        condition: task.condition.name,
        repeat: task.repeat
      }
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
end
