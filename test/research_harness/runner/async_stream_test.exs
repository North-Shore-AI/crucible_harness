defmodule CrucibleHarness.Runner.AsyncStreamTest do
  use ExUnit.Case, async: true

  alias CrucibleHarness.Runner.AsyncStream

  # Helper to create a minimal config
  defp make_config(opts \\ []) do
    %{
      experiment_id: "test_exp_#{:rand.uniform(10000)}",
      config: Map.new(opts)
    }
  end

  # Helper to create test tasks
  defp make_tasks(count, delay_ms \\ 0) do
    for i <- 1..count do
      %{
        experiment_id: "test_exp",
        condition: %{
          name: "test_condition",
          fn: fn _query ->
            if delay_ms > 0, do: Process.sleep(delay_ms)
            %{result: i, accuracy: 0.9}
          end
        },
        repeat: 1,
        query: %{id: "query_#{i}", question: "test question #{i}"},
        timeout: 30_000,
        lineage: %{}
      }
    end
  end

  describe "run_tasks/3" do
    test "executes all tasks and returns results" do
      config = make_config()
      tasks = make_tasks(5)

      results = AsyncStream.run_tasks(tasks, config)

      assert length(results) == 5
      assert Enum.all?(results, &is_map/1)
      assert Enum.all?(results, &Map.has_key?(&1, :result))
      assert Enum.all?(results, &Map.has_key?(&1, :elapsed_time))
    end

    test "respects max_concurrency option" do
      config = make_config()

      # Create tasks that track when they start/end
      parent = self()

      tasks =
        for i <- 1..10 do
          %{
            experiment_id: "test_exp",
            condition: %{
              name: "tracking_condition",
              fn: fn _query ->
                send(parent, {:started, i, self()})
                Process.sleep(50)
                send(parent, {:finished, i, self()})
                %{result: i}
              end
            },
            repeat: 1,
            query: %{id: "query_#{i}"},
            timeout: 5000,
            lineage: %{}
          }
        end

      # Run with max_concurrency of 2
      spawn(fn ->
        AsyncStream.run_tasks(tasks, config, max_concurrency: 2)
        send(parent, :done)
      end)

      # Collect messages to analyze concurrency
      messages = collect_messages_until(:done, 5000)

      # Analyze that at most 2 tasks were running concurrently
      max_concurrent = analyze_max_concurrent(messages)

      assert max_concurrent <= 2,
             "Expected max 2 concurrent tasks, got #{max_concurrent}"
    end

    test "respects timeout option" do
      config = make_config()

      # Create a task that takes longer than the timeout
      tasks = [
        %{
          experiment_id: "test_exp",
          condition: %{
            name: "slow_condition",
            fn: fn _query ->
              Process.sleep(5000)
              %{result: "should not complete"}
            end
          },
          repeat: 1,
          query: %{id: "query_1"},
          timeout: 100,
          lineage: %{}
        }
      ]

      results = AsyncStream.run_tasks(tasks, config, timeout: 100)

      assert length(results) == 1
      result = hd(results)
      # The result should indicate timeout/error
      assert result.result == {:error, :timeout} or
               match?({:error, {:exit, _}}, result.result) or
               result.result == nil
    end

    test "produces results in stable order when ordered: true" do
      config = make_config()

      # Create tasks with varying delays
      tasks =
        for i <- 1..10 do
          # Pseudo-random delays
          delay = rem(i * 7, 5) * 10

          %{
            experiment_id: "test_exp",
            condition: %{
              name: "ordered_condition",
              fn: fn query ->
                Process.sleep(delay)
                %{result: query.id}
              end
            },
            repeat: 1,
            query: %{id: "query_#{i}"},
            timeout: 5000,
            lineage: %{}
          }
        end

      results = AsyncStream.run_tasks(tasks, config, ordered: true, max_concurrency: 3)

      # Verify order is preserved
      result_ids = Enum.map(results, & &1.query_id)
      expected_ids = Enum.map(1..10, &"query_#{&1}")

      assert result_ids == expected_ids,
             "Results should be in order when ordered: true"
    end

    test "handles task errors gracefully" do
      config = make_config()

      tasks = [
        %{
          experiment_id: "test_exp",
          condition: %{
            name: "error_condition",
            fn: fn _query ->
              raise "Intentional error"
            end
          },
          repeat: 1,
          query: %{id: "query_1"},
          timeout: 5000,
          lineage: %{}
        },
        %{
          experiment_id: "test_exp",
          condition: %{
            name: "success_condition",
            fn: fn _query ->
              %{result: "success"}
            end
          },
          repeat: 1,
          query: %{id: "query_2"},
          timeout: 5000,
          lineage: %{}
        }
      ]

      results = AsyncStream.run_tasks(tasks, config)

      assert length(results) == 2

      # First task should have error result
      error_result = Enum.find(results, &(&1.query_id == "query_1"))
      assert match?({:error, _}, error_result.result)

      # Second task should succeed
      success_result = Enum.find(results, &(&1.query_id == "query_2"))
      assert success_result.result == %{result: "success"}
    end

    test "works with stream input" do
      config = make_config()

      # Create tasks as a stream
      task_stream =
        Stream.map(1..5, fn i ->
          %{
            experiment_id: "test_exp",
            condition: %{
              name: "stream_condition",
              fn: fn _query ->
                %{result: i * 2}
              end
            },
            repeat: 1,
            query: %{id: "query_#{i}"},
            timeout: 5000,
            lineage: %{}
          }
        end)

      results = AsyncStream.run_tasks(task_stream, config)

      assert length(results) == 5
      assert Enum.all?(results, &is_map(&1.result))
    end
  end

  describe "stream_tasks/3" do
    test "returns a stream that can be consumed lazily" do
      config = make_config()
      tasks = make_tasks(10)

      stream = AsyncStream.stream_tasks(tasks, config)

      # Verify it's a stream
      assert is_struct(stream, Stream) or is_function(stream, 2)

      # Take only first 3 results
      results = stream |> Stream.take(3) |> Enum.to_list()

      assert length(results) == 3
    end

    test "supports early termination" do
      config = make_config()
      parent = self()

      tasks =
        for i <- 1..100 do
          %{
            experiment_id: "test_exp",
            condition: %{
              name: "tracking_condition",
              fn: fn _query ->
                send(parent, {:executed, i})
                %{result: i}
              end
            },
            repeat: 1,
            query: %{id: "query_#{i}"},
            timeout: 5000,
            lineage: %{}
          }
        end

      # Take only 5 results from the stream
      _results =
        tasks
        |> AsyncStream.stream_tasks(config, max_concurrency: 2)
        |> Stream.take(5)
        |> Enum.to_list()

      # Wait a bit for any remaining messages
      Process.sleep(100)

      # Collect all :executed messages
      executed = collect_all_messages(:executed)

      # Due to async nature, some extra tasks may have started
      # but we shouldn't have executed all 100
      assert length(executed) < 100,
             "Expected fewer than 100 tasks executed for early termination"
    end
  end

  describe "run_tasks_with_progress/4" do
    test "calls progress callback for each result" do
      config = make_config()
      tasks = make_tasks(5)
      parent = self()

      callback = fn result, count, total ->
        send(parent, {:progress, count, total, result.query_id})
        :ok
      end

      results = AsyncStream.run_tasks_with_progress(tasks, config, callback)

      assert length(results) == 5

      # Collect progress messages
      progress_messages = collect_all_messages(:progress)

      assert length(progress_messages) == 5
      # Verify counts are sequential
      counts = Enum.map(progress_messages, fn {_, count, _, _} -> count end)
      assert counts == [1, 2, 3, 4, 5]
    end

    test "provides correct total count" do
      config = make_config()
      tasks = make_tasks(7)
      parent = self()

      callback = fn _result, _count, total ->
        send(parent, {:total, total})
        :ok
      end

      AsyncStream.run_tasks_with_progress(tasks, config, callback)

      totals = collect_all_messages(:total)
      assert Enum.all?(totals, fn {_, t} -> t == 7 end)
    end
  end

  # Helper functions

  defp collect_messages_until(stop_message, timeout) do
    collect_messages_until(stop_message, timeout, [])
  end

  defp collect_messages_until(stop_message, timeout, acc) do
    receive do
      ^stop_message ->
        Enum.reverse(acc)

      msg ->
        collect_messages_until(stop_message, timeout, [msg | acc])
    after
      timeout ->
        Enum.reverse(acc)
    end
  end

  defp collect_all_messages(tag) do
    collect_all_messages(tag, [])
  end

  defp collect_all_messages(tag, acc) do
    receive do
      {^tag, _} = msg ->
        collect_all_messages(tag, [msg | acc])

      {^tag, _, _} = msg ->
        collect_all_messages(tag, [msg | acc])

      {^tag, _, _, _} = msg ->
        collect_all_messages(tag, [msg | acc])
    after
      0 ->
        Enum.reverse(acc)
    end
  end

  defp analyze_max_concurrent(messages) do
    # Track active tasks at each point in time
    messages
    |> Enum.reduce({0, 0}, fn
      {:started, _, _}, {current, max} ->
        new_current = current + 1
        {new_current, max(new_current, max)}

      {:finished, _, _}, {current, max} ->
        {current - 1, max}

      _, acc ->
        acc
    end)
    |> elem(1)
  end
end
