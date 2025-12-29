defmodule CrucibleHarness.Experiment do
  @moduledoc """
  Behaviour and DSL for defining research experiments.

  This module provides a declarative DSL for defining experiments using macros.
  Experiments define conditions, metrics, datasets, and configuration parameters.

  ## Example

      defmodule MyExperiment do
        use CrucibleHarness.Experiment

        name "My Experiment"
        description "Comparing two approaches"

        dataset :mmlu_200

        conditions [
          %{name: "baseline", fn: &baseline/1},
          %{name: "treatment", fn: &treatment/1}
        ]

        metrics [:accuracy, :latency, :cost]
        repeat 5

        config %{
          timeout: 30_000,
          rate_limit: 10
        }

        def baseline(query), do: %{prediction: "A", latency: 100, cost: 0.01}
        def treatment(query), do: %{prediction: "B", latency: 150, cost: 0.02}
      end
  """

  @doc """
  Callback to return the experiment configuration.
  """
  @callback __config__() :: map()

  defmacro __using__(_opts) do
    quote do
      @behaviour CrucibleHarness.Experiment

      import CrucibleHarness.Experiment

      Module.register_attribute(__MODULE__, :experiment_name, persist: true)
      Module.register_attribute(__MODULE__, :experiment_description, persist: true)
      Module.register_attribute(__MODULE__, :experiment_dataset, persist: true)
      Module.register_attribute(__MODULE__, :experiment_conditions, persist: true)
      Module.register_attribute(__MODULE__, :experiment_metrics, persist: true)
      Module.register_attribute(__MODULE__, :experiment_repeat, persist: true)
      Module.register_attribute(__MODULE__, :experiment_config, persist: true)
      Module.register_attribute(__MODULE__, :experiment_tags, persist: true)
      Module.register_attribute(__MODULE__, :experiment_author, persist: true)
      Module.register_attribute(__MODULE__, :experiment_version, persist: true)
      Module.register_attribute(__MODULE__, :dataset_config, persist: true)
      Module.register_attribute(__MODULE__, :cost_budget, persist: true)
      Module.register_attribute(__MODULE__, :statistical_analysis, persist: true)
      Module.register_attribute(__MODULE__, :custom_metrics, persist: true)
      Module.register_attribute(__MODULE__, :metric_schemas, persist: true)
      Module.register_attribute(__MODULE__, :before_experiment_hook, persist: true)
      Module.register_attribute(__MODULE__, :after_experiment_hook, persist: true)
      Module.register_attribute(__MODULE__, :before_condition_hook, persist: true)
      Module.register_attribute(__MODULE__, :after_condition_hook, persist: true)
      Module.register_attribute(__MODULE__, :on_error_hook, persist: true)

      @before_compile CrucibleHarness.Experiment
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defmacro __before_compile__(_env) do
    quote do
      # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
      def __config__ do
        experiment_id = CrucibleHarness.Experiment.generate_experiment_id()

        %{
          experiment_id: experiment_id,
          name: @experiment_name || "Unnamed Experiment",
          description: @experiment_description || "",
          dataset: @experiment_dataset,
          conditions: @experiment_conditions || [],
          metrics: @experiment_metrics || [],
          repeat: @experiment_repeat || 1,
          config: @experiment_config || %{},
          tags: @experiment_tags || [],
          author: @experiment_author || "Unknown",
          version: @experiment_version || "0.1.0",
          dataset_config: @dataset_config || %{},
          cost_budget: @cost_budget,
          statistical_analysis:
            @statistical_analysis || CrucibleHarness.Experiment.default_statistical_analysis(),
          custom_metrics: @custom_metrics || [],
          metric_schemas: @metric_schemas || %{},
          hooks: CrucibleHarness.Experiment.collect_hooks(__MODULE__)
        }
      end
    end
  end

  @doc false
  def generate_experiment_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :rand.uniform(1_000_000)
    "exp_#{timestamp}_#{random}"
  end

  @doc false
  def default_statistical_analysis do
    %{
      significance_level: 0.05,
      multiple_testing_correction: :bonferroni,
      confidence_interval: 0.95
    }
  end

  @doc false
  def collect_hooks(module) do
    %{
      before_experiment: get_attr(module, :before_experiment_hook),
      after_experiment: get_attr(module, :after_experiment_hook),
      before_condition: get_attr(module, :before_condition_hook),
      after_condition: get_attr(module, :after_condition_hook),
      on_error: get_attr(module, :on_error_hook)
    }
  end

  defp get_attr(module, attr) do
    case List.keyfind(module.__info__(:attributes), attr, 0) do
      {^attr, [value | _]} -> value
      _ -> nil
    end
  end

  @doc """
  Sets the experiment name.
  """
  defmacro name(name) do
    quote do
      @experiment_name unquote(name)
    end
  end

  @doc """
  Sets the experiment description.
  """
  defmacro description(desc) do
    quote do
      @experiment_description unquote(desc)
    end
  end

  @doc """
  Sets the dataset to use for the experiment.
  """
  defmacro dataset(dataset_name) do
    quote do
      @experiment_dataset unquote(dataset_name)
    end
  end

  @doc """
  Defines the experimental conditions.
  """
  defmacro conditions(conditions_list) do
    quote do
      @experiment_conditions unquote(conditions_list)
    end
  end

  @doc """
  Defines the metrics to collect.
  """
  defmacro metrics(metrics_list) do
    quote do
      @experiment_metrics unquote(metrics_list)
    end
  end

  @doc """
  Sets the number of repetitions for each condition.
  """
  defmacro repeat(count) do
    quote do
      @experiment_repeat unquote(count)
    end
  end

  @doc """
  Sets the experiment configuration.
  """
  defmacro config(config_map) do
    quote do
      @experiment_config unquote(config_map)
    end
  end

  @doc """
  Sets experiment tags.
  """
  defmacro tags(tags_list) do
    quote do
      @experiment_tags unquote(tags_list)
    end
  end

  @doc """
  Sets the experiment author.
  """
  defmacro author(author_name) do
    quote do
      @experiment_author unquote(author_name)
    end
  end

  @doc """
  Sets the experiment version.
  """
  defmacro version(version_string) do
    quote do
      @experiment_version unquote(version_string)
    end
  end

  @doc """
  Sets dataset-specific configuration.
  """
  defmacro dataset_config(config_map) do
    quote do
      @dataset_config unquote(config_map)
    end
  end

  @doc """
  Sets the cost budget for the experiment.
  """
  defmacro cost_budget(budget_map) do
    quote do
      @cost_budget unquote(budget_map)
    end
  end

  @doc """
  Sets statistical analysis parameters.
  """
  defmacro statistical_analysis(analysis_map) do
    quote do
      @statistical_analysis unquote(analysis_map)
    end
  end

  @doc """
  Defines custom metrics.
  """
  defmacro custom_metrics(metrics_list) do
    quote do
      @custom_metrics unquote(metrics_list)
    end
  end

  @doc """
  Defines metric validation schemas.
  """
  defmacro metric_schemas(schemas_map) do
    quote do
      @metric_schemas unquote(schemas_map)
    end
  end

  @doc """
  Defines a hook to run before the experiment starts.

  The hook receives the config and should return `{:ok, config}` or `:ok`.
  """
  defmacro before_experiment(hook_fn) do
    quote do
      @before_experiment_hook unquote(hook_fn)
    end
  end

  @doc """
  Defines a hook to run after the experiment completes.

  The hook receives the config and results and should return `:ok`.
  """
  defmacro after_experiment(hook_fn) do
    quote do
      @after_experiment_hook unquote(hook_fn)
    end
  end

  @doc """
  Defines a hook to run before each condition execution.

  The hook receives the condition and query and should return `:ok`.
  """
  defmacro before_condition(hook_fn) do
    quote do
      @before_condition_hook unquote(hook_fn)
    end
  end

  @doc """
  Defines a hook to run after each condition execution.

  The hook receives the condition, query, and result and should return `:ok`.
  """
  defmacro after_condition(hook_fn) do
    quote do
      @after_condition_hook unquote(hook_fn)
    end
  end

  @doc """
  Defines a hook to handle errors during condition execution.

  The hook receives the condition, query, and error and should return
  `:retry`, `:skip`, or `:abort`.
  """
  defmacro on_error(hook_fn) do
    quote do
      @on_error_hook unquote(hook_fn)
    end
  end
end
