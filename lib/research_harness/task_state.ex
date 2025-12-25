defmodule CrucibleHarness.TaskState do
  @moduledoc """
  State object threaded through solver pipeline.

  `TaskState` represents the execution state of a task as it flows through a chain
  of solvers. It contains the input, conversation messages, output, and metadata.

  ## Fields

    * `:model` - Model identifier for the run (string or nil)
    * `:sample_id` - Unique identifier for the sample (string or integer)
    * `:epoch` - Epoch index for repeated evaluations
    * `:input` - Original input (string or list of messages)
    * `:messages` - List of conversation messages (maps with `:role` and `:content`)
    * `:target` - Target output (string or list of strings)
    * `:choices` - Multiple choice answers (CrucibleHarness.TaskState.Choices)
    * `:output` - Final output from generation (map or nil)
    * `:message_limit` - Optional cap on total messages
    * `:token_limit` - Optional cap on total tokens
    * `:completed` - Boolean flag indicating if processing is complete
    * `:metadata` - Additional metadata about the sample (map)
    * `:store` - Key-value store for inter-solver communication (map)
    * `:scores` - Optional scoring results (map or nil)
    * `:tools` - Available tools for tool calling
    * `:tool_choice` - Tool choice directive

  ## Examples

      # Create state from a sample
      sample = %{id: "sample_1", input: "What is 2+2?"}
      state = TaskState.new(sample)

      # Add messages during processing
      state = TaskState.add_message(state, %{role: "assistant", content: "4"})

      # Set final output
      state = TaskState.set_output(state, %{answer: "4", confidence: 0.95})

      # Mark as complete
      state = TaskState.complete(state)

  ## Store Usage

  The `:store` field can be used for inter-solver communication:

      # Solver 1 stores data
      state = %{state | store: Map.put(state.store, :step1_result, %{value: 42})}

      # Solver 2 reads it
      step1_value = state.store.step1_result.value
  """

  @type t :: %__MODULE__{
          model: String.t() | nil,
          sample_id: String.t() | integer(),
          epoch: non_neg_integer(),
          input: String.t() | [map()],
          messages: [map()],
          target: String.t() | [String.t()],
          choices: CrucibleHarness.TaskState.Choices.t() | nil,
          output: map() | nil,
          message_limit: pos_integer() | nil,
          token_limit: pos_integer() | nil,
          completed: boolean(),
          metadata: map(),
          store: map(),
          scores: map() | nil,
          tools: [CrucibleHarness.Tool.t()],
          tool_choice: term()
        }

  defstruct [
    :model,
    :sample_id,
    :epoch,
    :input,
    messages: [],
    target: "",
    choices: nil,
    output: nil,
    message_limit: nil,
    token_limit: nil,
    completed: false,
    metadata: %{},
    store: %{},
    scores: nil,
    tools: [],
    tool_choice: nil
  ]

  @doc """
  Creates a new TaskState from a sample.

  The sample should be a map with at least `:id` and `:input` keys.
  Optionally, it can include `:metadata`.

  ## Examples

      iex> sample = %{id: "test_1", input: "Hello"}
      iex> state = TaskState.new(sample)
      iex> state.sample_id
      "test_1"
      iex> state.messages
      [%{role: "user", content: "Hello"}]

      iex> sample = %{id: 123, input: [%{role: "user", content: "Hi"}], metadata: %{type: "chat"}}
      iex> state = TaskState.new(sample)
      iex> state.sample_id
      123
      iex> state.metadata.type
      "chat"
  """
  def new(sample, opts \\ []) do
    model = Keyword.get(opts, :model, sample[:model])
    epoch = Keyword.get(opts, :epoch, sample[:epoch] || 0)
    target = Keyword.get(opts, :target, sample[:target] || "")
    choices = Keyword.get(opts, :choices, sample[:choices] || [])
    scores = Keyword.get(opts, :scores, sample[:scores])
    message_limit = Keyword.get(opts, :message_limit, sample[:message_limit])
    token_limit = Keyword.get(opts, :token_limit, sample[:token_limit])
    tools = Keyword.get(opts, :tools, sample[:tools] || [])
    tool_choice = Keyword.get(opts, :tool_choice, sample[:tool_choice])

    %__MODULE__{
      model: model,
      sample_id: sample[:id],
      epoch: epoch,
      input: sample[:input],
      messages: input_to_messages(sample[:input]),
      target: target,
      choices: CrucibleHarness.TaskState.Choices.new(choices || []),
      message_limit: message_limit,
      token_limit: token_limit,
      metadata: sample[:metadata] || %{},
      scores: scores,
      tools: CrucibleHarness.Tool.normalize_tools(tools),
      tool_choice: tool_choice
    }
  end

  @doc """
  Marks the state as completed.

  When a state is marked as completed, solver chains will stop processing.

  ## Examples

      iex> sample = %{id: "test_1", input: "test"}
      iex> state = TaskState.new(sample)
      iex> state.completed
      false
      iex> state = TaskState.complete(state)
      iex> state.completed
      true
  """
  def complete(state) do
    %{state | completed: true}
  end

  @doc """
  Adds a message to the state's message list.

  Messages are appended to the end of the list, maintaining conversation order.

  ## Examples

      iex> sample = %{id: "test_1", input: "Hello"}
      iex> state = TaskState.new(sample)
      iex> state = TaskState.add_message(state, %{role: "assistant", content: "Hi there!"})
      iex> length(state.messages)
      2
      iex> List.last(state.messages)
      %{role: "assistant", content: "Hi there!"}
  """
  def add_message(state, msg) do
    %{state | messages: state.messages ++ [msg]}
  end

  @doc """
  Sets the output field of the state.

  This typically contains the final response from generation, including
  content, finish reason, and usage statistics.

  ## Examples

      iex> sample = %{id: "test_1", input: "test"}
      iex> state = TaskState.new(sample)
      iex> state = TaskState.set_output(state, %{answer: "42", confidence: 0.95})
      iex> state.output.answer
      "42"
  """
  def set_output(state, output) do
    %{state | output: output}
  end

  @doc """
  Returns the input text from the original sample input.

  If the input is a list of messages, returns the last user message content.
  """
  @spec input_text(t()) :: String.t()
  def input_text(%__MODULE__{input: input}) when is_binary(input), do: input

  def input_text(%__MODULE__{input: input}) when is_list(input) do
    case Enum.find(Enum.reverse(input), fn msg -> get_role(msg) == "user" end) do
      nil -> raise ArgumentError, "input_text requested but no user message exists"
      msg -> get_content(msg)
    end
  end

  @doc """
  Returns the last user message from the current message history.
  """
  @spec user_prompt(t()) :: map()
  def user_prompt(%__MODULE__{messages: messages}) do
    case Enum.find(Enum.reverse(messages), fn msg -> get_role(msg) == "user" end) do
      nil -> raise ArgumentError, "user_prompt requested but no user message exists"
      msg -> msg
    end
  end

  @doc """
  Sets available tools for tool calling.
  """
  @spec set_tools(t(), [CrucibleHarness.Tool.t() | map()]) :: t()
  def set_tools(state, tools) do
    %{state | tools: CrucibleHarness.Tool.normalize_tools(tools)}
  end

  @doc """
  Sets the tool choice directive.
  """
  @spec set_tool_choice(t(), term()) :: t()
  def set_tool_choice(state, tool_choice) do
    %{state | tool_choice: tool_choice}
  end

  # Private helpers

  defp input_to_messages(input) when is_binary(input) do
    [%{role: "user", content: input}]
  end

  defp input_to_messages(messages) when is_list(messages) do
    messages
  end

  defp get_role(%{role: role}), do: role
  defp get_role(%{"role" => role}), do: role
  defp get_role(_), do: nil

  defp get_content(%{content: content}), do: content
  defp get_content(%{"content" => content}), do: content
  defp get_content(_), do: ""
end
