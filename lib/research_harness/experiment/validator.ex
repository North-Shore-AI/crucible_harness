defmodule CrucibleHarness.Experiment.Validator do
  @moduledoc """
  Validates experiment definitions before execution.
  """

  @doc """
  Validates an experiment configuration.

  Returns `{:ok, config}` if valid, or `{:error, reason}` if invalid.
  """
  def validate(experiment_module) do
    config = experiment_module.__config__()

    with :ok <- validate_required_fields(config),
         :ok <- validate_conditions(config),
         :ok <- validate_metrics(config),
         :ok <- validate_config_values(config),
         :ok <- validate_cost_budget(config) do
      {:ok, config}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_required_fields(config) do
    required = [:name, :dataset, :conditions, :metrics]

    missing =
      Enum.filter(required, fn field ->
        value = Map.get(config, field)
        is_nil(value) or (is_list(value) and Enum.empty?(value))
      end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_conditions(config) do
    conditions = config.conditions

    cond do
      conditions == [] ->
        {:error, "Experiment must have at least 1 condition"}

      not all_conditions_valid?(conditions) ->
        {:error, "All conditions must have :name and :fn keys"}

      not all_condition_functions_valid?(conditions) ->
        {:error, "All condition functions must accept 1 argument"}

      true ->
        :ok
    end
  end

  defp all_conditions_valid?(conditions) do
    Enum.all?(conditions, fn condition ->
      is_map(condition) and Map.has_key?(condition, :name) and Map.has_key?(condition, :fn)
    end)
  end

  defp all_condition_functions_valid?(conditions) do
    Enum.all?(conditions, fn condition ->
      is_function(condition.fn, 1)
    end)
  end

  defp validate_metrics(config) do
    if Enum.empty?(config.metrics) do
      {:error, "Experiment must specify at least one metric"}
    else
      :ok
    end
  end

  defp validate_config_values(config) do
    cond do
      config.repeat < 1 ->
        {:error, "Repeat count must be at least 1"}

      config.config[:timeout] && config.config[:timeout] < 1000 ->
        {:error, "Timeout must be at least 1000ms"}

      config.config[:rate_limit] && config.config[:rate_limit] < 1 ->
        {:error, "Rate limit must be at least 1 request/second"}

      true ->
        :ok
    end
  end

  defp validate_cost_budget(config) do
    if budget = config.cost_budget do
      cond do
        budget[:max_total] && budget[:max_total] <= 0 ->
          {:error, "Cost budget must be positive"}

        budget[:max_per_condition] && budget[:max_per_condition] <= 0 ->
          {:error, "Per-condition cost budget must be positive"}

        true ->
          :ok
      end
    else
      :ok
    end
  end
end
