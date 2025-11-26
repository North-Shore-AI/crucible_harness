defmodule CrucibleHarness do
  @moduledoc """
  ResearchHarness: Automated Experiment Orchestration for AI Research

  ResearchHarness provides a comprehensive framework for orchestrating, executing,
  and analyzing large-scale AI research experiments. It enables systematic experimentation
  across multiple conditions, datasets, and configurations while maintaining reproducibility,
  fault tolerance, and detailed statistical analysis.

  ## Quick Start

      defmodule MyExperiment do
        use CrucibleHarness.Experiment

        name "My Research Experiment"
        dataset :mmlu_200

        conditions [
          %{name: "baseline", fn: &baseline_condition/1},
          %{name: "treatment", fn: &treatment_condition/1}
        ]

        metrics [:accuracy, :latency_p99, :cost_per_query]
        repeat 3

        def baseline_condition(query) do
          # Implementation
          %{prediction: "answer", latency: 100, cost: 0.01}
        end

        def treatment_condition(query) do
          # Implementation
          %{prediction: "answer", latency: 150, cost: 0.02}
        end
      end

      # Run the experiment
      {:ok, report} = CrucibleHarness.run(MyExperiment)

  ## Features

  - Declarative experiment definition via DSL
  - Parallel execution using GenStage/Flow
  - Fault tolerance and checkpointing
  - Statistical analysis with significance testing
  - Multi-format reporting (Markdown, LaTeX, HTML, Jupyter)
  - Cost estimation and budget management
  - Reproducibility via seed management
  """

  alias CrucibleHarness.{Runner, Reporter, Utilities}

  @doc """
  Runs an experiment and returns the results.

  ## Options

    * `:output_dir` - Directory for results and reports (default: "./results")
    * `:formats` - List of report formats to generate (default: [:markdown])
    * `:checkpoint_dir` - Directory for checkpoints (default: "./checkpoints")
    * `:dry_run` - Validate without executing (default: false)

  ## Examples

      {:ok, report} = CrucibleHarness.run(MyExperiment)

      {:ok, report} = CrucibleHarness.run(MyExperiment,
        output_dir: "./my_results",
        formats: [:markdown, :latex, :html]
      )
  """
  def run(experiment_module, opts \\ []) do
    with {:ok, config} <- validate_experiment(experiment_module),
         {:ok, estimates} <- estimate_cost_and_time(config, opts),
         :ok <- confirm_execution(config, estimates, opts),
         {:ok, results} <- Runner.run_experiment(config, opts),
         {:ok, analysis} <- analyze_results(results, config),
         {:ok, reports} <- generate_reports(analysis, config, opts) do
      {:ok,
       %{
         experiment_id: config.experiment_id,
         results: results,
         analysis: analysis,
         reports: reports
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Runs an experiment asynchronously and returns a task identifier.

  ## Examples

      {:ok, task_id} = CrucibleHarness.run_async(MyExperiment)
      CrucibleHarness.status(task_id)
  """
  def run_async(experiment_module, opts \\ []) do
    task = Task.async(fn -> run(experiment_module, opts) end)
    {:ok, task.ref}
  end

  @doc """
  Checks the status of an asynchronously running experiment.
  """
  def status(_task_ref) do
    # Implementation would check task status
    {:ok, :running}
  end

  @doc """
  Estimates the cost and time for an experiment without running it.

  ## Examples

      {:ok, estimates} = CrucibleHarness.estimate(MyExperiment)
      IO.puts("Estimated cost: $\#{estimates.cost.total_cost}")
      IO.puts("Estimated time: \#{estimates.time.estimated_duration}ms")
  """
  def estimate(experiment_module) do
    with {:ok, config} <- validate_experiment(experiment_module),
         {:ok, estimates} <- estimate_cost_and_time(config, []) do
      {:ok, estimates}
    end
  end

  @doc """
  Resumes a failed or interrupted experiment from the last checkpoint.

  ## Examples

      {:ok, report} = CrucibleHarness.resume("exp_abc123")
  """
  def resume(experiment_id) do
    with {:ok, checkpoint} <- Utilities.CheckpointManager.restore(experiment_id),
         {:ok, results} <- Runner.resume_experiment(checkpoint) do
      config = checkpoint.config
      analysis = analyze_results(results, config)
      reports = generate_reports(analysis, config, [])

      {:ok,
       %{experiment_id: experiment_id, results: results, analysis: analysis, reports: reports}}
    end
  end

  # Private Functions

  defp validate_experiment(experiment_module) do
    CrucibleHarness.Experiment.Validator.validate(experiment_module)
  end

  defp estimate_cost_and_time(config, opts) do
    cost_estimate = Utilities.CostEstimator.estimate(config)
    time_estimate = Utilities.TimeEstimator.estimate(config, opts)

    {:ok, %{cost: cost_estimate, time: time_estimate}}
  end

  defp confirm_execution(config, estimates, opts) do
    if opts[:dry_run] do
      IO.puts("\n=== DRY RUN MODE ===")
      print_estimates(config, estimates)
      {:error, :dry_run}
    else
      if should_confirm?(opts) do
        print_estimates(config, estimates)

        case IO.gets("Proceed with experiment? (y/n): ") do
          "y\n" -> :ok
          _ -> {:error, :cancelled}
        end
      else
        :ok
      end
    end
  end

  defp should_confirm?(opts) do
    Keyword.get(opts, :confirm, true)
  end

  defp print_estimates(config, estimates) do
    IO.puts("\n=== Experiment: #{config.name} ===")
    IO.puts("Total queries: #{estimates.cost.total_queries}")
    IO.puts("Estimated cost: $#{Float.round(estimates.cost.total_cost, 2)}")
    IO.puts("Estimated duration: #{format_duration(estimates.time.estimated_duration)}")
    IO.puts("")
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"

  defp format_duration(ms) when ms < 3_600_000 do
    minutes = ms |> trunc() |> div(60_000)
    "#{minutes}m"
  end

  defp format_duration(ms) do
    ms_int = trunc(ms)
    hours = div(ms_int, 3_600_000)
    minutes = div(rem(ms_int, 3_600_000), 60_000)
    "#{hours}h #{minutes}m"
  end

  defp analyze_results(results, config) do
    alias CrucibleHarness.Collector

    aggregated = Collector.MetricsAggregator.aggregate(results, config)
    analysis = Collector.StatisticalAnalyzer.analyze(aggregated, config)
    matrices = generate_comparison_matrices(analysis, config)

    {:ok,
     %{
       aggregated_results: aggregated,
       statistical_analysis: analysis,
       comparison_matrices: matrices
     }}
  end

  defp generate_comparison_matrices(analysis, config) do
    Enum.map(config.metrics, fn metric ->
      {metric, CrucibleHarness.Collector.ComparisonMatrix.generate(analysis, metric)}
    end)
    |> Map.new()
  end

  defp generate_reports(analysis, config, opts) do
    formats = Keyword.get(opts, :formats, [:markdown])
    output_dir = Keyword.get(opts, :output_dir, "./results")

    File.mkdir_p!(output_dir)

    reports =
      Enum.map(formats, fn format ->
        content = Reporter.generate(config, analysis, format)
        filename = "#{config.experiment_id}_report.#{format}"
        path = Path.join(output_dir, filename)
        File.write!(path, content)
        {format, path}
      end)
      |> Map.new()

    {:ok, reports}
  end
end
