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
    tool_calls_mode = normalize_tool_calls(Map.get(config, :tool_calls, :loop))
    config = Map.delete(config, :tool_calls)

    do_generate(state, generate_fn, config, tool_calls_mode, 0)
  end

  defp do_generate(state, generate_fn, config, tool_calls_mode, depth) do
    config =
      config
      |> maybe_put_tools(state.tools)
      |> maybe_put_tool_choice(state.tool_choice)
      |> maybe_put_model(state)

    case generate_fn.(state, config) do
      {:ok, response} ->
        handle_generation_success(response, state, generate_fn, config, tool_calls_mode, depth)

      error ->
        error
    end
  end

  defp apply_tool_calls(state, tool_calls) do
    Enum.reduce(tool_calls, state, fn tool_call, acc ->
      tool_name = tool_call_name(tool_call)
      tool_args = tool_call_args(tool_call)
      tool = CrucibleHarness.Tool.find(acc.tools, tool_name)

      {content, metadata} =
        case CrucibleHarness.Tool.execute(tool, tool_args) do
          {:ok, result} -> {result, %{}}
          {:error, reason} -> {inspect(reason), %{error: reason}}
        end

      tool_message =
        %{
          role: "tool",
          content: to_string(content),
          name: tool_name,
          tool_call_id: tool_call_id(tool_call)
        }
        |> Map.merge(metadata)

      acc
      |> TaskState.add_message(tool_message)
      |> maybe_mark_completed()
    end)
  end

  defp extract_tool_calls(response) do
    response[:tool_calls] || response["tool_calls"] || []
  end

  defp maybe_put_tool_calls(message, response) do
    tool_calls = extract_tool_calls(response)

    if tool_calls == [] do
      message
    else
      Map.put(message, :tool_calls, tool_calls)
    end
  end

  defp maybe_mark_completed(state) do
    state
    |> maybe_mark_message_limit()
    |> maybe_mark_token_limit()
  end

  defp maybe_mark_message_limit(%TaskState{message_limit: nil} = state), do: state

  defp maybe_mark_message_limit(%TaskState{message_limit: limit, messages: messages} = state)
       when is_integer(limit) do
    if length(messages) >= limit do
      %{state | completed: true}
    else
      state
    end
  end

  defp maybe_mark_token_limit(%TaskState{token_limit: nil} = state), do: state

  defp maybe_mark_token_limit(%TaskState{token_limit: limit, output: output} = state)
       when is_integer(limit) and is_map(output) do
    if output_token_count(output) >= limit do
      %{state | completed: true}
    else
      state
    end
  end

  defp maybe_mark_token_limit(state), do: state

  defp output_token_count(%{usage: usage}) when is_map(usage) do
    usage[:total_tokens] || usage["total_tokens"] || 0
  end

  defp output_token_count(_), do: 0

  defp tool_call_name(%{name: name}), do: name
  defp tool_call_name(%{"name" => name}), do: name
  defp tool_call_name(_), do: nil

  defp tool_call_args(%{arguments: args}) when is_map(args), do: args
  defp tool_call_args(%{"arguments" => args}) when is_map(args), do: args
  defp tool_call_args(_), do: %{}

  defp tool_call_id(%{id: id}), do: id
  defp tool_call_id(%{"id" => id}), do: id
  defp tool_call_id(_), do: nil

  defp normalize_tool_calls(mode) when mode in [:loop, "loop"], do: :loop
  defp normalize_tool_calls(mode) when mode in [:single, "single"], do: :single
  defp normalize_tool_calls(mode) when mode in [:none, "none"], do: :none
  defp normalize_tool_calls(_), do: :loop

  defp maybe_put_tools(config, tools) when is_list(tools) and tools != [] do
    Map.put_new(config, :tools, tools)
  end

  defp maybe_put_tools(config, _tools), do: config

  defp maybe_put_tool_choice(config, nil), do: config

  defp maybe_put_tool_choice(config, tool_choice),
    do: Map.put_new(config, :tool_choice, tool_choice)

  defp maybe_put_model(config, %TaskState{model: nil}), do: config
  defp maybe_put_model(config, %TaskState{model: model}), do: Map.put_new(config, :model, model)

  defp handle_generation_success(response, state, generate_fn, config, tool_calls_mode, depth) do
    assistant_message =
      %{role: "assistant", content: response.content}
      |> maybe_put_tool_calls(response)

    state =
      state
      |> TaskState.add_message(assistant_message)
      |> TaskState.set_output(response)
      |> maybe_mark_completed()

    tool_calls = extract_tool_calls(response)
    handle_tool_calls(state, tool_calls, tool_calls_mode, generate_fn, config, depth)
  end

  defp handle_tool_calls(state, _tool_calls, :none, _gn, _cfg, _d), do: {:ok, state}
  defp handle_tool_calls(state, [], _mode, _gn, _cfg, _d), do: {:ok, state}
  defp handle_tool_calls(%{completed: true} = state, _tc, _mode, _gn, _cfg, _d), do: {:ok, state}

  defp handle_tool_calls(state, tool_calls, :single, _gn, _cfg, _d) do
    {:ok, apply_tool_calls(state, tool_calls)}
  end

  defp handle_tool_calls(state, tool_calls, :loop, generate_fn, config, depth) do
    state = apply_tool_calls(state, tool_calls)

    if state.completed do
      {:ok, state}
    else
      do_generate(state, generate_fn, config, :loop, depth + 1)
    end
  end
end
