#!/usr/bin/env elixir

# Example: Jido.Plan pipeline -> solver chain
#
# This script shows how to interpret a Jido.Plan DAG as a solver chain.
# It requires the `jido_action` dependency in your app.

unless Code.ensure_loaded?(Jido.Plan) do
  raise """
  Jido.Plan is not available.
  Add {:jido_action, "..."} to your deps to run this example.
  """
end

alias CrucibleHarness.{PlanAdapter, TaskState}
alias CrucibleHarness.Solver.Chain

plan =
  Jido.Plan.new()
  |> Jido.Plan.add(:prepare, MyApp.Actions.Prepare)
  |> Jido.Plan.add(:generate, MyApp.Actions.Generate, depends_on: :prepare)
  |> Jido.Plan.add(:score, MyApp.Actions.Score, depends_on: :generate)

step_runner = fn state, step, meta, _generate_fn ->
  IO.puts("Running step #{step.name} (plan_id=#{meta.plan_id})")

  {:ok,
   TaskState.add_message(state, %{
     role: "assistant",
     content: "Completed #{step.name}"
   })}
end

{:ok, chain} = PlanAdapter.to_solver_chain(plan, step_runner: step_runner)

sample = %{id: "sample-1", input: "Explain recursion."}
state = TaskState.new(sample)

generate_fn = fn _state, _config ->
  {:ok, %{content: "ok", finish_reason: "stop", usage: %{}}}
end

{:ok, result_state} = Chain.solve(chain, state, generate_fn)

IO.inspect(result_state.messages, label: "Pipeline Messages")
