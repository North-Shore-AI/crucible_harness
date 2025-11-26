defmodule CrucibleHarness.ErrorsTest do
  use ExUnit.Case, async: true

  alias CrucibleHarness.Errors.{Classifier, Retry, DLQ}

  describe "error classifier" do
    test "identifies retryable errors" do
      assert Classifier.retryable?(:timeout) == true
      assert Classifier.retryable?(:connection_refused) == true
      assert Classifier.retryable?(:rate_limited) == true
      assert Classifier.retryable?({:http_status, 429}) == true
      assert Classifier.retryable?({:http_status, 503}) == true
      assert Classifier.retryable?({:http_status, 502}) == true
    end

    test "identifies permanent errors" do
      assert Classifier.retryable?(:invalid_query) == false
      assert Classifier.retryable?(:authentication_failed) == false
      assert Classifier.retryable?({:http_status, 401}) == false
      assert Classifier.retryable?({:http_status, 403}) == false
      assert Classifier.retryable?({:http_status, 404}) == false
    end

    test "can customize retryable errors" do
      config = %{
        retryable_errors: [:custom_error],
        permanent_errors: [:another_error]
      }

      assert Classifier.retryable?(:custom_error, config) == true
      assert Classifier.retryable?(:another_error, config) == false
    end
  end

  describe "retry logic" do
    test "exponential backoff calculates correct delays" do
      config = %{
        retry_strategy: :exponential_backoff,
        initial_delay_ms: 1000,
        backoff_factor: 2.0,
        max_delay_ms: 30_000,
        jitter: false
      }

      assert Retry.calculate_delay(0, config) == 1000
      assert Retry.calculate_delay(1, config) == 2000
      assert Retry.calculate_delay(2, config) == 4000
      assert Retry.calculate_delay(3, config) == 8000
      assert Retry.calculate_delay(4, config) == 16_000
      assert Retry.calculate_delay(5, config) == 30_000
      # Capped at max
      assert Retry.calculate_delay(10, config) == 30_000
    end

    test "constant backoff returns same delay" do
      config = %{
        retry_strategy: :constant,
        initial_delay_ms: 1000
      }

      assert Retry.calculate_delay(0, config) == 1000
      assert Retry.calculate_delay(1, config) == 1000
      assert Retry.calculate_delay(5, config) == 1000
    end

    test "linear backoff increases linearly" do
      config = %{
        retry_strategy: :linear,
        initial_delay_ms: 1000,
        backoff_factor: 1.0
      }

      assert Retry.calculate_delay(0, config) == 1000
      assert Retry.calculate_delay(1, config) == 2000
      assert Retry.calculate_delay(2, config) == 3000
    end

    test "jitter adds randomness" do
      config = %{
        retry_strategy: :exponential_backoff,
        initial_delay_ms: 1000,
        backoff_factor: 2.0,
        max_delay_ms: 30_000,
        jitter: true
      }

      # With jitter, delay should be between 50% and 100% of calculated value
      delay = Retry.calculate_delay(2, config)
      # 4000 without jitter
      assert delay >= 2000 and delay <= 4000
    end

    test "should_retry respects max_retries" do
      config = %{max_retries: 3}

      assert Retry.should_retry?(:timeout, 0, config) == true
      assert Retry.should_retry?(:timeout, 1, config) == true
      assert Retry.should_retry?(:timeout, 2, config) == true
      assert Retry.should_retry?(:timeout, 3, config) == false
      assert Retry.should_retry?(:timeout, 4, config) == false
    end

    test "should_retry checks error type" do
      config = %{max_retries: 3}

      assert Retry.should_retry?(:timeout, 0, config) == true
      assert Retry.should_retry?(:invalid_query, 0, config) == false
      assert Retry.should_retry?(:authentication_failed, 0, config) == false
    end

    test "execute_with_retry succeeds on first attempt" do
      task_fn = fn -> {:ok, "success"} end

      config = %{
        max_retries: 3,
        retry_strategy: :exponential_backoff,
        initial_delay_ms: 100,
        backoff_factor: 2.0,
        max_delay_ms: 1000,
        jitter: false
      }

      result = Retry.execute_with_retry(task_fn, config)

      assert result.status == :success
      assert result.result == {:ok, "success"}
      assert result.attempts == 1
      assert result.retry_delays == []
    end

    test "execute_with_retry retries on transient errors" do
      # Fail twice, then succeed
      agent = start_supervised!({Agent, fn -> 0 end})

      task_fn = fn ->
        count = Agent.get_and_update(agent, fn count -> {count, count + 1} end)

        case count do
          0 -> {:error, :timeout}
          1 -> {:error, :timeout}
          _ -> {:ok, "success"}
        end
      end

      config = %{
        max_retries: 3,
        retry_strategy: :constant,
        initial_delay_ms: 10,
        jitter: false
      }

      result = Retry.execute_with_retry(task_fn, config)

      assert result.status == :success
      assert result.result == {:ok, "success"}
      assert result.attempts == 3
      assert length(result.retry_delays) == 2
      assert Enum.all?(result.error_history, &match?(%{error: _}, &1))
    end

    test "execute_with_retry stops on permanent errors" do
      task_fn = fn -> {:error, :authentication_failed} end

      config = %{
        max_retries: 3,
        retry_strategy: :constant,
        initial_delay_ms: 10
      }

      result = Retry.execute_with_retry(task_fn, config)

      assert result.status == :failed_permanent
      assert result.result == {:error, :authentication_failed}
      assert result.attempts == 1
      assert result.retry_delays == []
    end

    test "execute_with_retry gives up after max_retries" do
      task_fn = fn -> {:error, :timeout} end

      config = %{
        max_retries: 2,
        retry_strategy: :constant,
        initial_delay_ms: 10,
        jitter: false
      }

      result = Retry.execute_with_retry(task_fn, config)

      assert result.status == :failed_retries_exhausted
      assert result.result == {:error, :timeout}
      assert result.attempts == 3
      # 2 retries
      assert length(result.retry_delays) == 2
    end
  end

  describe "dead letter queue" do
    setup do
      # Use temp directory for DLQ file
      temp_dir = System.tmp_dir!()
      dlq_path = Path.join(temp_dir, "test_dlq_#{System.unique_integer([:positive])}.jsonl")

      on_exit(fn ->
        if File.exists?(dlq_path), do: File.rm!(dlq_path)
      end)

      {:ok, dlq_path: dlq_path}
    end

    test "writes failed task to DLQ", %{dlq_path: dlq_path} do
      task = %{
        experiment_id: "exp_123",
        condition: "test_condition",
        query_id: "q_456",
        query: %{text: "test query"}
      }

      error = {:error, :authentication_failed}

      retry_result = %{
        status: :failed_permanent,
        result: error,
        attempts: 1,
        retry_delays: [],
        error_history: [%{attempt: 1, error: error, timestamp: DateTime.utc_now()}],
        final_status: :failed_permanent
      }

      assert :ok = DLQ.write(task, retry_result, dlq_path)

      # Verify file was created and contains JSON
      assert File.exists?(dlq_path)
      content = File.read!(dlq_path)
      assert String.contains?(content, "exp_123")
      assert String.contains?(content, "test_condition")
      assert String.contains?(content, "authentication_failed")
    end

    test "appends multiple entries to DLQ", %{dlq_path: dlq_path} do
      task1 = %{experiment_id: "exp_1", condition: "c1", query_id: "q1", query: %{}}
      task2 = %{experiment_id: "exp_2", condition: "c2", query_id: "q2", query: %{}}

      retry_result = %{
        status: :failed_permanent,
        result: {:error, :test},
        attempts: 1,
        retry_delays: [],
        error_history: [],
        final_status: :failed_permanent
      }

      DLQ.write(task1, retry_result, dlq_path)
      DLQ.write(task2, retry_result, dlq_path)

      lines = File.read!(dlq_path) |> String.split("\n", trim: true)
      assert length(lines) == 2
    end

    test "reads failed tasks from DLQ", %{dlq_path: dlq_path} do
      task = %{experiment_id: "exp_123", condition: "c1", query_id: "q1", query: %{}}

      retry_result = %{
        status: :failed_permanent,
        result: {:error, :test},
        attempts: 1,
        retry_delays: [],
        error_history: [],
        final_status: :failed_permanent
      }

      DLQ.write(task, retry_result, dlq_path)

      {:ok, entries} = DLQ.read(dlq_path)
      assert length(entries) == 1
      assert hd(entries).experiment_id == "exp_123"
    end
  end

  describe "circuit breaker" do
    test "tracks failure rate" do
      circuit = Retry.CircuitBreaker.new(max_failure_rate: 0.1, window_size: 10)

      # Add 9 successes, 1 failure = 10% failure rate (at threshold)
      circuit =
        circuit
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_failure()

      assert Retry.CircuitBreaker.failure_rate(circuit) == 0.1
      assert Retry.CircuitBreaker.should_abort?(circuit) == false
    end

    test "opens when failure rate exceeds threshold" do
      circuit = Retry.CircuitBreaker.new(max_failure_rate: 0.1, window_size: 10)

      # Add 8 successes, 2 failures = 20% failure rate (above 10% threshold)
      circuit =
        circuit
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_success()
        |> Retry.CircuitBreaker.record_failure()
        |> Retry.CircuitBreaker.record_failure()

      assert Retry.CircuitBreaker.failure_rate(circuit) == 0.2
      assert Retry.CircuitBreaker.should_abort?(circuit) == true
    end

    test "uses sliding window" do
      circuit = Retry.CircuitBreaker.new(max_failure_rate: 0.1, window_size: 5)

      # Add 5 successes (window full, 0% failure rate)
      circuit =
        1..5
        |> Enum.reduce(circuit, fn _, c -> Retry.CircuitBreaker.record_success(c) end)

      assert Retry.CircuitBreaker.failure_rate(circuit) == 0.0

      # Add 1 failure (oldest success drops out, now 1/5 = 20% failure rate)
      circuit = Retry.CircuitBreaker.record_failure(circuit)

      assert Retry.CircuitBreaker.failure_rate(circuit) == 0.2
      assert Retry.CircuitBreaker.should_abort?(circuit) == true
    end
  end
end
