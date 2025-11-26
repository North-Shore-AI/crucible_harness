defmodule CrucibleHarness.Errors.Retry do
  @moduledoc false

  alias CrucibleHarness.Errors.Classifier

  def calculate_delay(attempt, config) do
    strategy = Map.get(config, :retry_strategy, :exponential_backoff)
    initial = Map.get(config, :initial_delay_ms, 1_000)
    factor = Map.get(config, :backoff_factor, 2.0)
    max_delay = Map.get(config, :max_delay_ms, 30_000)
    jitter? = Map.get(config, :jitter, false)

    base_delay =
      case strategy do
        :constant ->
          initial

        :linear ->
          trunc(initial * (attempt + 1) * factor)

        _ ->
          trunc(initial * :math.pow(factor, attempt))
      end

    delay = min(base_delay, max_delay)

    if jitter? do
      jitter_factor = 0.5 + :rand.uniform() / 2
      trunc(delay * jitter_factor)
    else
      delay
    end
  end

  def should_retry?(error, attempt, config \\ %{}) do
    max_retries = Map.get(config, :max_retries, 3)
    reason = normalize_error(error)
    Classifier.retryable?(reason, config) and attempt < max_retries
  end

  def execute_with_retry(task_fn, config \\ %{}) when is_function(task_fn, 0) do
    do_execute(task_fn, config, 0, [], [])
  end

  defp do_execute(task_fn, config, attempt, delays, history) do
    case task_fn.() do
      {:ok, _} = ok ->
        build_result(:success, ok, attempt + 1, delays, history)

      {:error, _} = error ->
        handle_error(task_fn, config, attempt, delays, history, error)

      other ->
        handle_error(
          task_fn,
          config,
          attempt,
          delays,
          history,
          {:error, {:unexpected_return, other}}
        )
    end
  end

  defp handle_error(task_fn, config, attempt, delays, history, {:error, reason} = error) do
    normalized = normalize_error(reason)
    new_history = [%{attempt: attempt + 1, error: error, timestamp: DateTime.utc_now()} | history]

    cond do
      not Classifier.retryable?(normalized, config) ->
        build_result(:failed_permanent, error, attempt + 1, delays, new_history)

      attempt >= Map.get(config, :max_retries, 3) ->
        build_result(:failed_retries_exhausted, error, attempt + 1, delays, new_history)

      true ->
        delay = calculate_delay(attempt, config)
        do_execute(task_fn, config, attempt + 1, [delay | delays], new_history)
    end
  end

  defp build_result(status, result, attempts, delays, history) do
    %{
      status: status,
      final_status: status,
      result: result,
      attempts: attempts,
      retry_delays: Enum.reverse(delays),
      error_history: Enum.reverse(history)
    }
  end

  defp normalize_error({:error, reason}), do: reason
  defp normalize_error(reason), do: reason

  defmodule CircuitBreaker do
    @moduledoc false

    defstruct max_failure_rate: 0.2, window_size: 50, window: []

    def new(opts \\ []) do
      %__MODULE__{
        max_failure_rate: Keyword.get(opts, :max_failure_rate, 0.2),
        window_size: Keyword.get(opts, :window_size, 50),
        window: []
      }
    end

    def record_success(%__MODULE__{} = circuit) do
      update_window(circuit, :success)
    end

    def record_failure(%__MODULE__{} = circuit) do
      update_window(circuit, :failure)
    end

    def failure_rate(%__MODULE__{window: []}), do: 0.0

    def failure_rate(%__MODULE__{window: window}) do
      failures = Enum.count(window, &(&1 == :failure))
      total = max(Enum.count(window), 1)
      failures / total
    end

    def should_abort?(%__MODULE__{} = circuit) do
      failure_rate(circuit) > circuit.max_failure_rate
    end

    defp update_window(%__MODULE__{window: window, window_size: window_size} = circuit, outcome) do
      new_window =
        [outcome | window]
        |> Enum.take(window_size)

      %__MODULE__{circuit | window: new_window}
    end
  end
end
