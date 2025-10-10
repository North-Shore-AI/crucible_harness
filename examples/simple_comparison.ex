defmodule Examples.SimpleComparison do
  @moduledoc """
  A simple two-condition comparison experiment.

  This example demonstrates the basic usage of ResearchHarness
  for comparing two experimental conditions.
  """

  use CrucibleHarness.Experiment

  name("Simple A/B Comparison")

  description("""
  Compares two simple conditions (A and B) to demonstrate
  basic experiment setup and execution.
  """)

  dataset(:test_dataset)
  dataset_config(%{sample_size: 50})

  conditions([
    %{
      name: "baseline",
      description: "Baseline condition",
      fn: &__MODULE__.baseline/1
    },
    %{
      name: "treatment",
      description: "Treatment condition",
      fn: &__MODULE__.treatment/1
    }
  ])

  metrics([:accuracy, :latency, :cost])
  repeat(3)

  config(%{
    timeout: 10_000,
    rate_limit: 5,
    max_parallel: 5
  })

  statistical_analysis(%{
    significance_level: 0.05,
    confidence_interval: 0.95,
    multiple_testing_correction: :bonferroni
  })

  # Condition implementations

  def baseline(query) do
    # Simulate a baseline condition with some variance
    latency = 100 + :rand.uniform(50)
    accuracy = 0.70 + :rand.uniform() * 0.1

    %{
      prediction: "Baseline answer",
      accuracy: accuracy,
      latency: latency,
      cost: 0.001
    }
  end

  def treatment(query) do
    # Simulate a treatment condition with improved performance
    latency = 120 + :rand.uniform(60)
    accuracy = 0.80 + :rand.uniform() * 0.1

    %{
      prediction: "Treatment answer",
      accuracy: accuracy,
      latency: latency,
      cost: 0.002
    }
  end
end
