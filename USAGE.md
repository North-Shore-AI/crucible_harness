# ResearchHarness Usage Guide

This guide provides detailed instructions for using ResearchHarness to run AI research experiments.

## Table of Contents

1. [Basic Workflow](#basic-workflow)
2. [Defining Experiments](#defining-experiments)
3. [Running Experiments](#running-experiments)
4. [Analyzing Results](#analyzing-results)
5. [Best Practices](#best-practices)

## Basic Workflow

The typical ResearchHarness workflow consists of:

1. **Define** - Create an experiment module using the DSL
2. **Estimate** - Check cost and time estimates
3. **Run** - Execute the experiment
4. **Analyze** - Review generated reports
5. **Iterate** - Refine and repeat

## Defining Experiments

### Minimal Example

```elixir
defmodule MinimalExperiment do
  use CrucibleHarness.Experiment

  name "Minimal Experiment"
  dataset :test_dataset

  conditions [
    %{name: "baseline", fn: &baseline/1}
  ]

  metrics [:accuracy]

  def baseline(query) do
    %{accuracy: 0.8}
  end
end
```

### Complete Example

```elixir
defmodule CompleteExperiment do
  use CrucibleHarness.Experiment

  # Required fields
  name "Complete Research Experiment"
  description "A comprehensive experiment demonstrating all features"
  dataset :mmlu_200

  # Experimental conditions
  conditions [
    %{
      name: "baseline",
      description: "Baseline condition",
      fn: &baseline/1
    },
    %{
      name: "treatment_a",
      description: "Treatment A with enhancement X",
      fn: &treatment_a/1
    },
    %{
      name: "treatment_b",
      description: "Treatment B with enhancement Y",
      fn: &treatment_b/1
    }
  ]

  # Metrics to collect
  metrics [:accuracy, :latency, :cost, :reliability]

  # Optional: Custom metrics
  custom_metrics [
    %{
      name: :efficiency,
      description: "Accuracy per dollar spent",
      fn: fn results ->
        if results.cost > 0 do
          results.accuracy / results.cost
        else
          0.0
        end
      end
    }
  ]

  # Experimental design
  repeat 5

  # Execution configuration
  config %{
    timeout: 30_000,
    rate_limit: 10,
    max_parallel: 5,
    random_seed: 42,
    checkpoint_interval: 50
  }

  # Dataset configuration
  dataset_config %{
    sample_size: 100,
    shuffle: true,
    seed: 42
  }

  # Cost constraints
  cost_budget %{
    max_total: 50.00,
    max_per_condition: 20.00,
    currency: :usd
  }

  # Statistical analysis settings
  statistical_analysis %{
    significance_level: 0.05,
    confidence_interval: 0.95,
    multiple_testing_correction: :bonferroni
  }

  # Metadata
  author "Research Team"
  version "1.0.0"
  tags [:baseline, :comparison, :2024]

  # Condition implementations
  def baseline(query), do: %{accuracy: 0.75, latency: 100, cost: 0.01, reliability: 0.8}
  def treatment_a(query), do: %{accuracy: 0.82, latency: 120, cost: 0.015, reliability: 0.85}
  def treatment_b(query), do: %{accuracy: 0.85, latency: 150, cost: 0.02, reliability: 0.90}
end
```

## Running Experiments

### Step 1: Estimate Cost and Time

Always estimate before running:

```elixir
{:ok, estimates} = CrucibleHarness.estimate(MyExperiment)

IO.puts("Total queries: #{estimates.cost.total_queries}")
IO.puts("Estimated cost: $#{Float.round(estimates.cost.total_cost, 2)}")
IO.puts("Estimated time: #{format_time(estimates.time.estimated_duration)}")
```

### Step 2: Run the Experiment

Basic run:

```elixir
{:ok, report} = CrucibleHarness.run(MyExperiment)
```

With options:

```elixir
{:ok, report} = CrucibleHarness.run(MyExperiment,
  output_dir: "./my_results",
  formats: [:markdown, :latex, :html, :jupyter],
  checkpoint_dir: "./my_checkpoints",
  confirm: false  # Skip confirmation prompt
)
```

Dry run (validate only):

```elixir
CrucibleHarness.run(MyExperiment, dry_run: true)
```

### Step 3: Run Asynchronously

For long-running experiments:

```elixir
{:ok, task_ref} = CrucibleHarness.run_async(MyExperiment)

# Check status
CrucibleHarness.status(task_ref)

# Or subscribe to progress updates
CrucibleHarness.Runner.ProgressTracker.subscribe(self())

receive do
  {:progress_update, update} ->
    IO.puts("Progress: #{update.progress_pct}%")
end
```

### Step 4: Resume After Failure

If an experiment is interrupted:

```elixir
# List available checkpoints
checkpoints = CrucibleHarness.Utilities.CheckpointManager.list_checkpoints()

# Resume from checkpoint
{:ok, report} = CrucibleHarness.resume("exp_12345")
```

## Analyzing Results

### Report Formats

ResearchHarness generates multiple report formats:

#### Markdown (`.markdown`)
- Human-readable tables and statistics
- Suitable for GitHub/GitLab
- Easy to include in documentation

#### LaTeX (`.latex`)
- Publication-ready tables
- Professional formatting
- Ready to include in papers

#### HTML (`.html`)
- Interactive web view
- Styled tables and statistics
- Share via browser

#### Jupyter (`.ipynb`)
- Interactive Python notebook
- Includes visualization code
- Further analysis in Python/Jupyter

### Understanding Reports

Each report contains:

1. **Experiment Metadata** - Name, date, author, configuration
2. **Methodology** - Dataset, conditions, metrics, design
3. **Summary Statistics** - Mean, std dev, confidence intervals per condition
4. **Pairwise Comparisons** - Statistical tests between all condition pairs
5. **Comparison Matrices** - Visual comparison across all conditions

### Key Metrics

**Statistical Significance:**
- p-value < 0.05 (or configured threshold) indicates significant difference
- Effect size (Cohen's d) measures practical significance
  - Small: d = 0.2
  - Medium: d = 0.5
  - Large: d = 0.8

**Confidence Intervals:**
- 95% CI shows range where true mean likely falls
- Non-overlapping CIs suggest significant difference

## Best Practices

### 1. Start Small

Begin with a small sample to validate your experiment:

```elixir
dataset_config %{
  sample_size: 10  # Start with 10 samples
}
```

### 2. Use Cost Budgets

Prevent runaway costs:

```elixir
cost_budget %{
  max_total: 10.00,
  max_per_condition: 5.00
}
```

### 3. Set Appropriate Repetitions

More repetitions = more statistical power, but higher cost:
- Pilot studies: 3-5 repetitions
- Main experiments: 10+ repetitions
- Critical comparisons: 20+ repetitions

### 4. Configure Timeouts

Set reasonable timeouts to prevent hanging:

```elixir
config %{
  timeout: 30_000,  # 30 seconds per query
  retry_on_failure: 3,
  retry_delay: 1_000
}
```

### 5. Use Rate Limiting

Respect API rate limits:

```elixir
config %{
  rate_limit: 10,  # 10 requests per second
  max_parallel: 5  # Max 5 parallel executions
}
```

### 6. Document Your Experiments

Include comprehensive descriptions:

```elixir
description """
This experiment evaluates whether ensemble methods improve
accuracy on MMLU benchmarks. We compare:
1. Single model baselines (GPT-4, Claude)
2. 3-model ensembles
3. 5-model ensembles

Hypothesis: Ensembles will improve accuracy by 5-10% but
increase latency by 2-3x.
"""
```

### 7. Use Meaningful Condition Names

```elixir
# Good
conditions [
  %{name: "gpt4_baseline", ...},
  %{name: "ensemble_3_majority_vote", ...}
]

# Less clear
conditions [
  %{name: "cond1", ...},
  %{name: "cond2", ...}
]
```

### 8. Version Your Experiments

Track experiment versions:

```elixir
version "1.0.0"
tags [:v1, :baseline, :production]
```

### 9. Monitor Progress

Subscribe to progress updates for long experiments:

```elixir
CrucibleHarness.Runner.ProgressTracker.subscribe(self())
```

### 10. Archive Results

Keep organized records:

```bash
# Directory structure
results/
  exp_12345_2024-01-15/
    report.markdown
    report.latex
    report.html
    report.ipynb
    raw_data.csv
```

## Common Patterns

### Comparing Multiple Models

```elixir
conditions [
  %{name: "gpt4", fn: &query_model(&1, :gpt4)},
  %{name: "claude", fn: &query_model(&1, :claude)},
  %{name: "gemini", fn: &query_model(&1, :gemini)}
]

def query_model(query, model) do
  # Implementation
end
```

### Testing Parameter Ranges

```elixir
conditions for temp <- [0.0, 0.5, 1.0, 1.5] do
  %{
    name: "temp_#{temp}",
    fn: &query_with_temp(&1, temp)
  }
end
```

### Ensemble Experiments

```elixir
conditions [
  %{name: "single", fn: &single_model/1},
  %{name: "ensemble_3", fn: &ensemble(&1, 3)},
  %{name: "ensemble_5", fn: &ensemble(&1, 5)},
  %{name: "ensemble_7", fn: &ensemble(&1, 7)}
]
```

## Troubleshooting

### Experiment Fails to Start

Check validation errors:
```elixir
case CrucibleHarness.run(MyExperiment) do
  {:error, reason} -> IO.inspect(reason)
  {:ok, _} -> :ok
end
```

### Experiment Crashes Mid-Run

Resume from checkpoint:
```elixir
{:ok, report} = CrucibleHarness.resume("exp_12345")
```

### Results Seem Wrong

1. Check condition implementations
2. Verify metric calculations
3. Review dataset
4. Increase repetitions for more stable estimates

### Reports Not Generated

Check output directory permissions:
```elixir
File.mkdir_p!("./results")
```

## Next Steps

1. Review the [examples](examples/) directory
2. Read the [design document](../../../research_infra_design_docs/08-research_harness-design.md)
3. Check the API documentation with `mix docs`

## Support

For issues or questions, refer to the main ResearchHarness documentation or reach out to the development team.
