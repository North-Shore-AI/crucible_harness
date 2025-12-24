# ResearchHarness Quick Start

Get up and running with ResearchHarness in 5 minutes.

## 1. Run the Example

```bash
cd apps/research_harness
iex -S mix
```

In IEx:

```elixir
# Load the example
Code.require_file("examples/simple_comparison.ex")

# Run the experiment (with auto-confirmation disabled for demo)
{:ok, report} = CrucibleHarness.run(
  Examples.SimpleComparison,
  output_dir: "./demo_results",
  formats: [:markdown, :html],
  confirm: false
)

# View the results
IO.puts("Reports generated:")
IO.inspect(report.reports)
```

## 2. View Your Results

Open the generated reports:

```bash
# View markdown report
cat demo_results/exp_*_report.markdown

# Open HTML report in browser
open demo_results/exp_*_report.html  # macOS
xdg-open demo_results/exp_*_report.html  # Linux
```

## 3. Create Your First Experiment

Create a new file `my_first_experiment.ex`:

```elixir
defmodule MyFirstExperiment do
  use CrucibleHarness.Experiment

  # Basic configuration
  name "My First Experiment"
  description "Testing baseline vs improved approach"

  # Use test dataset (100 samples)
  dataset :test_dataset
  dataset_config %{sample_size: 100}

  # Define two conditions to compare
  conditions [
    %{
      name: "baseline",
      fn: fn query ->
        # Simulate baseline with 70% accuracy
        %{
          accuracy: 0.70 + :rand.uniform() * 0.1,
          latency: 100 + :rand.uniform(50),
          cost: 0.001
        }
      end
    },
    %{
      name: "improved",
      fn: fn query ->
        # Simulate improved approach with 85% accuracy
        %{
          accuracy: 0.85 + :rand.uniform() * 0.08,
          latency: 120 + :rand.uniform(40),
          cost: 0.002
        }
      end
    }
  ]

  # What to measure
  metrics [:accuracy, :latency, :cost]

  # Repeat each condition 5 times for statistical power
  repeat 5

  # Configuration
  config %{
    timeout: 10_000,
    rate_limit: 10
  }
end
```

## 4. Run Your Experiment

```elixir
# Load your experiment
Code.require_file("my_first_experiment.ex")

# Check estimates first
{:ok, estimates} = CrucibleHarness.estimate(MyFirstExperiment)
IO.puts("Estimated cost: $#{Float.round(estimates.cost.total_cost, 2)}")
IO.puts("Estimated time: #{div(estimates.time.estimated_duration, 1000)}s")

# Run it
{:ok, report} = CrucibleHarness.run(
  MyFirstExperiment,
  output_dir: "./my_results",
  formats: [:markdown, :html],
  confirm: false
)

IO.puts("\nExperiment complete!")
IO.puts("View results: my_results/#{report.experiment_id}_report.html")
```

## 5. Understanding Your Results

Your report will show:

### Summary Statistics

```
| Condition | N   | Accuracy     | Latency      | Cost        |
|-----------|-----|--------------|--------------|-------------|
| baseline  | 500 | 0.75 ± 0.03  | 125 ± 15     | 0.001       |
| improved  | 500 | 0.87 ± 0.02  | 135 ± 12     | 0.002       |
```

### Statistical Analysis

```
baseline vs improved:
- Mean difference (accuracy): +0.12
- p-value: < 0.001
- Significant: Yes
- Effect size: 1.2 (Large)
```

## What's Happening?

1. **Experiment Definition**: You defined two conditions with different performance characteristics
2. **Execution**: ResearchHarness ran each condition 5 times on 100 samples = 1000 total runs
3. **Analysis**: Statistical tests compared the conditions
4. **Reporting**: Results generated in multiple formats

## Next Steps

### Add More Conditions

```elixir
conditions [
  %{name: "baseline", fn: &baseline/1},
  %{name: "approach_a", fn: &approach_a/1},
  %{name: "approach_b", fn: &approach_b/1},
  %{name: "approach_c", fn: &approach_c/1}
]
```

### Add Custom Metrics

```elixir
custom_metrics [
  %{
    name: :efficiency,
    description: "Accuracy per dollar",
    fn: fn results -> results.accuracy / results.cost end
  }
]
```

### Set Cost Budgets

```elixir
cost_budget %{
  max_total: 10.00,
  max_per_condition: 5.00
}
```

### Configure Statistical Analysis

```elixir
statistical_analysis %{
  significance_level: 0.01,  # More stringent
  confidence_interval: 0.99,
  multiple_testing_correction: :bonferroni
}
```

## Common Workflows

### Development Workflow

```elixir
# 1. Test with small sample
dataset_config %{sample_size: 10}
repeat 2

# 2. Run quickly
{:ok, _} = CrucibleHarness.run(MyExperiment, confirm: false)

# 3. Iterate on conditions
# 4. Scale up when ready
dataset_config %{sample_size: 1000}
repeat 10
```

### Production Workflow

```elixir
# 1. Estimate thoroughly
{:ok, estimates} = CrucibleHarness.estimate(MyExperiment)

# 2. Set budgets
cost_budget %{max_total: 100.00}

# 3. Run with all reports
{:ok, report} = CrucibleHarness.run(
  MyExperiment,
  formats: [:markdown, :latex, :html, :jupyter]
)

# 4. Archive results
File.cp_r!("./results", "./archive/exp_#{Date.utc_today()}")
```

## Tips

1. **Start small**: Use `sample_size: 10` and `repeat: 2` while developing
2. **Check estimates**: Always run `CrucibleHarness.estimate/1` first
3. **Use meaningful names**: Clear condition names help interpret results
4. **Document thoroughly**: Use the `description` field
5. **Monitor progress**: Subscribe to progress updates for long experiments

## Examples

Check out more examples:

```bash
# Simple A/B test
examples/simple_comparison.ex

# Complex ensemble evaluation
examples/ensemble_comparison.ex
```

## Documentation

- **README.md** - Full feature documentation
- **USAGE.md** - Detailed usage guide
- **IMPLEMENTATION_SUMMARY.md** - Technical details

## Getting Help

```elixir
# In IEx, get help on any module
h ResearchHarness
h CrucibleHarness.Experiment
h CrucibleHarness.Reporter

# View module docs
open https://hexdocs.pm/research_harness  # When published
```

## That's It!

You now know enough to:
- ✅ Define experiments
- ✅ Run them
- ✅ Interpret results
- ✅ Iterate and improve

Go forth and experiment! 🚀

## Solver Pipelines (v0.3.1)

Build composable LLM execution pipelines:

```elixir
alias CrucibleHarness.{TaskState}
alias CrucibleHarness.Solver.{Chain, Generate}

# Create state from sample
sample = %{id: "test", input: "What is 2+2?"}
state = TaskState.new(sample)

# Build a chain with the Generate solver
chain = Chain.new([
  Generate.new(%{temperature: 0.7, max_tokens: 100})
])

# Define your LLM backend
generate_fn = fn state, config ->
  {:ok, %{content: "4", finish_reason: "stop", usage: %{}}}
end

# Execute
{:ok, result} = Chain.solve(chain, state, generate_fn)
IO.puts result.output.content  # "4"
```

See **USAGE.md** for full Solver Pipelines documentation.

---

**Pro Tip**: Keep your experiments in version control alongside your code. This ensures reproducibility and makes it easy to track experimental changes over time.

