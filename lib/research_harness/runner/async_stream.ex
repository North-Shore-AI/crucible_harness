defmodule CrucibleHarness.Runner.AsyncStream do
  @moduledoc """
  Alternative execution engine using `Task.async_stream/3` for bounded concurrency.

  This engine is designed for scenarios where:
  - Memory pressure is a concern (large datasets)
  - GPU-bound tasks require strict concurrency limits
  - Streaming/lazy evaluation is preferred over materializing all results

  ## Usage

  Configure the execution engine in your experiment:

      config %{
        execution_engine: :async_stream,
        max_parallel: 4,
        timeout: 60_000
      }

  ## Options

    * `:max_concurrency` - Maximum number of concurrent tasks (default: 4)
    * `:timeout` - Task timeout in milliseconds (default: 30_000)
    * `:ordered` - Whether to preserve order of results (default: true)
    * `:on_timeout` - Behavior on timeout: `:exit` | `:kill_task` (default: `:kill_task`)

  """

  alias CrucibleHarness.Runner.{ProgressTracker, RateLimiter}

  @type task :: map()
  @type result :: map()
  @type opts :: keyword()

  @default_max_concurrency 4
  @default_timeout 30_000
  @default_ordered true

  @doc """
  Executes tasks using `Task.async_stream/3` with bounded concurrency.

  Returns a list of results. Unlike the Flow-based engine, this implementation
  processes tasks lazily and can handle enumerables/streams without full materialization.

  ## Options

    * `:max_concurrency` - Maximum number of concurrent tasks (default: 4)
    * `:timeout` - Task timeout in milliseconds (default: 30_000)
    * `:ordered` - Whether to preserve order of results (default: true)

  ## Examples

      tasks = generate_tasks(config, dataset)
      results = AsyncStream.run_tasks(tasks, config, max_concurrency: 4)

  """
  @spec run_tasks(Enumerable.t(), map(), opts()) :: [result()]
  def run_tasks(tasks, config, opts \\ []) do
    max_concurrency = resolve_max_concurrency(config, opts)
    timeout = resolve_timeout(config, opts)
    ordered = Keyword.get(opts, :ordered, @default_ordered)
    on_timeout = Keyword.get(opts, :on_timeout, :kill_task)

    # Emit telemetry for execution start
    :telemetry.execute(
      [:research_harness, :runner, :async_stream, :start],
      %{max_concurrency: max_concurrency, timeout: timeout},
      %{experiment_id: config.experiment_id, ordered: ordered}
    )

    start_time = System.monotonic_time(:millisecond)

    results =
      tasks
      |> Task.async_stream(
        &execute_task(&1, config),
        max_concurrency: max_concurrency,
        timeout: timeout,
        ordered: ordered,
        on_timeout: on_timeout
      )
      |> Stream.with_index(1)
      |> Enum.map(fn {result, index} ->
        handle_task_result(result, index, config)
      end)

    elapsed = System.monotonic_time(:millisecond) - start_time

    # Emit telemetry for execution complete
    :telemetry.execute(
      [:research_harness, :runner, :async_stream, :complete],
      %{duration: elapsed, result_count: length(results)},
      %{experiment_id: config.experiment_id}
    )

    results
  end

  @doc """
  Executes tasks as a stream, yielding results lazily.

  Unlike `run_tasks/3`, this returns a `Stream` that can be consumed incrementally.
  Useful for checkpointing or progress reporting without holding all results in memory.

  ## Examples

      tasks
      |> AsyncStream.stream_tasks(config)
      |> Stream.each(&checkpoint_result/1)
      |> Enum.to_list()

  """
  @spec stream_tasks(Enumerable.t(), map(), opts()) :: Enumerable.t()
  def stream_tasks(tasks, config, opts \\ []) do
    max_concurrency = resolve_max_concurrency(config, opts)
    timeout = resolve_timeout(config, opts)
    ordered = Keyword.get(opts, :ordered, @default_ordered)
    on_timeout = Keyword.get(opts, :on_timeout, :kill_task)

    tasks
    |> Task.async_stream(
      &execute_task(&1, config),
      max_concurrency: max_concurrency,
      timeout: timeout,
      ordered: ordered,
      on_timeout: on_timeout
    )
    |> Stream.with_index(1)
    |> Stream.map(fn {result, index} ->
      handle_task_result(result, index, config)
    end)
  end

  @doc """
  Executes tasks with progress callback.

  Calls the provided callback after each task completes with the result
  and the current count.

  ## Examples

      AsyncStream.run_tasks_with_progress(tasks, config, fn result, count, total ->
        IO.puts("Completed \#{count}/\#{total}")
        :ok
      end)

  """
  @spec run_tasks_with_progress(
          Enumerable.t(),
          map(),
          (result(), pos_integer(), pos_integer() -> any()),
          opts()
        ) :: [result()]
  def run_tasks_with_progress(tasks, config, callback, opts \\ [])
      when is_function(callback, 3) do
    # We need to know total for progress reporting
    # If tasks is a stream, we cannot know total without consuming it
    # In that case, we pass 0 as total
    {task_list, total} = materialize_if_needed(tasks)

    max_concurrency = resolve_max_concurrency(config, opts)
    timeout = resolve_timeout(config, opts)
    ordered = Keyword.get(opts, :ordered, @default_ordered)
    on_timeout = Keyword.get(opts, :on_timeout, :kill_task)

    task_list
    |> Task.async_stream(
      &execute_task(&1, config),
      max_concurrency: max_concurrency,
      timeout: timeout,
      ordered: ordered,
      on_timeout: on_timeout
    )
    |> Stream.with_index(1)
    |> Enum.map(fn {result, index} ->
      task_result = handle_task_result(result, index, config)
      callback.(task_result, index, total)
      task_result
    end)
  end

  # Private Functions

  defp resolve_max_concurrency(config, opts) do
    Keyword.get(opts, :max_concurrency) ||
      Keyword.get(opts, :max_parallel) ||
      get_in(config.config, [:max_concurrency]) ||
      get_in(config.config, [:max_parallel]) ||
      @default_max_concurrency
  end

  defp resolve_timeout(config, opts) do
    Keyword.get(opts, :timeout) ||
      get_in(config.config, [:timeout]) ||
      @default_timeout
  end

  defp materialize_if_needed(tasks) when is_list(tasks) do
    {tasks, length(tasks)}
  end

  defp materialize_if_needed(tasks) do
    task_list = Enum.to_list(tasks)
    {task_list, length(task_list)}
  end

  defp execute_task(task, _config) do
    # Rate limiting (if rate limiter is running)
    if Process.whereis(RateLimiter) do
      RateLimiter.acquire()
    end

    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        task.condition.fn.(task.query)
      rescue
        e -> {:error, Exception.message(e)}
      catch
        :exit, {:timeout, _} -> {:error, :timeout}
        kind, reason -> {:error, {kind, reason}}
      end

    end_time = System.monotonic_time(:millisecond)
    elapsed_time = end_time - start_time

    # Emit per-task telemetry
    lineage = resolve_lineage(task)
    telemetry_meta = build_lineage_metadata(lineage)

    :telemetry.execute(
      [:research_harness, :task, :complete],
      %{duration: elapsed_time},
      Map.merge(
        %{
          experiment_id: task.experiment_id,
          condition: task.condition.name,
          repeat: task.repeat,
          engine: :async_stream
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

  defp handle_task_result({:ok, result}, index, _config) do
    # Update progress tracker if available
    if Process.whereis(ProgressTracker) do
      ProgressTracker.update(index)
    end

    result
  end

  defp handle_task_result({:exit, :timeout}, index, config) do
    if Process.whereis(ProgressTracker) do
      ProgressTracker.update(index)
    end

    %{
      experiment_id: config.experiment_id,
      condition: :unknown,
      repeat: 0,
      query_id: :unknown,
      result: {:error, :timeout},
      elapsed_time: nil,
      timestamp: DateTime.utc_now()
    }
  end

  defp handle_task_result({:exit, reason}, index, config) do
    if Process.whereis(ProgressTracker) do
      ProgressTracker.update(index)
    end

    %{
      experiment_id: config.experiment_id,
      condition: :unknown,
      repeat: 0,
      query_id: :unknown,
      result: {:error, {:exit, reason}},
      elapsed_time: nil,
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
