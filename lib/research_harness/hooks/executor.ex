defmodule CrucibleHarness.Hooks.Executor do
  @moduledoc """
  Executes lifecycle hooks with error handling and timeout protection.

  Hooks provide extension points during experiment execution:
  - before_experiment: Setup operations before experiment starts
  - after_experiment: Teardown operations after experiment completes
  - before_condition: Pre-processing before each condition execution
  - after_condition: Post-processing after each condition execution
  - on_error: Custom error handling for failed conditions
  """

  require Logger

  @doc """
  Runs the before_experiment hook.

  Returns {:ok, config} with potentially modified config, or {:error, reason} if hook fails.
  """
  def run_before_experiment(nil, config), do: {:ok, config}

  def run_before_experiment(hook_fn, config) when is_function(hook_fn, 1) do
    try do
      case hook_fn.(config) do
        {:ok, modified_config} ->
          {:ok, modified_config}

        :ok ->
          {:ok, config}

        {:error, reason} ->
          Logger.error("before_experiment hook failed: #{inspect(reason)}")
          {:error, reason}

        other ->
          Logger.error("before_experiment hook returned unexpected value: #{inspect(other)}")
          {:error, :invalid_hook_return}
      end
    rescue
      e ->
        Logger.error("before_experiment hook raised exception: #{Exception.message(e)}")
        {:error, {:hook_exception, e}}
    catch
      :exit, reason ->
        Logger.error("before_experiment hook exited: #{inspect(reason)}")
        {:error, {:hook_exit, reason}}
    end
  end

  @doc """
  Runs the after_experiment hook.

  Returns :ok or {:error, reason} if hook fails.
  """
  def run_after_experiment(nil, _config, _results), do: :ok

  def run_after_experiment(hook_fn, config, results) when is_function(hook_fn, 2) do
    try do
      case hook_fn.(config, results) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("after_experiment hook failed: #{inspect(reason)}")
          {:error, reason}

        other ->
          Logger.error("after_experiment hook returned unexpected value: #{inspect(other)}")
          {:error, :invalid_hook_return}
      end
    rescue
      e ->
        Logger.error("after_experiment hook raised exception: #{Exception.message(e)}")
        {:error, {:hook_exception, e}}
    catch
      :exit, reason ->
        Logger.error("after_experiment hook exited: #{inspect(reason)}")
        {:error, {:hook_exit, reason}}
    end
  end

  @doc """
  Runs the before_condition hook.

  Returns :ok or {:error, reason} if hook fails.
  """
  def run_before_condition(nil, _condition, _query), do: :ok

  def run_before_condition(hook_fn, condition, query) when is_function(hook_fn, 2) do
    try do
      case hook_fn.(condition, query) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("before_condition hook failed: #{inspect(reason)}")
          {:error, reason}

        other ->
          Logger.warning("before_condition hook returned unexpected value: #{inspect(other)}")
          {:error, :invalid_hook_return}
      end
    rescue
      e ->
        Logger.warning("before_condition hook raised exception: #{Exception.message(e)}")
        {:error, {:hook_exception, e}}
    catch
      :exit, reason ->
        Logger.warning("before_condition hook exited: #{inspect(reason)}")
        {:error, {:hook_exit, reason}}
    end
  end

  @doc """
  Runs the after_condition hook.

  Returns :ok or {:error, reason} if hook fails.
  """
  def run_after_condition(nil, _condition, _query, _result), do: :ok

  def run_after_condition(hook_fn, condition, query, result) when is_function(hook_fn, 3) do
    try do
      case hook_fn.(condition, query, result) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("after_condition hook failed: #{inspect(reason)}")
          {:error, reason}

        other ->
          Logger.warning("after_condition hook returned unexpected value: #{inspect(other)}")
          {:error, :invalid_hook_return}
      end
    rescue
      e ->
        Logger.warning("after_condition hook raised exception: #{Exception.message(e)}")
        {:error, {:hook_exception, e}}
    catch
      :exit, reason ->
        Logger.warning("after_condition hook exited: #{inspect(reason)}")
        {:error, {:hook_exit, reason}}
    end
  end

  @doc """
  Runs the on_error hook.

  Returns :retry, :skip, or :abort based on hook decision.
  Default is :skip if hook is nil or returns unexpected value.
  """
  def run_on_error(nil, _condition, _query, _error), do: :skip

  def run_on_error(hook_fn, condition, query, error) when is_function(hook_fn, 3) do
    try do
      case hook_fn.(condition, query, error) do
        :retry ->
          :retry

        :skip ->
          :skip

        :abort ->
          :abort

        other ->
          Logger.warning(
            "on_error hook returned unexpected value: #{inspect(other)}, defaulting to :skip"
          )

          :skip
      end
    rescue
      e ->
        Logger.warning(
          "on_error hook raised exception: #{Exception.message(e)}, defaulting to :skip"
        )

        :skip
    catch
      :exit, reason ->
        Logger.warning("on_error hook exited: #{inspect(reason)}, defaulting to :skip")
        :skip
    end
  end
end
