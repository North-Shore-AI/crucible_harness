defmodule CrucibleHarness.TaskStateTest do
  use ExUnit.Case, async: true

  alias CrucibleHarness.TaskState

  describe "new/1" do
    test "creates TaskState from sample with string input" do
      sample = %{id: "sample_1", input: "What is 2+2?"}
      state = TaskState.new(sample)

      assert state.sample_id == "sample_1"
      assert state.input == "What is 2+2?"
      assert state.messages == [%{role: "user", content: "What is 2+2?"}]
      assert state.output == nil
      assert state.completed == false
      assert state.metadata == %{}
      assert state.store == %{}
      assert state.epoch == 0
    end

    test "creates TaskState from sample with message list input" do
      messages = [
        %{role: "system", content: "You are a math tutor"},
        %{role: "user", content: "What is 2+2?"}
      ]

      sample = %{id: 123, input: messages}
      state = TaskState.new(sample)

      assert state.sample_id == 123
      assert state.input == messages
      assert state.messages == messages
      assert state.completed == false
    end

    test "creates TaskState with metadata" do
      sample = %{
        id: "sample_1",
        input: "test",
        metadata: %{category: "math", difficulty: "easy"}
      }

      state = TaskState.new(sample)

      assert state.metadata == %{category: "math", difficulty: "easy"}
    end

    test "creates TaskState with nil metadata" do
      sample = %{id: "sample_1", input: "test"}
      state = TaskState.new(sample)

      assert state.metadata == %{}
    end

    test "accepts overrides for model, epoch, target, choices, and limits" do
      sample = %{id: "sample_1", input: "test"}

      state =
        TaskState.new(sample,
          model: "gpt-4",
          epoch: 2,
          target: "Paris",
          choices: ["A", "B", "C"],
          message_limit: 8,
          token_limit: 100
        )

      assert state.model == "gpt-4"
      assert state.epoch == 2
      assert state.target == "Paris"
      assert length(state.choices.items) == 3
      assert state.message_limit == 8
      assert state.token_limit == 100
    end
  end

  describe "input_text/1" do
    test "returns input when input is a string" do
      state = TaskState.new(%{id: "sample_1", input: "Hello"})

      assert TaskState.input_text(state) == "Hello"
    end

    test "returns last user message when input is a list" do
      messages = [
        %{role: "system", content: "System"},
        %{role: "user", content: "First"},
        %{role: "assistant", content: "Ack"},
        %{role: "user", content: "Second"}
      ]

      state = TaskState.new(%{id: "sample_1", input: messages})

      assert TaskState.input_text(state) == "Second"
    end

    test "raises when no user message exists" do
      messages = [%{role: "system", content: "System"}]
      state = TaskState.new(%{id: "sample_1", input: messages})

      assert_raise ArgumentError, fn ->
        TaskState.input_text(state)
      end
    end
  end

  describe "user_prompt/1" do
    test "returns last user message" do
      messages = [
        %{role: "user", content: "First"},
        %{role: "assistant", content: "Ack"},
        %{role: "user", content: "Second"}
      ]

      state = TaskState.new(%{id: "sample_1", input: messages})

      assert TaskState.user_prompt(state) == %{role: "user", content: "Second"}
    end

    test "raises when no user message exists" do
      state = TaskState.new(%{id: "sample_1", input: [%{role: "system", content: "Sys"}]})

      assert_raise ArgumentError, fn ->
        TaskState.user_prompt(state)
      end
    end
  end

  describe "choices helper" do
    test "wraps choices with original positions and supports mark/shuffle" do
      choices = TaskState.Choices.new(["A", "B", "C"])

      assert Enum.map(choices.items, & &1.value) == ["A", "B", "C"]
      assert Enum.map(choices.items, & &1.original_position) == [0, 1, 2]

      choices = TaskState.Choices.mark_choice(choices, 1, true)
      assert Enum.at(choices.items, 1).correct == true

      shuffled = TaskState.Choices.shuffle(choices, seed: 123)
      assert Enum.map(shuffled.items, & &1.value) |> Enum.sort() == ["A", "B", "C"]
      assert Enum.all?(shuffled.items, &is_integer(&1.original_position))
    end
  end

  describe "complete/1" do
    test "marks state as completed" do
      sample = %{id: "sample_1", input: "test"}
      state = TaskState.new(sample)

      refute state.completed

      completed_state = TaskState.complete(state)

      assert completed_state.completed
    end

    test "preserves other fields when completing" do
      sample = %{id: "sample_1", input: "test"}
      state = TaskState.new(sample)
      state = TaskState.add_message(state, %{role: "assistant", content: "response"})
      state = TaskState.set_output(state, %{answer: "4"})

      completed_state = TaskState.complete(state)

      assert completed_state.sample_id == "sample_1"
      assert length(completed_state.messages) == 2
      assert completed_state.output == %{answer: "4"}
      assert completed_state.completed
    end
  end

  describe "add_message/2" do
    test "appends message to empty messages list" do
      sample = %{id: "sample_1", input: "test"}
      state = TaskState.new(sample)

      # Clear default messages
      state = %{state | messages: []}

      new_state = TaskState.add_message(state, %{role: "assistant", content: "response"})

      assert length(new_state.messages) == 1
      assert hd(new_state.messages) == %{role: "assistant", content: "response"}
    end

    test "appends message to existing messages" do
      sample = %{id: "sample_1", input: "test"}
      state = TaskState.new(sample)

      state = TaskState.add_message(state, %{role: "assistant", content: "first response"})
      state = TaskState.add_message(state, %{role: "user", content: "follow up"})
      state = TaskState.add_message(state, %{role: "assistant", content: "second response"})

      assert length(state.messages) == 4
      assert Enum.at(state.messages, -1) == %{role: "assistant", content: "second response"}
    end

    test "maintains message order" do
      sample = %{id: "sample_1", input: "start"}
      state = TaskState.new(sample)

      state =
        state
        |> TaskState.add_message(%{role: "assistant", content: "msg1"})
        |> TaskState.add_message(%{role: "user", content: "msg2"})
        |> TaskState.add_message(%{role: "assistant", content: "msg3"})

      roles = Enum.map(state.messages, & &1.role)
      assert roles == ["user", "assistant", "user", "assistant"]
    end
  end

  describe "set_output/2" do
    test "sets output on state" do
      sample = %{id: "sample_1", input: "test"}
      state = TaskState.new(sample)

      output = %{answer: "4", confidence: 0.95}
      new_state = TaskState.set_output(state, output)

      assert new_state.output == output
    end

    test "overwrites previous output" do
      sample = %{id: "sample_1", input: "test"}
      state = TaskState.new(sample)

      state = TaskState.set_output(state, %{answer: "3"})
      state = TaskState.set_output(state, %{answer: "4"})

      assert state.output == %{answer: "4"}
    end

    test "can set output to nil" do
      sample = %{id: "sample_1", input: "test"}
      state = TaskState.new(sample)

      state = TaskState.set_output(state, %{answer: "4"})
      state = TaskState.set_output(state, nil)

      assert state.output == nil
    end
  end

  describe "store field" do
    test "can be used to store arbitrary data" do
      sample = %{id: "sample_1", input: "test"}
      state = TaskState.new(sample)

      # Store can hold any data for solver communication
      state = %{state | store: %{intermediate_results: [1, 2, 3], step: 2}}

      assert state.store.intermediate_results == [1, 2, 3]
      assert state.store.step == 2
    end
  end

  describe "integration scenarios" do
    test "typical solver pipeline state transitions" do
      # Start with a sample
      sample = %{
        id: "math_001",
        input: "What is 15 + 27?",
        metadata: %{dataset: "arithmetic", difficulty: "easy"}
      }

      # Create initial state
      state = TaskState.new(sample)
      assert length(state.messages) == 1
      refute state.completed

      # First solver adds a message
      state =
        TaskState.add_message(state, %{role: "assistant", content: "Let me calculate that."})

      assert length(state.messages) == 2

      # Second solver adds output
      state = TaskState.set_output(state, %{answer: "42", steps: ["15", "+", "27", "=", "42"]})
      assert state.output.answer == "42"

      # Final solver marks complete
      state = TaskState.complete(state)
      assert state.completed

      # Verify all data is preserved
      assert state.sample_id == "math_001"
      assert state.metadata.difficulty == "easy"
      assert length(state.messages) == 2
    end

    test "using store for inter-solver communication" do
      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)

      # Solver 1 stores intermediate data
      state = %{state | store: Map.put(state.store, :solver1_data, %{value: 42})}

      # Solver 2 reads and adds more data
      solver1_value = state.store.solver1_data.value

      state = %{
        state
        | store:
            Map.put(state.store, :solver2_data, %{
              previous: solver1_value,
              doubled: solver1_value * 2
            })
      }

      assert state.store.solver1_data.value == 42
      assert state.store.solver2_data.doubled == 84
    end
  end
end
