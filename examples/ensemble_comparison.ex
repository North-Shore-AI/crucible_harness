defmodule Examples.EnsembleComparison do
  @moduledoc """
  Compares single model performance against ensemble methods.

  This example demonstrates a more complex experiment with multiple
  conditions and custom metrics.
  """

  use CrucibleHarness.Experiment

  name("Ensemble vs Single Model Comparison")

  description("""
  Evaluates whether ensemble methods improve accuracy and reliability
  compared to single-model baselines.
  """)

  author("Research Team")
  version("1.0.0")
  tags([:ensemble, :comparison, :accuracy])

  dataset(:mmlu_200)

  dataset_config(%{
    sample_size: 100,
    shuffle: true,
    seed: 42
  })

  conditions([
    %{
      name: "single_model_a",
      description: "Single model A baseline",
      fn: &__MODULE__.single_model_a/1
    },
    %{
      name: "single_model_b",
      description: "Single model B baseline",
      fn: &__MODULE__.single_model_b/1
    },
    %{
      name: "ensemble_3",
      description: "3-model ensemble with majority voting",
      fn: &__MODULE__.ensemble_3/1
    },
    %{
      name: "ensemble_5",
      description: "5-model ensemble with majority voting",
      fn: &__MODULE__.ensemble_5/1
    }
  ])

  metrics([:accuracy, :latency, :cost, :reliability])
  repeat(5)

  custom_metrics([
    %{
      name: :cost_accuracy_ratio,
      description: "Cost per percentage point of accuracy",
      fn: fn results ->
        if results.accuracy > 0 do
          results.cost / results.accuracy
        else
          999.99
        end
      end
    }
  ])

  config(%{
    timeout: 30_000,
    rate_limit: 10,
    max_parallel: 10,
    random_seed: 42
  })

  cost_budget(%{
    max_total: 10.00,
    max_per_condition: 3.00
  })

  statistical_analysis(%{
    significance_level: 0.05,
    confidence_interval: 0.95,
    multiple_testing_correction: :bonferroni
  })

  # Condition implementations

  def single_model_a(query) do
    # Simulate a single model with moderate performance
    Process.sleep(80 + :rand.uniform(40))

    accuracy = 0.65 + :rand.uniform() * 0.15

    %{
      prediction: "Answer from Model A",
      accuracy: accuracy,
      latency: 100 + :rand.uniform(50),
      cost: 0.001,
      reliability: 0.75
    }
  end

  def single_model_b(query) do
    # Simulate another single model with different characteristics
    Process.sleep(100 + :rand.uniform(50))

    accuracy = 0.70 + :rand.uniform() * 0.15

    %{
      prediction: "Answer from Model B",
      accuracy: accuracy,
      latency: 120 + :rand.uniform(60),
      cost: 0.0015,
      reliability: 0.80
    }
  end

  def ensemble_3(query) do
    # Simulate a 3-model ensemble
    Process.sleep(200 + :rand.uniform(100))

    # Ensemble generally improves accuracy
    accuracy = 0.75 + :rand.uniform() * 0.15

    %{
      prediction: "Ensemble answer (3 models)",
      accuracy: accuracy,
      latency: 250 + :rand.uniform(100),
      cost: 0.003,
      reliability: 0.85
    }
  end

  def ensemble_5(query) do
    # Simulate a 5-model ensemble
    Process.sleep(300 + :rand.uniform(150))

    # Larger ensemble potentially improves accuracy further
    accuracy = 0.80 + :rand.uniform() * 0.12

    %{
      prediction: "Ensemble answer (5 models)",
      accuracy: accuracy,
      latency: 400 + :rand.uniform(150),
      cost: 0.005,
      reliability: 0.90
    }
  end
end
