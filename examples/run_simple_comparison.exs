#!/usr/bin/env elixir

# Example: Simple A/B Comparison
#
# This script demonstrates running a basic two-condition experiment
# using CrucibleHarness.
#
# Usage:
#   mix run examples/run_simple_comparison.exs

Code.require_file("simple_comparison.ex", __DIR__)

IO.puts("""
====================================================================
Running: Simple A/B Comparison Experiment
====================================================================

This experiment compares two conditions (baseline vs treatment) to
demonstrate basic usage of CrucibleHarness.
""")

# Step 1: Get cost estimates
IO.puts("\n--- Step 1: Estimating Cost and Time ---")
{:ok, estimates} = CrucibleHarness.estimate(Examples.SimpleComparison)

IO.puts("Total queries: #{estimates.cost.total_queries}")
IO.puts("Estimated cost: $#{Float.round(estimates.cost.total_cost, 2)}")
IO.puts("Estimated duration: #{trunc(estimates.time.estimated_duration / 1000)}s")

# Step 2: Run the experiment
IO.puts("\n--- Step 2: Running Experiment ---")
output_dir = "./example_results"
File.mkdir_p!(output_dir)

{:ok, report} =
  CrucibleHarness.run(
    Examples.SimpleComparison,
    output_dir: output_dir,
    formats: [:markdown, :html],
    confirm: false
  )

# Step 3: Show results
IO.puts("\n--- Step 3: Results ---")
IO.puts("Experiment ID: #{report.experiment_id}")
IO.puts("Number of results: #{length(report.results)}")

IO.puts("\n--- Generated Reports ---")

Enum.each(report.reports, fn {format, path} ->
  IO.puts("  - #{format}: #{path}")
end)

IO.puts("""

====================================================================
✓ Experiment Complete!
====================================================================

View your reports in: #{output_dir}/

To view the HTML report:
  open #{output_dir}/#{report.experiment_id}_report.html

To view the Markdown report:
  cat #{output_dir}/#{report.experiment_id}_report.markdown

""")
