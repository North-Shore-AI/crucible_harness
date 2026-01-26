defmodule CrucibleHarness.Runner.ExecutionEngineTest do
  use ExUnit.Case

  alias CrucibleHarness.Runner

  # Test experiment module for execution engine tests
  defmodule AsyncStreamExperiment do
    use CrucibleHarness.Experiment

    name("Async Stream Test Experiment")
    description("Tests async_stream execution engine")
    dataset(:test_dataset)

    conditions([
      %{name: "condition_a", fn: &__MODULE__.condition_a/1}
    ])

    metrics([:accuracy])
    repeat(1)

    config(%{
      timeout: 5_000,
      execution_engine: :async_stream,
      max_parallel: 2
    })

    dataset_config(%{
      sample_size: 10
    })

    def condition_a(_query) do
      %{
        prediction: "A",
        accuracy: 0.8
      }
    end
  end

  defmodule FlowExperiment do
    use CrucibleHarness.Experiment

    name("Flow Test Experiment")
    description("Tests flow execution engine")
    dataset(:test_dataset)

    conditions([
      %{name: "condition_a", fn: &__MODULE__.condition_a/1}
    ])

    metrics([:accuracy])
    repeat(1)

    config(%{
      timeout: 5_000,
      execution_engine: :flow,
      max_parallel: 2
    })

    dataset_config(%{
      sample_size: 10
    })

    def condition_a(_query) do
      %{
        prediction: "A",
        accuracy: 0.8
      }
    end
  end

  defmodule StreamDataExperiment do
    use CrucibleHarness.Experiment

    name("Stream Data Experiment")
    description("Tests experiment with streaming dataset")
    dataset(:test_dataset)

    conditions([
      %{name: "condition_a", fn: &__MODULE__.condition_a/1}
    ])

    metrics([:accuracy])
    repeat(1)

    config(%{
      timeout: 5_000,
      execution_engine: :async_stream,
      max_parallel: 2
    })

    dataset_config(%{
      sample_size: 5,
      limit: 5
    })

    def condition_a(_query) do
      %{
        prediction: "A",
        accuracy: 0.9
      }
    end
  end

  describe "execution engine selection" do
    test "uses async_stream engine when configured" do
      config = AsyncStreamExperiment.__config__()

      # Run with async_stream engine
      {:ok, results} = Runner.run_experiment(config)

      assert is_list(results)
      # 10 samples * 1 condition * 1 repeat
      assert length(results) == 10
    end

    test "uses flow engine when configured" do
      config = FlowExperiment.__config__()

      # Run with flow engine
      {:ok, results} = Runner.run_experiment(config)

      assert is_list(results)
      assert length(results) == 10
    end

    test "defaults to flow engine when not specified" do
      config = FlowExperiment.__config__()
      # Remove execution_engine from config
      config = put_in(config.config, Map.delete(config.config, :execution_engine))

      {:ok, results} = Runner.run_experiment(config)

      assert is_list(results)
    end

    test "execution engine can be overridden via opts" do
      config = FlowExperiment.__config__()

      # Override to use async_stream
      {:ok, results} = Runner.run_experiment(config, execution_engine: :async_stream)

      assert is_list(results)
      assert length(results) == 10
    end
  end

  describe "dataset handling" do
    test "works with stream datasets" do
      config = StreamDataExperiment.__config__()

      {:ok, results} = Runner.run_experiment(config)

      assert is_list(results)
      # Limited to 5 samples
      assert length(results) == 5
    end

    test "respects dataset limit" do
      # Create a custom config with explicit limit
      defmodule LimitedExperiment do
        use CrucibleHarness.Experiment

        name("Limited Dataset Experiment")
        dataset(:test_dataset)

        conditions([
          %{name: "condition_a", fn: &__MODULE__.condition_a/1}
        ])

        metrics([:accuracy])
        repeat(1)

        config(%{
          timeout: 5_000,
          execution_engine: :async_stream,
          max_parallel: 2
        })

        # This is the key - sample_size controls the mock dataset size
        dataset_config(%{
          sample_size: 3
        })

        def condition_a(_query) do
          %{prediction: "A", accuracy: 0.8}
        end
      end

      config = LimitedExperiment.__config__()
      {:ok, results} = Runner.run_experiment(config)

      # 3 samples * 1 condition * 1 repeat = 3
      assert length(results) == 3
    end
  end

  describe "result structure" do
    test "async_stream results have same structure as flow results" do
      async_config = AsyncStreamExperiment.__config__()
      flow_config = FlowExperiment.__config__()

      {:ok, async_results} = Runner.run_experiment(async_config)
      {:ok, flow_results} = Runner.run_experiment(flow_config)

      async_sample = hd(async_results)
      flow_sample = hd(flow_results)

      # Both should have the same keys
      async_keys = Map.keys(async_sample) |> Enum.sort()
      flow_keys = Map.keys(flow_sample) |> Enum.sort()

      assert async_keys == flow_keys

      # Check essential keys exist
      assert Map.has_key?(async_sample, :experiment_id)
      assert Map.has_key?(async_sample, :condition)
      assert Map.has_key?(async_sample, :result)
      assert Map.has_key?(async_sample, :elapsed_time)
      assert Map.has_key?(async_sample, :timestamp)
    end
  end
end
