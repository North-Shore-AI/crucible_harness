defmodule CrucibleHarness.Solver.GenerateTest do
  use ExUnit.Case, async: true

  alias CrucibleHarness.{Solver, TaskState}
  alias CrucibleHarness.Solver.Generate, as: GenerateSolver

  describe "new/1" do
    test "creates GenerateSolver with default config" do
      solver = GenerateSolver.new()

      assert %GenerateSolver{config: %{}} = solver
    end

    test "creates GenerateSolver with custom config" do
      config = %{temperature: 0.9, max_tokens: 500}
      solver = GenerateSolver.new(config)

      assert %GenerateSolver{config: ^config} = solver
    end

    test "creates GenerateSolver with full config" do
      config = %{
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000,
        stop: ["\n\n"],
        top_p: 0.9
      }

      solver = GenerateSolver.new(config)

      assert solver.config.model == "gpt-4"
      assert solver.config.temperature == 0.7
      assert solver.config.max_tokens == 1000
      assert solver.config.stop == ["\n\n"]
      assert solver.config.top_p == 0.9
    end
  end

  describe "solve/3" do
    test "calls generate function with state and config" do
      sample = %{id: "test_1", input: "What is 2+2?"}
      state = TaskState.new(sample)
      solver = GenerateSolver.new(%{temperature: 0.7})

      generate_fn = fn received_state, received_config ->
        # Verify the state and config passed to generate
        assert received_state.sample_id == "test_1"
        assert received_config.temperature == 0.7

        {:ok,
         %{
           content: "The answer is 4",
           finish_reason: "stop",
           usage: %{tokens: 10}
         }}
      end

      {:ok, result_state} = GenerateSolver.solve(solver, state, generate_fn)

      # Verify the state was updated correctly
      assert length(result_state.messages) == 2
      assert Enum.at(result_state.messages, -1).role == "assistant"
      assert Enum.at(result_state.messages, -1).content == "The answer is 4"
    end

    test "adds assistant message to state" do
      sample = %{id: "test_1", input: "Hello"}
      state = TaskState.new(sample)
      solver = GenerateSolver.new()

      generate_fn = fn _state, _config ->
        {:ok, %{content: "Hi there!", finish_reason: "stop", usage: %{}}}
      end

      {:ok, result_state} = GenerateSolver.solve(solver, state, generate_fn)

      messages = result_state.messages
      assert length(messages) == 2
      assert Enum.at(messages, 0) == %{role: "user", content: "Hello"}
      assert Enum.at(messages, 1) == %{role: "assistant", content: "Hi there!"}
    end

    test "sets output to response" do
      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)
      solver = GenerateSolver.new()

      response = %{
        content: "response content",
        finish_reason: "stop",
        usage: %{prompt_tokens: 5, completion_tokens: 10, total_tokens: 15}
      }

      generate_fn = fn _state, _config -> {:ok, response} end

      {:ok, result_state} = GenerateSolver.solve(solver, state, generate_fn)

      assert result_state.output == response
      assert result_state.output.usage.total_tokens == 15
    end

    test "propagates generate errors" do
      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)
      solver = GenerateSolver.new()

      generate_fn = fn _state, _config -> {:error, :api_timeout} end

      assert {:error, :api_timeout} = GenerateSolver.solve(solver, state, generate_fn)
    end

    test "works with multi-turn conversation" do
      sample = %{
        id: "test_1",
        input: [
          %{role: "system", content: "You are helpful"},
          %{role: "user", content: "First question"}
        ]
      }

      state = TaskState.new(sample)
      solver = GenerateSolver.new()

      generate_fn = fn state, _config ->
        # Verify we have the conversation history
        assert length(state.messages) == 2
        {:ok, %{content: "First answer", finish_reason: "stop", usage: %{}}}
      end

      {:ok, result_state} = GenerateSolver.solve(solver, state, generate_fn)

      assert length(result_state.messages) == 3
      assert Enum.at(result_state.messages, -1).content == "First answer"
    end

    test "passes empty config when not provided" do
      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)
      solver = GenerateSolver.new()

      generate_fn = fn _state, config ->
        assert config == %{}
        {:ok, %{content: "response", finish_reason: "stop", usage: %{}}}
      end

      {:ok, _result_state} = GenerateSolver.solve(solver, state, generate_fn)
    end

    test "merges solver config with generate call" do
      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)
      solver = GenerateSolver.new(%{temperature: 0.5, max_tokens: 100})

      generate_fn = fn _state, config ->
        assert config.temperature == 0.5
        assert config.max_tokens == 100
        {:ok, %{content: "response", finish_reason: "stop", usage: %{}}}
      end

      {:ok, _result_state} = GenerateSolver.solve(solver, state, generate_fn)
    end

    test "resolves tool calls in loop mode" do
      tool =
        CrucibleHarness.Tool.new(
          name: "adder",
          handler: fn %{"a" => a, "b" => b} -> {:ok, "#{a + b}"} end
        )

      state =
        TaskState.new(%{id: "test_1", input: "add"})
        |> TaskState.set_tools([tool])

      solver = GenerateSolver.new(%{tool_calls: "loop"})

      call_count = :counters.new(1, [])

      generate_fn = fn _state, _config ->
        :counters.add(call_count, 1, 1)

        case :counters.get(call_count, 1) do
          1 ->
            {:ok,
             %{
               content: "",
               finish_reason: "tool_calls",
               usage: %{total_tokens: 5},
               tool_calls: [%{name: "adder", arguments: %{"a" => 2, "b" => 3}}]
             }}

          2 ->
            {:ok, %{content: "5", finish_reason: "stop", usage: %{total_tokens: 7}}}
        end
      end

      {:ok, result_state} = GenerateSolver.solve(solver, state, generate_fn)

      assert :counters.get(call_count, 1) == 2
      assert Enum.at(result_state.messages, -1).content == "5"
      assert result_state.output.content == "5"
    end

    test "resolves tool calls once in single mode" do
      tool =
        CrucibleHarness.Tool.new(
          name: "echo",
          handler: fn %{"value" => value} -> {:ok, value} end
        )

      state =
        TaskState.new(%{id: "test_1", input: "echo"})
        |> TaskState.set_tools([tool])

      solver = GenerateSolver.new(%{tool_calls: "single"})

      generate_fn = fn _state, _config ->
        {:ok,
         %{
           content: "",
           finish_reason: "tool_calls",
           usage: %{total_tokens: 5},
           tool_calls: [%{name: "echo", arguments: %{"value" => "hi"}}]
         }}
      end

      {:ok, result_state} = GenerateSolver.solve(solver, state, generate_fn)

      assert Enum.any?(result_state.messages, &(&1.role == "tool"))
      assert result_state.output.finish_reason == "tool_calls"
    end

    test "ignores tool calls when disabled" do
      tool =
        CrucibleHarness.Tool.new(
          name: "noop",
          handler: fn _ -> {:ok, "ignored"} end
        )

      state =
        TaskState.new(%{id: "test_1", input: "noop"})
        |> TaskState.set_tools([tool])

      solver = GenerateSolver.new(%{tool_calls: "none"})

      generate_fn = fn _state, _config ->
        {:ok,
         %{
           content: "done",
           finish_reason: "stop",
           usage: %{total_tokens: 5},
           tool_calls: [%{name: "noop", arguments: %{}}]
         }}
      end

      {:ok, result_state} = GenerateSolver.solve(solver, state, generate_fn)

      refute Enum.any?(result_state.messages, &(&1.role == "tool"))
      assert result_state.output.content == "done"
    end

    test "marks state completed when message limit is reached" do
      state =
        TaskState.new(%{id: "test_1", input: "Hello"}, message_limit: 2)

      solver = GenerateSolver.new()

      generate_fn = fn _state, _config ->
        {:ok, %{content: "Hi", finish_reason: "stop", usage: %{total_tokens: 5}}}
      end

      {:ok, result_state} = GenerateSolver.solve(solver, state, generate_fn)

      assert length(result_state.messages) == 2
      assert result_state.completed
    end
  end

  describe "GenerateSolver as a Solver" do
    test "implements Solver behaviour" do
      behaviours = GenerateSolver.__info__(:attributes)[:behaviour] || []
      assert Solver in behaviours
    end

    test "can be used in a chain" do
      alias CrucibleHarness.Solver.Chain

      defmodule SetupSolver do
        use Solver

        @impl true
        def solve(state, _generate_fn) do
          # Add a system message
          new_state = TaskState.add_message(state, %{role: "system", content: "Be concise"})
          {:ok, new_state}
        end
      end

      sample = %{id: "test_1", input: "What is the capital of France?"}
      state = TaskState.new(sample)

      generate_solver = GenerateSolver.new(%{temperature: 0.7})
      chain = Chain.new([SetupSolver, generate_solver])

      generate_fn = fn state, _config ->
        # Should have system message, original user message
        assert length(state.messages) >= 2
        {:ok, %{content: "Paris", finish_reason: "stop", usage: %{}}}
      end

      {:ok, result_state} = Chain.solve(chain, state, generate_fn)

      # Should have: user (from initial state), system (from SetupSolver), assistant (from generate)
      assert length(result_state.messages) == 3
      assert Enum.at(result_state.messages, 0).role == "user"
      assert Enum.at(result_state.messages, 1).role == "system"
      assert Enum.at(result_state.messages, 2).role == "assistant"
      assert result_state.output.content == "Paris"
    end
  end

  describe "integration scenarios" do
    test "typical generate workflow" do
      sample = %{
        id: "math_001",
        input: "Solve: 15 + 27 = ?",
        metadata: %{category: "arithmetic"}
      }

      state = TaskState.new(sample)

      config = %{
        model: "test-model",
        temperature: 0.0,
        max_tokens: 50,
        stop: ["\n"]
      }

      solver = GenerateSolver.new(config)

      generate_fn = fn state, received_config ->
        # Verify inputs
        assert state.sample_id == "math_001"
        assert received_config.temperature == 0.0

        # Simulate API response
        {:ok,
         %{
           content: "15 + 27 = 42",
           finish_reason: "stop",
           usage: %{
             prompt_tokens: 8,
             completion_tokens: 7,
             total_tokens: 15
           }
         }}
      end

      {:ok, final_state} = GenerateSolver.solve(solver, state, generate_fn)

      # Verify final state
      assert final_state.sample_id == "math_001"
      assert final_state.metadata.category == "arithmetic"
      assert length(final_state.messages) == 2
      assert final_state.output.content == "15 + 27 = 42"
      assert final_state.output.usage.total_tokens == 15
    end

    test "error recovery in generate" do
      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)
      solver = GenerateSolver.new()

      # Simulate transient error then success
      call_count = :counters.new(1, [])

      generate_fn = fn _state, _config ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        case count do
          0 -> {:error, :timeout}
          _ -> {:ok, %{content: "success", finish_reason: "stop", usage: %{}}}
        end
      end

      # First call fails
      assert {:error, :timeout} = GenerateSolver.solve(solver, state, generate_fn)

      # Second call succeeds
      {:ok, result_state} = GenerateSolver.solve(solver, state, generate_fn)
      assert result_state.output.content == "success"
    end

    test "preserves state across multiple generates in chain" do
      alias CrucibleHarness.Solver.Chain

      sample = %{id: "test_1", input: "Start"}
      state = TaskState.new(sample)

      solver1 = GenerateSolver.new(%{model: "model-1"})
      solver2 = GenerateSolver.new(%{model: "model-2"})

      chain = Chain.new([solver1, solver2])

      call_count = :counters.new(1, [])

      generate_fn = fn state, config ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        content = "Response #{count + 1} from #{config.model}"

        # Verify state accumulates messages
        expected_messages = 1 + count
        assert length(state.messages) == expected_messages

        {:ok, %{content: content, finish_reason: "stop", usage: %{}}}
      end

      {:ok, final_state} = Chain.solve(chain, state, generate_fn)

      # Should have: initial user message + 2 assistant messages
      assert length(final_state.messages) == 3
      assert Enum.at(final_state.messages, 0).role == "user"
      assert Enum.at(final_state.messages, 1).role == "assistant"
      assert Enum.at(final_state.messages, 1).content == "Response 1 from model-1"
      assert Enum.at(final_state.messages, 2).role == "assistant"
      assert Enum.at(final_state.messages, 2).content == "Response 2 from model-2"
    end
  end
end
