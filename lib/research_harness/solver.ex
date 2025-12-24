defmodule CrucibleHarness.Solver do
  @moduledoc """
  Behaviour for composable execution steps.

  Solvers are the building blocks of task execution pipelines. Each solver
  implements the `solve/3` callback, which takes a `TaskState`, performs some
  operation (optionally calling the generate function), and returns an updated state.

  Solvers can be composed using `CrucibleHarness.Solver.Chain` to create
  multi-step pipelines.

  ## Implementing a Solver

      defmodule MySolver do
        use CrucibleHarness.Solver

        @impl true
        def solve(state, generate_fn) do
          # Perform some operation on the state
          new_state = CrucibleHarness.TaskState.add_message(
            state,
            %{role: "assistant", content: "Processing..."}
          )

          # Optionally call the generate function
          case generate_fn.(new_state, %{temperature: 0.7}) do
            {:ok, response} ->
              final_state = CrucibleHarness.TaskState.set_output(new_state, response)
              {:ok, final_state}

            error ->
              error
          end
        end
      end

  ## Using Solvers

      # Create a sample and initial state
      sample = %{id: "test_1", input: "What is 2+2?"}
      state = CrucibleHarness.TaskState.new(sample)

      # Define a generate function
      generate_fn = fn state, config ->
        # Call your LLM backend
        {:ok, %{content: "4", finish_reason: "stop", usage: %{}}}
      end

      # Run the solver
      {:ok, result_state} = MySolver.solve(state, generate_fn)

  ## Solver Composition

  Solvers can be chained together:

      alias CrucibleHarness.Solver.Chain

      chain = Chain.new([
        SystemPromptSolver,
        GenerateSolver.new(%{temperature: 0.7}),
        ValidationSolver
      ])

      {:ok, final_state} = Chain.solve(chain, state, generate_fn)
  """

  alias CrucibleHarness.TaskState

  @type generate_fn ::
          (TaskState.t(), map() -> {:ok, map()} | {:error, term()})

  @doc """
  Executes the solver on the given state.

  ## Parameters

    * `state` - The current `TaskState`
    * `generate_fn` - A function that takes a state and config, returns `{:ok, response}` or `{:error, term()}`

  ## Returns

    * `{:ok, new_state}` - Successfully processed state
    * `{:error, reason}` - Error occurred during processing
  """
  @callback solve(state :: TaskState.t(), generate_fn :: generate_fn()) ::
              {:ok, TaskState.t()} | {:error, term()}

  @doc """
  Uses the Solver behaviour in a module.

  This macro sets the `@behaviour CrucibleHarness.Solver` attribute.

  ## Example

      defmodule MySolver do
        use CrucibleHarness.Solver

        @impl true
        def solve(state, generate_fn) do
          # Implementation
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour CrucibleHarness.Solver
    end
  end
end
