defmodule CrucibleHarness.TaskState do
  @moduledoc """
  State object threaded through solver pipeline.

  `TaskState` represents the execution state of a task as it flows through a chain
  of solvers. It contains the input, conversation messages, output, and metadata.

  ## Fields

    * `:sample_id` - Unique identifier for the sample (string or integer)
    * `:input` - Original input (string or list of messages)
    * `:messages` - List of conversation messages (maps with `:role` and `:content`)
    * `:output` - Final output from generation (map or nil)
    * `:completed` - Boolean flag indicating if processing is complete
    * `:metadata` - Additional metadata about the sample (map)
    * `:store` - Key-value store for inter-solver communication (map)

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
          sample_id: String.t() | integer(),
          input: String.t() | [map()],
          messages: [map()],
          output: map() | nil,
          completed: boolean(),
          metadata: map(),
          store: map()
        }

  defstruct [
    :sample_id,
    :input,
    messages: [],
    output: nil,
    completed: false,
    metadata: %{},
    store: %{}
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
  def new(sample) do
    %__MODULE__{
      sample_id: sample[:id],
      input: sample[:input],
      messages: input_to_messages(sample[:input]),
      metadata: sample[:metadata] || %{}
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

  # Private helpers

  defp input_to_messages(input) when is_binary(input) do
    [%{role: "user", content: input}]
  end

  defp input_to_messages(messages) when is_list(messages) do
    messages
  end
end
