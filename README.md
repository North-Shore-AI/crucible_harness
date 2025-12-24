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
- **Lifecycle Hooks** (v0.2.0) - Extensible callbacks for setup, teardown, and custom error handling
- **Error Recovery** (v0.2.0) - Automatic retry with exponential backoff and circuit breaker
- **Metric Validation** (v0.2.0) - Runtime schema validation with type coercion
- **Solver Pipelines** (v0.3.1) - Composable execution steps inspired by inspect-ai
- **State Threading** (v0.3.1) - TaskState carries messages and metadata through solver chains
- **LLM Backend Abstraction** (v0.3.1) - Swappable Generate backends for different LLM providers

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

### Lifecycle Hooks (v0.2.0)

Hooks provide extension points during experiment execution for setup, teardown, logging, and custom error handling:

```elixir
defmodule MyExperiment do
  use CrucibleHarness.Experiment

  name "Experiment with Hooks"
  dataset :my_dataset
  conditions [%{name: "test", fn: &test_condition/1}]
  metrics [:accuracy, :latency]

  # Called once before experiment starts - can modify config
  before_experiment fn config ->
    Logger.info("Starting experiment: #{config.name}")
    {:ok, Map.put(config, :start_time, DateTime.utc_now())}
  end

  # Called once after experiment completes
  after_experiment fn config, results ->
    duration = DateTime.diff(DateTime.utc_now(), config.start_time, :second)
    Logger.info("Completed in #{duration}s with #{length(results)} results")
    :ok
  end

  # Called before each condition execution
  before_condition fn condition, query ->
    Logger.metadata(condition: condition.name, query_id: query.id)
    :ok
  end

  # Called after each condition execution
  after_condition fn condition, query, result ->
    :telemetry.execute([:experiment, :task, :complete], %{latency: result.latency}, %{})
    :ok
  end

  # Called when a condition fails - return :retry, :skip, or :abort
  on_error fn condition, query, error ->
    case error do
      {:error, :timeout} -> :retry
      {:error, :rate_limited} -> :retry
      {:error, :authentication_failed} -> :abort
      _ -> :skip
    end
  end

  def test_condition(query), do: %{accuracy: 0.85, latency: 100}
end
```

**Hook Signatures:**
- `before_experiment(config)` → `{:ok, config}` or `:ok`
- `after_experiment(config, results)` → `:ok`
- `before_condition(condition, query)` → `:ok`
- `after_condition(condition, query, result)` → `:ok`
- `on_error(condition, query, error)` → `:retry` | `:skip` | `:abort`

All hooks are optional and errors in hooks are handled gracefully (they won't crash your experiment).

### Error Recovery (v0.2.0)

Configure automatic retry with exponential backoff for transient failures:

```elixir
config %{
  error_handling: %{
    # Retry strategy: :exponential_backoff, :constant, or :linear
    retry_strategy: :exponential_backoff,
    max_retries: 3,
    initial_delay_ms: 1000,
    max_delay_ms: 30_000,
    backoff_factor: 2.0,
    jitter: true,  # Add randomness to prevent thundering herd

    # Dead letter queue for permanently failed tasks
    dlq_enabled: true,
    dlq_path: "./failed_tasks.jsonl",

    # Circuit breaker - abort if failure rate exceeds threshold
    max_failure_rate: 0.1,  # Abort if >10% tasks fail
    failure_window: 100     # Over last 100 tasks
  }
}
```

**Error Classification:**
- **Retryable errors:** `:timeout`, `:connection_refused`, `:rate_limited`, HTTP 429/502/503/504
- **Permanent errors:** `:invalid_query`, `:authentication_failed`, HTTP 400/401/403/404

Task results now include retry information:

```elixir
%{
  result: {:ok, %{accuracy: 0.85}},
  attempts: 2,
  retry_delays: [1000, 2000],
  final_status: :success,  # :success | :failed_permanent | :failed_retries_exhausted
  error_history: [%{attempt: 1, error: :timeout, timestamp: ~U[...]}]
}
```

### Metric Validation (v0.2.0)

Define schemas to validate metrics at runtime and catch errors early:

```elixir
defmodule MyExperiment do
  use CrucibleHarness.Experiment

  name "Validated Experiment"
  dataset :my_dataset
  conditions [%{name: "test", fn: &test_condition/1}]

  metrics [:accuracy, :latency, :cost]

  # Define validation schemas for each metric
  metric_schemas %{
    accuracy: %{type: :float, min: 0.0, max: 1.0, required: true},
    latency: %{type: :number, min: 0, unit: :milliseconds, required: true},
    cost: %{type: :float, min: 0.0, required: false, default: 0.0},
    custom: %{
      type: :map,
      schema: %{
        value: %{type: :number, min: 0},
        confidence: %{type: :float, min: 0.0, max: 1.0}
      }
    }
  }

  config %{
    metric_validation: %{
      enabled: true,
      on_invalid: :log_and_continue,  # :log_and_continue | :log_and_retry | :abort
      coerce_types: true  # Try to convert "0.85" -> 0.85
    }
  }

  def test_condition(query) do
    %{accuracy: 0.85, latency: 123, custom: %{value: 42, confidence: 0.95}}
  end
end
```

**Schema Helpers:**

```elixir
alias CrucibleHarness.Validation.Schema

# Common schema types
Schema.float(min: 0.0, max: 1.0)      # Float with range
Schema.number(min: 0)                  # Integer or float
Schema.map(schema: %{...})             # Nested map validation
Schema.percentage()                    # 0-100 float
Schema.probability()                   # 0-1 float
Schema.positive_number()               # >= 0
Schema.duration_ms()                   # Positive number in milliseconds
```

### Solver Pipelines (v0.3.1)

Build composable LLM execution pipelines using inspect-ai-inspired patterns:

```elixir
alias CrucibleHarness.{Solver, TaskState}
alias CrucibleHarness.Solver.{Chain, Generate}

# Define a custom solver
defmodule SystemPromptSolver do
  use CrucibleHarness.Solver

  @impl true
  def solve(state, _generate_fn) do
    msg = %{role: "system", content: "You are a helpful assistant."}
    {:ok, TaskState.add_message(state, msg)}
  end
end

# Create a solver chain
chain = Chain.new([
  SystemPromptSolver,
  Generate.new(%{model: "gpt-4", temperature: 0.7, max_tokens: 500, stop: []}),
])

# Initialize state from a sample
sample = %{id: "sample_1", input: "Explain recursion briefly."}
state = TaskState.new(sample)

# Define your LLM backend
generate_fn = fn state, config ->
  # Call your LLM (Tinkex, OpenAI, etc.)
  MyLLMBackend.generate(state.messages, config)
end

# Execute the chain
{:ok, result} = Chain.solve(chain, state, generate_fn)

# Access results
IO.puts(result.output.content)
```

**Key Concepts:**

- **Solver** - A behaviour for execution steps (`solve/2` callback)
- **Chain** - Composes solvers sequentially; stops on error or `state.completed`
- **TaskState** - Carries messages, metadata, and inter-solver data via `store`
- **Generate** - Behaviour for LLM backends; `Solver.Generate` is a built-in solver

**Implementing a Generate Backend:**

```elixir
defmodule MyBackend do
  @behaviour CrucibleHarness.Generate

  @impl true
  def generate(messages, config) do
    # Call your LLM API
    {:ok, %{
      content: "Response text",
      finish_reason: "stop",
      usage: %{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30}
    }}
  end
end
```

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
CrucibleHarness
├── Experiment (DSL & Definition)
├── Runner (Execution Engine with GenStage/Flow)
├── Collector (Results Aggregation & Statistical Analysis)
├── Reporter (Multi-Format Output Generation)
├── Hooks (Lifecycle Hook Execution) [v0.2.0]
│   └── Executor (Safe hook execution with error handling)
├── Errors (Error Recovery Framework) [v0.2.0]
│   ├── Classifier (Error type classification)
│   ├── Retry (Exponential backoff logic)
│   └── DLQ (Dead letter queue for failed tasks)
├── Validation (Metric Validation) [v0.2.0]
│   ├── Schema (Schema definition helpers)
│   └── MetricValidator (Runtime validation)
├── Solver (Composable Execution Steps) [v0.3.1]
│   ├── Chain (Sequential solver composition)
│   └── Generate (Built-in LLM generation solver)
├── TaskState (State Threading for Pipelines) [v0.3.1]
├── Generate (LLM Backend Abstraction) [v0.3.1]
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
- `metric_schemas` - Validation schemas for metrics (v0.2.0)
- `before_experiment` - Hook called before experiment starts (v0.2.0)
- `after_experiment` - Hook called after experiment completes (v0.2.0)
- `before_condition` - Hook called before each condition (v0.2.0)
- `after_condition` - Hook called after each condition (v0.2.0)
- `on_error` - Hook for custom error handling (v0.2.0)

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
    {:crucible_harness, "~> 0.3.1"}
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

## Upgrading

### Upgrading to v0.3.1

Version 0.3.1 adds inspect-ai parity modules for building composable LLM execution pipelines.

#### New Modules
- `CrucibleHarness.Solver` - Behaviour for composable execution steps
- `CrucibleHarness.Solver.Chain` - Sequential solver composition with early termination
- `CrucibleHarness.Solver.Generate` - Built-in solver for LLM generation
- `CrucibleHarness.TaskState` - State object threaded through solver pipelines
- `CrucibleHarness.Generate` - Behaviour for LLM backend implementations

#### Quick Example

```elixir
alias CrucibleHarness.{Solver, TaskState}
alias CrucibleHarness.Solver.{Chain, Generate}

# Create a sample and initial state
sample = %{id: "test_1", input: "What is 2+2?"}
state = TaskState.new(sample)

# Define a generate function (your LLM backend)
generate_fn = fn state, config ->
  {:ok, %{content: "4", finish_reason: "stop", usage: %{}}}
end

# Build a solver chain
chain = Chain.new([
  MySystemPromptSolver,
  Generate.new(%{temperature: 0.7, max_tokens: 100}),
  MyValidationSolver
])

# Execute the chain
{:ok, result_state} = Chain.solve(chain, state, generate_fn)
```

#### No Breaking Changes
Existing experiment definitions continue to work unchanged. The new modules are additive.

### Upgrading to v0.3.0

Version 0.3.0 introduces integration with the new `crucible_ir` library for shared IR structs. This change is mostly transparent to users.

#### What Changed
- CrucibleHarness now depends on `crucible_ir` v0.1.1 for IR struct definitions
- Updated to work with `crucible_framework` v0.5.0
- Internal IR module references updated from `Crucible.IR.*` to `CrucibleIR.*`

#### Do I Need to Change My Code?
**For most users: No.** The public API remains unchanged.

**Only if you were directly using internal IR structs** (uncommon), update your imports:

```elixir
# Before
alias Crucible.IR.{Experiment, BackendRef, StageDef}

# After
alias CrucibleIR.{Experiment, BackendRef, StageDef}
```

#### Dependencies
The new version automatically brings in:
- `crucible_ir` v0.1.1 - Shared IR structs
- `crucible_framework` v0.5.0 - Updated framework integration

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

