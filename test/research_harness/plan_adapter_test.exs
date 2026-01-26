defmodule CrucibleHarness.PlanAdapterTest do
  use ExUnit.Case, async: true

  alias CrucibleHarness.PlanAdapter
  alias CrucibleHarness.Solver.Chain
  alias CrucibleHarness.TaskState

  defp build_plan do
    step1 = %{
      id: "step-1",
      name: :step1,
      instruction: %{action: :step1_action},
      depends_on: [],
      opts: []
    }

    step2 = %{
      id: "step-2",
      name: :step2,
      instruction: %{action: :step2_action},
      depends_on: [:step1],
      opts: []
    }

    step3 = %{
      id: "step-3",
      name: :step3,
      instruction: %{action: :step3_action},
      depends_on: [:step2],
      opts: []
    }

    %{
      id: "plan-1",
      context: %{pipeline: "eval"},
      steps: %{
        step1: step1,
        step2: step2,
        step3: step3
      }
    }
  end

  test "builds solver chain from plan and executes in dependency order" do
    plan = build_plan()

    step_runner = fn state, step, meta ->
      send(self(), {:step_called, step.name, meta})

      {:ok,
       TaskState.add_message(state, %{
         role: "assistant",
         content: to_string(step.name)
       })}
    end

    assert {:ok, %Chain{} = chain} =
             PlanAdapter.to_solver_chain(plan, step_runner: step_runner)

    state = TaskState.new(%{id: "sample-1", input: "hello"})

    generate_fn = fn _state, _config ->
      {:ok, %{content: "", finish_reason: "stop", usage: %{}}}
    end

    assert {:ok, result_state} = Chain.solve(chain, state, generate_fn)

    assert_receive {:step_called, :step1, meta1}
    assert meta1.plan_id == "plan-1"
    assert meta1.step_id == "step-1"
    assert meta1.step_name == :step1
    assert meta1.plan_context == %{pipeline: "eval"}

    assert_receive {:step_called, :step2, _meta2}
    assert_receive {:step_called, :step3, _meta3}

    assert length(result_state.messages) == 4
  end

  test "returns error when plan dependencies are missing" do
    plan = build_plan()

    step_runner = fn state, _step, _meta -> {:ok, state} end

    bad_plan =
      put_in(plan.steps.step2.depends_on, [:missing_step])

    assert {:error, {:unknown_dependencies, _}} =
             PlanAdapter.to_solver_chain(bad_plan, step_runner: step_runner)
  end

  test "allows overriding plan_id" do
    plan = build_plan()

    step_runner = fn state, step, meta ->
      send(self(), {:step_called, step.name, meta})
      {:ok, state}
    end

    assert {:ok, %Chain{} = chain} =
             PlanAdapter.to_solver_chain(plan, step_runner: step_runner, plan_id: "override-plan")

    state = TaskState.new(%{id: "sample-1", input: "hello"})

    generate_fn = fn _state, _config ->
      {:ok, %{content: "", finish_reason: "stop", usage: %{}}}
    end

    assert {:ok, _} = Chain.solve(chain, state, generate_fn)

    assert_receive {:step_called, :step1, meta1}
    assert meta1.plan_id == "override-plan"
  end
end
