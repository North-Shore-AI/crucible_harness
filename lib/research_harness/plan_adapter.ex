defmodule CrucibleHarness.PlanAdapter.Step do
  @moduledoc false

  use CrucibleHarness.Solver

  alias CrucibleHarness.TaskState

  defstruct [:step, :runner, :plan_meta]

  @impl true
  def solve(_state, _generate_fn) do
    {:error, :invalid_step}
  end

  def solve(%__MODULE__{step: step, runner: runner, plan_meta: plan_meta}, state, generate_fn) do
    meta = build_step_meta(step, plan_meta)

    case call_runner(runner, state, step, meta, generate_fn) do
      {:ok, %TaskState{} = new_state} ->
        {:ok, new_state}

      {:error, _} = error ->
        error

      other ->
        {:error, {:invalid_step_result, other}}
    end
  end

  defp build_step_meta(step, plan_meta) do
    %{
      trace_id: plan_meta.trace_id,
      work_id: plan_meta.work_id,
      plan_id: plan_meta.plan_id,
      plan_context: plan_meta.plan_context,
      step_id: Map.get(step, :id),
      step_name: Map.get(step, :name)
    }
  end

  defp call_runner(runner, state, step, meta, generate_fn) do
    case :erlang.fun_info(runner, :arity) do
      {:arity, 2} -> runner.(state, step)
      {:arity, 3} -> runner.(state, step, meta)
      {:arity, 4} -> runner.(state, step, meta, generate_fn)
      _ -> {:error, :invalid_step_runner}
    end
  end
end

defmodule CrucibleHarness.PlanAdapter do
  @moduledoc """
  Optional adapter to interpret Jido.Plan data as solver chains.

  This module avoids hard dependencies on Jido.Plan by working with any plan
  that exposes a `%{steps: %{}}` map containing step definitions with
  `:name` and `:depends_on` fields. When Jido.Plan is available, the adapter
  works directly with `Jido.Plan.PlanInstruction` steps.
  """

  alias CrucibleHarness.PlanAdapter.Step
  alias CrucibleHarness.Solver.Chain

  @type plan :: map()
  @type step :: map()
  @type step_runner ::
          (CrucibleHarness.TaskState.t(), step(), map() -> step_result())
          | (CrucibleHarness.TaskState.t(), step(), map(), CrucibleHarness.Solver.generate_fn() ->
               step_result())
  @type step_result :: {:ok, CrucibleHarness.TaskState.t()} | {:error, term()}

  @doc """
  Converts a plan into a solver chain.

  Options:
    * `:step_runner` (required) - function invoked for each step
    * `:plan_id` - override the plan id used in step metadata
    * `:plan_context` - override the plan context passed to steps
    * `:lineage` - map containing trace/work ids for step metadata
  """
  @spec to_solver_chain(plan(), keyword()) :: {:ok, Chain.t()} | {:error, term()}
  def to_solver_chain(plan, opts \\ []) when is_map(plan) do
    with {:ok, step_runner} <- fetch_step_runner(opts),
         {:ok, steps} <- normalize_steps(plan),
         {:ok, ordered_steps} <- order_steps(steps) do
      plan_meta = build_plan_meta(plan, opts)

      solvers =
        Enum.map(ordered_steps, fn step ->
          %Step{step: step, runner: step_runner, plan_meta: plan_meta}
        end)

      {:ok, Chain.new(solvers)}
    end
  end

  defp fetch_step_runner(opts) do
    case Keyword.fetch(opts, :step_runner) do
      {:ok, runner} when is_function(runner) ->
        {:ok, runner}

      _ ->
        {:error, :missing_step_runner}
    end
  end

  defp normalize_steps(plan) do
    case Map.fetch(plan, :steps) do
      {:ok, steps} when is_map(steps) ->
        {:ok, Enum.map(steps, &normalize_step/1)}

      _ ->
        {:error, :invalid_plan}
    end
  end

  defp normalize_step({name, step}) when is_map(step) do
    step
    |> Map.put_new(:name, name)
    |> Map.update(:depends_on, [], &List.wrap/1)
  end

  defp normalize_step({name, step}) do
    %{
      name: name,
      instruction: step,
      depends_on: []
    }
  end

  defp order_steps(steps) do
    steps_by_name =
      steps
      |> Enum.map(fn step -> {step.name, step} end)
      |> Map.new()

    deps_by_name =
      steps
      |> Enum.map(fn step ->
        {step.name, MapSet.new(step.depends_on || [])}
      end)
      |> Map.new()

    case unknown_dependencies(deps_by_name, steps_by_name) do
      [] ->
        with {:ok, order} <- topo_sort(deps_by_name, []) do
          {:ok, Enum.map(order, &Map.fetch!(steps_by_name, &1))}
        end

      unknown ->
        {:error, {:unknown_dependencies, unknown}}
    end
  end

  defp unknown_dependencies(deps_by_name, steps_by_name) do
    deps_by_name
    |> Enum.flat_map(fn {_name, deps} ->
      deps
      |> Enum.reject(&Map.has_key?(steps_by_name, &1))
    end)
    |> Enum.uniq()
  end

  defp topo_sort(deps_by_name, acc) do
    {ready, blocked} =
      Enum.split_with(deps_by_name, fn {_name, deps} ->
        MapSet.size(deps) == 0
      end)

    ready_names = ready |> Enum.map(&elem(&1, 0)) |> sort_names()

    cond do
      ready_names == [] and map_size(deps_by_name) == 0 ->
        {:ok, acc}

      ready_names == [] ->
        {:error, :cycle_detected}

      true ->
        next_deps =
          blocked
          |> Enum.into(%{}, fn {name, deps} ->
            {name, MapSet.difference(deps, MapSet.new(ready_names))}
          end)

        topo_sort(next_deps, acc ++ ready_names)
    end
  end

  defp sort_names(names) do
    Enum.sort_by(names, &to_string/1)
  end

  defp build_plan_meta(plan, opts) do
    lineage = Keyword.get(opts, :lineage, %{})

    %{
      trace_id: Map.get(lineage, :trace_id),
      work_id: Map.get(lineage, :work_id),
      plan_id: Keyword.get(opts, :plan_id, Map.get(plan, :id)),
      plan_context: Keyword.get(opts, :plan_context, Map.get(plan, :context, %{}))
    }
  end
end
