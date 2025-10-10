defmodule ResearchHarness.Experiment do
  @moduledoc """
  Behaviour and DSL for defining research experiments.

  This module provides a declarative DSL for defining experiments using macros.
  Experiments define conditions, metrics, datasets, and configuration parameters.

  ## Example

      defmodule MyExperiment do
        use ResearchHarness.Experiment

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
      @behaviour ResearchHarness.Experiment

      import ResearchHarness.Experiment

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

      @before_compile ResearchHarness.Experiment
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __config__ do
        experiment_id = generate_experiment_id()

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
          statistical_analysis: @statistical_analysis || default_statistical_analysis(),
          custom_metrics: @custom_metrics || []
        }
      end

      defp generate_experiment_id do
        timestamp = DateTime.utc_now() |> DateTime.to_unix()
        random = :rand.uniform(1_000_000)
        "exp_#{timestamp}_#{random}"
      end

      defp default_statistical_analysis do
        %{
          significance_level: 0.05,
          multiple_testing_correction: :bonferroni,
          confidence_interval: 0.95
        }
      end
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
end
