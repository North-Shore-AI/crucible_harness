#!/usr/bin/env elixir

# Example: Ensemble vs Single Model Comparison
#
# This script demonstrates running a multi-condition experiment comparing
# single models against ensemble methods.
#
# Usage:
#   mix run examples/run_ensemble_comparison.exs

Code.require_file("ensemble_comparison.ex", __DIR__)

IO.puts("""
====================================================================
Running: Ensemble vs Single Model Comparison
====================================================================

This experiment compares:
  - Single model A baseline
  - Single model B baseline
  - 3-model ensemble
  - 5-model ensemble
""")

# Step 1: Get cost estimates
IO.puts("\n--- Step 1: Estimating Cost and Time ---")
{:ok, estimates} = CrucibleHarness.estimate(Examples.EnsembleComparison)

IO.puts("Total queries: #{estimates.cost.total_queries}")
IO.puts("Estimated cost: $#{Float.round(estimates.cost.total_cost, 2)}")

duration_mins = trunc(estimates.time.estimated_duration / 60_000)
IO.puts("Estimated duration: ~#{duration_mins} minutes")

# Check budget
config = Examples.EnsembleComparison.__config__()

if config.cost_budget do
  IO.puts("\nCost Budget: $#{config.cost_budget.max_total}")

  if estimates.cost.total_cost > config.cost_budget.max_total do
    IO.puts("⚠ WARNING: Estimated cost exceeds budget!")
  else
    IO.puts("✓ Within budget")
  end
end

# Step 2: Run the experiment
IO.puts("\n--- Step 2: Running Experiment ---")
IO.puts("This will take a few minutes...")

output_dir = "./example_results"
File.mkdir_p!(output_dir)

{:ok, report} =
  CrucibleHarness.run(
    Examples.EnsembleComparison,
    output_dir: output_dir,
    formats: [:markdown, :html, :latex],
    confirm: false
  )

# Step 3: Show results summary
IO.puts("\n--- Step 3: Results Summary ---")
IO.puts("Experiment ID: #{report.experiment_id}")
IO.puts("Total queries executed: #{length(report.results)}")

# Extract and display key findings
analysis = report.analysis

if analysis.aggregated_results do
  IO.puts("\n--- Performance by Condition ---")

  Enum.each(analysis.aggregated_results, fn result ->
    accuracy = result.metrics[:accuracy]
    latency = result.metrics[:latency]
    cost = result.metrics[:cost]

    IO.puts("\n#{result.condition}:")

    if accuracy do
      IO.puts("  Accuracy: #{Float.round(accuracy.mean, 3)} ± #{Float.round(accuracy.std, 3)}")
    end

    if latency do
      IO.puts("  Latency:  #{Float.round(latency.mean, 1)}ms ± #{Float.round(latency.std, 1)}ms")
    end

    if cost do
      IO.puts("  Cost:     $#{Float.round(cost.mean, 4)}")
    end
  end)
end

# Show significant comparisons
if analysis.statistical_analysis && analysis.statistical_analysis.comparisons do
  IO.puts("\n--- Significant Differences ---")

  Enum.each(analysis.statistical_analysis.comparisons, fn comp ->
    {c1, c2} = comp.pair

    # Check accuracy metric
    if comp.metrics[:accuracy] && comp.metrics[:accuracy].significant do
      stats = comp.metrics[:accuracy]
      direction = if stats.mean_diff > 0, do: "higher", else: "lower"
      IO.puts("✓ #{c1} has significantly #{direction} accuracy than #{c2}")

      IO.puts(
        "  (p = #{Float.round(stats.p_value, 4)}, effect size = #{Float.round(stats.effect_size, 2)})"
      )
    end
  end)
end

IO.puts("\n--- Generated Reports ---")

Enum.each(report.reports, fn {format, path} ->
  IO.puts("  - #{format}: #{path}")
end)

IO.puts("""

====================================================================
✓ Experiment Complete!
====================================================================

View your reports in: #{output_dir}/

Key Files:
  - HTML:     #{output_dir}/#{report.experiment_id}_report.html
  - Markdown: #{output_dir}/#{report.experiment_id}_report.markdown
  - LaTeX:    #{output_dir}/#{report.experiment_id}_report.latex

""")
