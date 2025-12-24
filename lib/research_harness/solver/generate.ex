defmodule CrucibleHarness.Solver.Generate do
  @moduledoc """
  Solver that calls the generate function and updates state.

  This is a built-in solver that handles the common pattern of calling an LLM
  generation function and updating the state with the response. It adds the
  assistant's message to the conversation and stores the full response in the
  output field.

  ## Examples

      # Create a generate solver with configuration
      solver = Solver.Generate.new(%{
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000,
        stop: []
      })

      # Use in a chain
      alias CrucibleHarness.Solver.Chain

      chain = Chain.new([
        SystemPromptSolver,
        Solver.Generate.new(%{temperature: 0.7}),
        PostProcessSolver
      ])

  ## Configuration

  The config passed to `new/1` is forwarded to the generate function when
  the solver executes. Common config options:

    * `:model` - Model identifier
    * `:temperature` - Sampling temperature (0.0-1.0+)
    * `:max_tokens` - Maximum tokens to generate
    * `:stop` - List of stop sequences
    * Any other backend-specific parameters

  ## State Updates

  When the solver executes successfully:

  1. Calls the generate function with current state and config
  2. Adds an assistant message to `state.messages` with the response content
  3. Sets `state.output` to the full response (including usage statistics)
  4. Returns the updated state

  ## Error Handling

  If the generate function returns an error, the solver propagates it:

      {:error, :timeout} = generate_fn.(state, config)
      # Solver returns {:error, :timeout}

  ## Complete Example

      # Define your backend
      defmodule MyBackend do
        @behaviour CrucibleHarness.Generate

        @impl true
        def generate(messages, config) do
          # Call API
          {:ok, %{
            content: "Response text",
            finish_reason: "stop",
            usage: %{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30}
          }}
        end
      end

      # Create generate function
      generate_fn = fn state, config ->
        MyBackend.generate(state.messages, config)
      end

      # Create and run solver
      sample = %{id: "test_1", input: "Hello"}
      state = CrucibleHarness.TaskState.new(sample)

      solver = CrucibleHarness.Solver.Generate.new(%{
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 100,
        stop: []
      })

      {:ok, result_state} = solver.solve(state, generate_fn)

      # result_state.messages => [
      #   %{role: "user", content: "Hello"},
      #   %{role: "assistant", content: "Response text"}
      # ]
      # result_state.output => %{content: "Response text", finish_reason: "stop", ...}
  """

  use CrucibleHarness.Solver

  alias CrucibleHarness.TaskState

  @type t :: %__MODULE__{
          config: map()
        }

  defstruct config: %{}

  @doc """
  Creates a new Generate solver.

  ## Parameters

    * `config` - Configuration map to pass to the generate function (default: `%{}`)

  ## Examples

      # With no config
      solver = Solver.Generate.new()

      # With model parameters
      solver = Solver.Generate.new(%{
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000,
        stop: []
      })

      # With additional backend-specific options
      solver = Solver.Generate.new(%{
        model: "claude-3-opus",
        temperature: 0.8,
        max_tokens: 2000,
        stop: [],
        top_p: 0.9,
        presence_penalty: 0.1
      })
  """
  def new(config \\ %{}) do
    %__MODULE__{config: config}
  end

  @doc """
  Executes the generate solver.

  Calls the generate function with the current state's messages and the
  solver's configuration, then updates the state with the response.

  ## Parameters

    * `solver` - The Generate solver struct
    * `state` - Current TaskState
    * `generate_fn` - Function that takes (state, config) and returns {:ok, response} or {:error, term}

  ## Returns

    * `{:ok, updated_state}` - State with new assistant message and output set
    * `{:error, reason}` - Error from the generate function

  ## Examples

      solver = Solver.Generate.new(%{temperature: 0.7})
      {:ok, state} = solver.solve(state, generate_fn)
  """
  @impl true
  def solve(state, generate_fn) do
    solve(%__MODULE__{}, state, generate_fn)
  end

  def solve(%__MODULE__{config: config}, state, generate_fn) do
    case generate_fn.(state, config) do
      {:ok, response} ->
        new_state =
          state
          |> TaskState.add_message(%{role: "assistant", content: response.content})
          |> TaskState.set_output(response)

        {:ok, new_state}

      error ->
        error
    end
  end
end
