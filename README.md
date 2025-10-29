<p align="center">
  <img src="assets/crucible_harness.svg" alt="Harness" width="150"/>
</p>

# CrucibleHarness

[![Elixir](https://img.shields.io/badge/elixir-1.14+-purple.svg)](https://elixir-lang.org)
[![Hex.pm](https://img.shields.io/hexpm/v/crucible_harness.svg)](https://hex.pm/packages/crucible_harness)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-purple.svg)](https://hexdocs.pm/crucible_harness)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/North-Shore-AI/crucible_harness/blob/main/LICENSE)

**Automated Experiment Orchestration for AI Research**

ResearchHarness is a comprehensive Elixir library for orchestrating, executing, and analyzing large-scale AI research experiments. It provides the infrastructure to systematically run experiments across multiple conditions, datasets, and configurations while maintaining reproducibility, fault tolerance, and detailed statistical analysis.

Think of it as **"pytest + MLflow + Weights & Biases"** for Elixir AI research.

## Features

- **Declarative Experiment Definition** - DSL for expressing complex experimental designs
- **Parallel Execution** - Leverage BEAM's concurrency for efficient multi-condition runs
- **Fault Tolerance** - Resume experiments after failures without data loss
- **Statistical Analysis** - Automated significance testing across all condition pairs
- **Multi-Format Reporting** - Generate Markdown, LaTeX, HTML, and Jupyter notebooks
- **Cost Management** - Estimate and control API costs before execution
- **Reproducibility** - Version control for experiments, controlled random seeds, full audit trails

## Quick Start

### 1. Define an Experiment

```elixir
defmodule MyExperiment do
  use CrucibleHarness.Experiment

  name "My Research Experiment"
  description "Comparing baseline vs treatment"

  dataset :mmlu_200

  conditions [
    %{name: "baseline", fn: &baseline_condition/1},
    %{name: "treatment", fn: &treatment_condition/1}
  ]

  metrics [:accuracy, :latency_p99, :cost_per_query]
  repeat 3

  config %{
    timeout: 30_000,
    rate_limit: 10
  }

  def baseline_condition(query) do
    # Your implementation
    %{prediction: "answer", accuracy: 0.75, latency: 100, cost: 0.01}
  end

  def treatment_condition(query) do
    # Your implementation
    %{prediction: "answer", accuracy: 0.82, latency: 150, cost: 0.02}
  end
end
```

### 2. Run the Experiment

```elixir
# Estimate cost and time first
{:ok, estimates} = CrucibleHarness.estimate(MyExperiment)
IO.puts("Estimated cost: $#{estimates.cost.total_cost}")
IO.puts("Estimated time: #{estimates.time.estimated_duration}ms")

# Run the experiment
{:ok, report} = CrucibleHarness.run(MyExperiment,
  output_dir: "./results",
  formats: [:markdown, :latex, :html]
)
```

### 3. View Results

Reports are automatically generated in your specified formats:
- `results/exp_12345_report.markdown` - Markdown report
- `results/exp_12345_report.latex` - LaTeX tables and figures
- `results/exp_12345_report.html` - Interactive HTML report

## Advanced Features

### Parameter Sweeps

```elixir
defmodule EnsembleSizeSweep do
  use CrucibleHarness.Experiment

  name "Ensemble Size Sweep (1-10 models)"
  dataset :mmlu_200

  conditions for n <- 1..10 do
    %{
      name: "ensemble_#{n}",
      fn: &ensemble(&1, models: n)
    }
  end

  metrics [:accuracy, :latency_p99, :cost_per_query]
  repeat 5
end
```

### Cost Budgets

```elixir
cost_budget %{
  max_total: 100.00,          # $100 maximum
  max_per_condition: 25.00,   # $25 per condition max
  currency: :usd
}
```

### Statistical Analysis

```elixir
statistical_analysis %{
  significance_level: 0.05,
  multiple_testing_correction: :bonferroni,
  confidence_interval: 0.95
}
```

### Checkpointing and Resume

```elixir
# Run experiment (will checkpoint automatically)
{:ok, report} = CrucibleHarness.run(MyExperiment)

# If interrupted, resume from last checkpoint
{:ok, report} = CrucibleHarness.resume("exp_12345")
```

## Architecture

```
ResearchHarness
├── Experiment (DSL & Definition)
├── Runner (Execution Engine with GenStage/Flow)
├── Collector (Results Aggregation & Statistical Analysis)
├── Reporter (Multi-Format Output Generation)
└── Utilities (Cost/Time Estimation, Checkpointing)
```

## Example Experiments

See the `examples/` directory for complete examples:

- `simple_comparison.ex` - Basic two-condition comparison
- `ensemble_comparison.ex` - Multi-condition ensemble evaluation

## API Reference

### Main Functions

#### `CrucibleHarness.run/2`
Runs an experiment and generates reports.

**Options:**
- `:output_dir` - Directory for results (default: "./results")
- `:formats` - Report formats (default: `[:markdown]`)
- `:checkpoint_dir` - Checkpoint directory (default: "./checkpoints")
- `:dry_run` - Validate without executing (default: `false`)

#### `CrucibleHarness.estimate/1`
Estimates cost and time without running the experiment.

#### `CrucibleHarness.resume/1`
Resumes a failed or interrupted experiment from checkpoint.

### Experiment DSL

#### Required Fields
- `name` - Experiment name
- `dataset` - Dataset identifier
- `conditions` - List of experimental conditions
- `metrics` - Metrics to collect

#### Optional Fields
- `description` - Detailed description
- `author` - Experiment author
- `version` - Experiment version
- `tags` - Tags for organization
- `repeat` - Number of repetitions (default: 1)
- `config` - Execution configuration
- `cost_budget` - Budget constraints
- `statistical_analysis` - Analysis parameters
- `custom_metrics` - Custom metric definitions

## Configuration

Add to your `config.exs`:

```elixir
config :research_harness,
  checkpoint_dir: "./checkpoints",
  results_dir: "./results"
```

## Testing

```bash
mix test
```

## Installation

Add `research_harness` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:crucible_harness, "~> 0.1.0"}
  ]
end
```

Or install from GitHub:

```elixir
def deps do
  [
    {:crucible_harness, github: "nshkrdotcom/elixir_ai_research", sparse: "apps/research_harness"}
  ]
end
```

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc):

```bash
mix docs
```

## Contributing

This is part of the Spectra AI research infrastructure. Contributions welcome!

## License

MIT License - see [LICENSE](https://github.com/North-Shore-AI/crucible_harness/blob/main/LICENSE) file for details

## Acknowledgments

Built for systematic AI research experimentation with a focus on ensemble methods, hedging strategies, and model comparisons.

