defmodule CrucibleHarness.Solver.ChainTest do
  use ExUnit.Case, async: true

  alias CrucibleHarness.{Solver, TaskState}
  alias CrucibleHarness.Solver.Chain

  # Test solver implementations
  defmodule Step1Solver do
    use Solver

    @impl true
    def solve(state, _generate_fn) do
      new_state = TaskState.add_message(state, %{role: "assistant", content: "Step 1"})
      {:ok, new_state}
    end
  end

  defmodule Step2Solver do
    use Solver

    @impl true
    def solve(state, _generate_fn) do
      new_state = TaskState.add_message(state, %{role: "assistant", content: "Step 2"})
      {:ok, new_state}
    end
  end

  defmodule Step3Solver do
    use Solver

    @impl true
    def solve(state, _generate_fn) do
      new_state = TaskState.add_message(state, %{role: "assistant", content: "Step 3"})
      {:ok, new_state}
    end
  end

  defmodule CompletingSolver do
    use Solver

    @impl true
    def solve(state, _generate_fn) do
      new_state =
        state
        |> TaskState.add_message(%{role: "assistant", content: "Done - completing"})
        |> TaskState.complete()

      {:ok, new_state}
    end
  end

  defmodule ErrorSolver do
    use Solver

    @impl true
    def solve(_state, _generate_fn) do
      {:error, :solver_failed}
    end
  end

  defmodule CountingSolver do
    use Solver

    @impl true
    def solve(state, _generate_fn) do
      count = Map.get(state.store, :count, 0)
      new_state = %{state | store: Map.put(state.store, :count, count + 1)}
      {:ok, new_state}
    end
  end

  describe "new/1" do
    test "creates chain with single solver" do
      chain = Chain.new([Step1Solver])

      assert %Chain{solvers: [Step1Solver]} = chain
    end

    test "creates chain with multiple solvers" do
      chain = Chain.new([Step1Solver, Step2Solver, Step3Solver])

      assert %Chain{solvers: [Step1Solver, Step2Solver, Step3Solver]} = chain
    end

    test "creates chain with nested list (flattens)" do
      chain = Chain.new([[Step1Solver, Step2Solver], [Step3Solver]])

      assert %Chain{solvers: [Step1Solver, Step2Solver, Step3Solver]} = chain
    end

    test "creates chain with empty list" do
      chain = Chain.new([])

      assert %Chain{solvers: []} = chain
    end
  end

  describe "solve/3 with Chain struct" do
    test "executes single solver in chain" do
      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)
      chain = Chain.new([Step1Solver])
      generate_fn = fn _s, _o -> {:ok, %{content: "mock", finish_reason: "stop", usage: %{}}} end

      {:ok, result_state} = Chain.solve(chain, state, generate_fn)

      assert length(result_state.messages) == 2
      assert Enum.at(result_state.messages, -1).content == "Step 1"
    end

    test "executes multiple solvers in sequence" do
      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)
      chain = Chain.new([Step1Solver, Step2Solver, Step3Solver])
      generate_fn = fn _s, _o -> {:ok, %{content: "mock", finish_reason: "stop", usage: %{}}} end

      {:ok, result_state} = Chain.solve(chain, state, generate_fn)

      # Initial user message + 3 solver messages
      assert length(result_state.messages) == 4
      assert Enum.at(result_state.messages, 1).content == "Step 1"
      assert Enum.at(result_state.messages, 2).content == "Step 2"
      assert Enum.at(result_state.messages, 3).content == "Step 3"
    end

    test "threads state through chain correctly" do
      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)
      chain = Chain.new([CountingSolver, CountingSolver, CountingSolver])
      generate_fn = fn _s, _o -> {:ok, %{content: "mock", finish_reason: "stop", usage: %{}}} end

      {:ok, result_state} = Chain.solve(chain, state, generate_fn)

      assert result_state.store.count == 3
    end

    test "stops execution when state.completed is true" do
      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)
      chain = Chain.new([Step1Solver, CompletingSolver, Step2Solver, Step3Solver])
      generate_fn = fn _s, _o -> {:ok, %{content: "mock", finish_reason: "stop", usage: %{}}} end

      {:ok, result_state} = Chain.solve(chain, state, generate_fn)

      # Should have initial message + Step1 + CompletingSolver, but NOT Step2 or Step3
      assert length(result_state.messages) == 3
      assert Enum.at(result_state.messages, 1).content == "Step 1"
      assert Enum.at(result_state.messages, 2).content == "Done - completing"
      assert result_state.completed
    end

    test "stops and returns error when solver fails" do
      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)
      chain = Chain.new([Step1Solver, ErrorSolver, Step2Solver])
      generate_fn = fn _s, _o -> {:ok, %{content: "mock", finish_reason: "stop", usage: %{}}} end

      assert {:error, :solver_failed} = Chain.solve(chain, state, generate_fn)
    end

    test "handles empty chain" do
      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)
      chain = Chain.new([])
      generate_fn = fn _s, _o -> {:ok, %{content: "mock", finish_reason: "stop", usage: %{}}} end

      {:ok, result_state} = Chain.solve(chain, state, generate_fn)

      # State should be unchanged
      assert result_state == state
    end

    test "passes generate function to all solvers" do
      defmodule GenerateMockingSolver do
        use Solver

        @impl true
        def solve(state, generate_fn) do
          {:ok, response} = generate_fn.(state, %{model: "test"})

          new_state =
            TaskState.add_message(state, %{role: "assistant", content: response.content})

          {:ok, new_state}
        end
      end

      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)
      chain = Chain.new([GenerateMockingSolver, GenerateMockingSolver])

      call_count = :counters.new(1, [])

      generate_fn = fn _state, _opts ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)
        {:ok, %{content: "response_#{count}", finish_reason: "stop", usage: %{}}}
      end

      {:ok, result_state} = Chain.solve(chain, state, generate_fn)

      # Should have called generate twice
      assert :counters.get(call_count, 1) == 2
      assert Enum.at(result_state.messages, 1).content == "response_1"
      assert Enum.at(result_state.messages, 2).content == "response_2"
    end
  end

  describe "Chain as a Solver" do
    test "Chain implements Solver behaviour" do
      behaviours = Chain.__info__(:attributes)[:behaviour] || []
      assert Solver in behaviours
    end

    test "can nest chains" do
      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)

      inner_chain = Chain.new([Step1Solver, Step2Solver])
      outer_chain = Chain.new([inner_chain, Step3Solver])

      generate_fn = fn _s, _o -> {:ok, %{content: "mock", finish_reason: "stop", usage: %{}}} end

      {:ok, result_state} = Chain.solve(outer_chain, state, generate_fn)

      assert length(result_state.messages) == 4
      assert Enum.at(result_state.messages, 1).content == "Step 1"
      assert Enum.at(result_state.messages, 2).content == "Step 2"
      assert Enum.at(result_state.messages, 3).content == "Step 3"
    end
  end

  describe "integration scenarios" do
    test "realistic solver pipeline" do
      defmodule SystemPromptSolver do
        use Solver

        @impl true
        def solve(state, _generate_fn) do
          system_msg = %{role: "system", content: "You are a helpful assistant."}
          new_state = TaskState.add_message(%{state | messages: []}, system_msg)
          new_state = TaskState.add_message(new_state, %{role: "user", content: state.input})
          {:ok, new_state}
        end
      end

      defmodule QuerySolver do
        use Solver

        @impl true
        def solve(state, generate_fn) do
          case generate_fn.(state, %{temperature: 0.7, max_tokens: 100}) do
            {:ok, response} ->
              new_state =
                TaskState.add_message(state, %{role: "assistant", content: response.content})

              {:ok, new_state}

            error ->
              error
          end
        end
      end

      defmodule ValidateSolver do
        use Solver

        @impl true
        def solve(state, _generate_fn) do
          # Check if we got a response
          if Enum.any?(state.messages, &(&1.role == "assistant")) do
            new_state = TaskState.set_output(state, %{valid: true})
            {:ok, new_state}
          else
            {:error, :no_response}
          end
        end
      end

      sample = %{id: "test_1", input: "What is the capital of France?"}
      state = TaskState.new(sample)

      chain = Chain.new([SystemPromptSolver, QuerySolver, ValidateSolver])

      generate_fn = fn _state, _opts ->
        {:ok,
         %{
           content: "The capital of France is Paris.",
           finish_reason: "stop",
           usage: %{tokens: 15}
         }}
      end

      {:ok, result_state} = Chain.solve(chain, state, generate_fn)

      # Verify the pipeline worked
      assert length(result_state.messages) == 3
      assert Enum.at(result_state.messages, 0).role == "system"
      assert Enum.at(result_state.messages, 1).role == "user"
      assert Enum.at(result_state.messages, 2).role == "assistant"
      assert result_state.output.valid == true
    end
  end
end
