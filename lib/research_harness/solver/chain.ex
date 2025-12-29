defmodule CrucibleHarness.Solver.Chain do
  @moduledoc """
  Compose solvers sequentially. Stops if state.completed is true.

  Chain allows you to combine multiple solvers into a sequential pipeline.
  Each solver processes the state and passes it to the next solver in the chain.
  The chain stops early if any solver returns an error or if the state is
  marked as completed.

  ## Examples

      alias CrucibleHarness.Solver.Chain

      # Create a chain of solvers
      chain = Chain.new([
        SystemPromptSolver,
        GenerateSolver.new(%{temperature: 0.7}),
        ValidationSolver
      ])

      # Execute the chain
      {:ok, final_state} = Chain.solve(chain, initial_state, generate_fn)

  ## Early Termination

  The chain will stop processing in two cases:

  1. **Error**: If any solver returns `{:error, reason}`, the chain halts
     and propagates the error.

  2. **Completion**: If `state.completed` is `true` after a solver runs,
     remaining solvers are skipped.

  ## Nested Chains

  Chains can be nested since Chain itself implements the Solver behaviour:

      inner_chain = Chain.new([SolverA, SolverB])
      outer_chain = Chain.new([inner_chain, SolverC])
  """

  use CrucibleHarness.Solver

  @type t :: %__MODULE__{
          solvers: [module() | t()]
        }

  defstruct solvers: []

  @doc """
  Creates a new solver chain.

  The input list is flattened, so nested lists are supported.

  ## Examples

      iex> chain = Chain.new([SolverA, SolverB, SolverC])
      iex> length(chain.solvers)
      3

      iex> chain = Chain.new([[SolverA, SolverB], [SolverC]])
      iex> length(chain.solvers)
      3

      iex> chain = Chain.new([])
      iex> chain.solvers
      []
  """
  def new(solvers) do
    %__MODULE__{solvers: List.flatten(solvers)}
  end

  @doc """
  Executes the chain of solvers sequentially.

  Each solver in the chain is called with the current state and the generate
  function. The state is threaded through each solver, with each solver
  receiving the updated state from the previous one.

  The chain stops if:
  - A solver returns an error (error is propagated)
  - A solver sets `state.completed` to `true` (remaining solvers skipped)
  - All solvers complete successfully

  ## Parameters

    * `chain` - The Chain struct containing the solvers
    * `state` - Initial TaskState
    * `generate_fn` - Generate function passed to each solver

  ## Returns

    * `{:ok, final_state}` - All solvers completed successfully
    * `{:error, reason}` - A solver returned an error

  ## Examples

      chain = Chain.new([Step1, Step2, Step3])
      {:ok, result} = Chain.solve(chain, state, generate_fn)
  """
  @impl true
  def solve(state, generate_fn) do
    solve(%__MODULE__{}, state, generate_fn)
  end

  def solve(%__MODULE__{solvers: solvers}, state, generate_fn) do
    Enum.reduce_while(solvers, {:ok, state}, fn solver, {:ok, acc} ->
      execute_solver(solver, acc, generate_fn)
    end)
  end

  defp execute_solver(solver, state, generate_fn) do
    result =
      cond do
        is_atom(solver) ->
          solver.solve(state, generate_fn)

        is_struct(solver) ->
          solver.__struct__.solve(solver, state, generate_fn)

        true ->
          {:error, {:invalid_solver, solver}}
      end

    case result do
      {:ok, new_state} ->
        if new_state.completed do
          {:halt, {:ok, new_state}}
        else
          {:cont, {:ok, new_state}}
        end

      error ->
        {:halt, error}
    end
  end
end
