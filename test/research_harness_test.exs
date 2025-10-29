defmodule ResearchHarnessTest do
  use ExUnit.Case
  # doctest CrucibleHarness - Disabled: examples prompt for user input which hangs tests

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
      rate_limit: 400
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

  describe "runner" do
    test "runs a simple experiment" do
      config = SimpleExperiment.__config__()
      {:ok, results} = CrucibleHarness.Runner.run_experiment(config)

      assert is_list(results)
      assert length(results) > 0

      # Check first result has expected structure
      first = List.first(results)
      assert is_map(first)
      assert Map.has_key?(first, :experiment_id)
      assert Map.has_key?(first, :condition)
      assert Map.has_key?(first, :result)
    end

    test "respects repeat count" do
      config = SimpleExperiment.__config__()
      {:ok, results} = CrucibleHarness.Runner.run_experiment(config)

      # Should have results for each condition * repeat * dataset_size
      # 2 conditions * 2 repeats * 100 samples (default) = 400
      assert length(results) == 400
    end
  end

  describe "metrics aggregator" do
    test "aggregates results correctly" do
      config = SimpleExperiment.__config__()
      {:ok, results} = CrucibleHarness.Runner.run_experiment(config)

      aggregated = CrucibleHarness.Collector.MetricsAggregator.aggregate(results, config)

      assert is_list(aggregated)
      # 2 conditions
      assert length(aggregated) == 2

      # Each aggregation should have statistics
      Enum.each(aggregated, fn agg ->
        assert Map.has_key?(agg, :condition)
        assert Map.has_key?(agg, :n)
        assert Map.has_key?(agg, :metrics)
      end)
    end
  end

  describe "statistical analyzer" do
    test "performs statistical analysis" do
      config = SimpleExperiment.__config__()
      {:ok, results} = CrucibleHarness.Runner.run_experiment(config)
      aggregated = CrucibleHarness.Collector.MetricsAggregator.aggregate(results, config)

      analysis = CrucibleHarness.Collector.StatisticalAnalyzer.analyze(aggregated, config)

      assert is_map(analysis)
      assert Map.has_key?(analysis, :comparisons)
      assert Map.has_key?(analysis, :effect_sizes)
      assert Map.has_key?(analysis, :confidence_intervals)
    end
  end

  describe "reporter" do
    test "generates markdown report" do
      config = SimpleExperiment.__config__()
      {:ok, results} = CrucibleHarness.Runner.run_experiment(config)
      aggregated = CrucibleHarness.Collector.MetricsAggregator.aggregate(results, config)
      analysis = CrucibleHarness.Collector.StatisticalAnalyzer.analyze(aggregated, config)

      report_data = %{
        aggregated_results: aggregated,
        statistical_analysis: analysis,
        comparison_matrices: %{}
      }

      markdown = CrucibleHarness.Reporter.MarkdownGenerator.generate(config, report_data)

      assert is_binary(markdown)
      assert String.contains?(markdown, config.name)
      assert String.contains?(markdown, "## Results")
      assert String.contains?(markdown, "## Statistical Analysis")
    end

    test "generates HTML report" do
      config = SimpleExperiment.__config__()
      {:ok, results} = CrucibleHarness.Runner.run_experiment(config)
      aggregated = CrucibleHarness.Collector.MetricsAggregator.aggregate(results, config)
      analysis = CrucibleHarness.Collector.StatisticalAnalyzer.analyze(aggregated, config)

      report_data = %{
        aggregated_results: aggregated,
        statistical_analysis: analysis,
        comparison_matrices: %{}
      }

      html = CrucibleHarness.Reporter.HTMLGenerator.generate(config, report_data)

      assert is_binary(html)
      assert String.contains?(html, "<!DOCTYPE html>")
      assert String.contains?(html, config.name)
    end
  end

  describe "full integration" do
    @tag timeout: 120_000
    test "runs complete experiment with report generation" do
      result =
        CrucibleHarness.run(SimpleExperiment,
          output_dir: "./test_output",
          formats: [:markdown],
          confirm: false
        )

      assert {:ok, report} = result
      assert is_map(report)
      assert Map.has_key?(report, :experiment_id)
      assert Map.has_key?(report, :results)
      assert Map.has_key?(report, :analysis)
      assert Map.has_key?(report, :reports)

      # Clean up
      File.rm_rf!("./test_output")
    end
  end
end
