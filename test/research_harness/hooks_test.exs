defmodule CrucibleHarness.HooksTest do
  use ExUnit.Case, async: true

  alias CrucibleHarness.Hooks.Executor

  describe "lifecycle hooks" do
    defmodule HookTestExperiment do
      use CrucibleHarness.Experiment

      name("Hook Test Experiment")
      dataset(:test_dataset)

      conditions([
        %{name: "test_condition", fn: &__MODULE__.test_condition/1}
      ])

      metrics([:value])
      repeat(1)

      # Track hook calls in process dictionary
      before_experiment(fn config ->
        Process.put(:before_experiment_called, true)
        Process.put(:before_experiment_config, config.name)
        {:ok, Map.put(config, :hook_modified, true)}
      end)

      after_experiment(fn _config, results ->
        Process.put(:after_experiment_called, true)
        Process.put(:after_experiment_results_count, length(results))
        :ok
      end)

      before_condition(fn _condition, _query ->
        current = Process.get(:before_condition_calls, 0)
        Process.put(:before_condition_calls, current + 1)
        :ok
      end)

      after_condition(fn _condition, _query, _result ->
        current = Process.get(:after_condition_calls, 0)
        Process.put(:after_condition_calls, current + 1)
        :ok
      end)

      on_error(fn _condition, _query, error ->
        Process.put(:on_error_called, true)
        Process.put(:on_error_reason, error)
        :skip
      end)

      def test_condition(_query) do
        %{value: 42}
      end
    end

    test "hooks are defined in experiment config" do
      config = HookTestExperiment.__config__()

      assert is_function(config.hooks.before_experiment, 1)
      assert is_function(config.hooks.after_experiment, 2)
      assert is_function(config.hooks.before_condition, 2)
      assert is_function(config.hooks.after_condition, 3)
      assert is_function(config.hooks.on_error, 3)
    end

    test "before_experiment hook is called and can modify config" do
      config = HookTestExperiment.__config__()

      assert {:ok, modified_config} =
               Executor.run_before_experiment(config.hooks.before_experiment, config)

      assert Process.get(:before_experiment_called) == true
      assert Process.get(:before_experiment_config) == "Hook Test Experiment"
      assert modified_config.hook_modified == true
    end

    test "after_experiment hook is called with results" do
      config = HookTestExperiment.__config__()
      results = [%{test: "result1"}, %{test: "result2"}]

      assert :ok =
               Executor.run_after_experiment(config.hooks.after_experiment, config, results)

      assert Process.get(:after_experiment_called) == true
      assert Process.get(:after_experiment_results_count) == 2
    end

    test "before_condition hook is called for each task" do
      config = HookTestExperiment.__config__()
      condition = %{name: "test"}
      query = %{id: "q1"}

      assert :ok = Executor.run_before_condition(config.hooks.before_condition, condition, query)
      assert :ok = Executor.run_before_condition(config.hooks.before_condition, condition, query)

      assert Process.get(:before_condition_calls) == 2
    end

    test "after_condition hook is called after each task" do
      config = HookTestExperiment.__config__()
      condition = %{name: "test"}
      query = %{id: "q1"}
      result = %{value: 42}

      assert :ok =
               Executor.run_after_condition(
                 config.hooks.after_condition,
                 condition,
                 query,
                 result
               )

      assert Process.get(:after_condition_calls) == 1
    end

    test "on_error hook is called on failures" do
      config = HookTestExperiment.__config__()
      condition = %{name: "test"}
      query = %{id: "q1"}
      error = {:error, :timeout}

      assert :skip = Executor.run_on_error(config.hooks.on_error, condition, query, error)

      assert Process.get(:on_error_called) == true
      assert Process.get(:on_error_reason) == {:error, :timeout}
    end

    test "hook errors are handled gracefully" do
      failing_hook = fn _config ->
        raise "Hook failed!"
      end

      config = HookTestExperiment.__config__()

      # Should return error tuple, not crash
      assert {:error, _reason} = Executor.run_before_experiment(failing_hook, config)
    end

    test "hooks with nil are skipped" do
      config = %{hooks: %{before_experiment: nil}}

      # Should succeed without calling anything
      assert {:ok, ^config} = Executor.run_before_experiment(nil, config)
    end
  end

  describe "on_error hook actions" do
    test "on_error can return :retry" do
      on_error_hook = fn _condition, _query, _error -> :retry end

      assert :retry ==
               Executor.run_on_error(
                 on_error_hook,
                 %{name: "test"},
                 %{id: "q1"},
                 {:error, :timeout}
               )
    end

    test "on_error can return :skip" do
      on_error_hook = fn _condition, _query, _error -> :skip end

      assert :skip ==
               Executor.run_on_error(
                 on_error_hook,
                 %{name: "test"},
                 %{id: "q1"},
                 {:error, :timeout}
               )
    end

    test "on_error can return :abort" do
      on_error_hook = fn _condition, _query, _error -> :abort end

      assert :abort ==
               Executor.run_on_error(
                 on_error_hook,
                 %{name: "test"},
                 %{id: "q1"},
                 {:error, :timeout}
               )
    end
  end
end
