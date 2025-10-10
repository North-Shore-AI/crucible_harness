defmodule ResearchHarnessTest do
  use ExUnit.Case
  doctest CrucibleHarness

  alias CrucibleHarness.Experiment

  # Test experiment module
  defmodule SimpleExperiment do
    use CrucibleHarness.Experiment

    name("Simple Test Experiment")
    description("A simple experiment for testing")
    dataset(:test_dataset)

    conditions([
      %{name: "condition_a", fn: &__MODULE__.condition_a/1},
      %{name: "condition_b", fn: &__MODULE__.condition_b/1}
    ])

    metrics([:accuracy, :latency])
    repeat(2)

    config(%{
      timeout: 5_000,
      rate_limit: 10
    })

    def condition_a(_query) do
      %{
        prediction: "A",
        accuracy: 0.8,
        latency: 100
      }
    end

    def condition_b(_query) do
      %{
        prediction: "B",
        accuracy: 0.85,
        latency: 150
      }
    end
  end

  describe "experiment validation" do
    test "validates a valid experiment" do
      assert {:ok, config} = Experiment.Validator.validate(SimpleExperiment)
      assert config.name == "Simple Test Experiment"
      assert length(config.conditions) == 2
      assert length(config.metrics) == 2
    end

    test "requires name" do
      defmodule NoNameExperiment do
        use CrucibleHarness.Experiment
        dataset(:test)
        conditions([%{name: "test", fn: &Function.identity/1}])
        metrics([:accuracy])
      end

      # The name will be set to "Unnamed Experiment" by default
      assert {:ok, config} = Experiment.Validator.validate(NoNameExperiment)
      assert config.name == "Unnamed Experiment"
    end

    test "requires at least one condition" do
      defmodule NoConditionsExperiment do
        use CrucibleHarness.Experiment
        name("Test")
        dataset(:test)
        conditions([])
        metrics([:accuracy])
      end

      assert {:error, _} = Experiment.Validator.validate(NoConditionsExperiment)
    end

    test "requires at least one metric" do
      defmodule NoMetricsExperiment do
        use CrucibleHarness.Experiment
        name("Test")
        dataset(:test)
        conditions([%{name: "test", fn: &Function.identity/1}])
        metrics([])
      end

      assert {:error, _} = Experiment.Validator.validate(NoMetricsExperiment)
    end
  end

  describe "cost estimation" do
    test "estimates experiment costs" do
      config = SimpleExperiment.__config__()
      estimate = CrucibleHarness.Utilities.CostEstimator.estimate(config)

      assert is_number(estimate.total_cost)
      assert estimate.total_cost > 0
      assert is_map(estimate.condition_costs)
    end
  end

  describe "time estimation" do
    test "estimates experiment duration" do
      config = SimpleExperiment.__config__()
      estimate = CrucibleHarness.Utilities.TimeEstimator.estimate(config)

      assert is_number(estimate.estimated_duration)
      assert estimate.estimated_duration > 0
      assert %DateTime{} = estimate.estimated_completion
    end
  end
end
