defmodule CrucibleHarness.SolverTest do
  use ExUnit.Case, async: true

  alias CrucibleHarness.{Solver, TaskState}

  # Test solver implementations
  defmodule SimpleSolver do
    use Solver

    @impl true
    def solve(state, _generate_fn) do
      new_state =
        TaskState.add_message(state, %{role: "assistant", content: "SimpleSolver response"})

      {:ok, new_state}
    end
  end

  defmodule ErrorSolver do
    use Solver

    @impl true
    def solve(_state, _generate_fn) do
      {:error, :test_error}
    end
  end

  defmodule CompletingSolver do
    use Solver

    @impl true
    def solve(state, _generate_fn) do
      new_state =
        state
        |> TaskState.add_message(%{role: "assistant", content: "Done"})
        |> TaskState.complete()

      {:ok, new_state}
    end
  end

  defmodule StoreSolver do
    use Solver

    @impl true
    def solve(state, _generate_fn) do
      new_store = Map.put(state.store, :visited, true)
      {:ok, %{state | store: new_store}}
    end
  end

  describe "Solver behaviour" do
    test "SimpleSolver implements the solve callback" do
      sample = %{id: "test_1", input: "test input"}
      state = TaskState.new(sample)

      generate_fn = fn _state, _opts ->
        {:ok, %{content: "mock", finish_reason: "stop", usage: %{}}}
      end

      {:ok, new_state} = SimpleSolver.solve(state, generate_fn)

      assert length(new_state.messages) == 2
      assert Enum.at(new_state.messages, -1).content == "SimpleSolver response"
    end

    test "ErrorSolver returns error tuple" do
      sample = %{id: "test_1", input: "test input"}
      state = TaskState.new(sample)

      generate_fn = fn _state, _opts ->
        {:ok, %{content: "mock", finish_reason: "stop", usage: %{}}}
      end

      assert {:error, :test_error} = ErrorSolver.solve(state, generate_fn)
    end

    test "CompletingSolver marks state as completed" do
      sample = %{id: "test_1", input: "test input"}
      state = TaskState.new(sample)

      generate_fn = fn _state, _opts ->
        {:ok, %{content: "mock", finish_reason: "stop", usage: %{}}}
      end

      {:ok, new_state} = CompletingSolver.solve(state, generate_fn)

      assert new_state.completed
    end

    test "StoreSolver can use store field" do
      sample = %{id: "test_1", input: "test input"}
      state = TaskState.new(sample)

      generate_fn = fn _state, _opts ->
        {:ok, %{content: "mock", finish_reason: "stop", usage: %{}}}
      end

      refute state.store[:visited]

      {:ok, new_state} = StoreSolver.solve(state, generate_fn)

      assert new_state.store[:visited]
    end
  end

  describe "Solver with generate function" do
    test "solver can call generate function" do
      defmodule GenerateUsingSolver do
        use Solver

        @impl true
        def solve(state, generate_fn) do
          case generate_fn.(state, %{temperature: 0.7}) do
            {:ok, response} ->
              new_state =
                TaskState.add_message(state, %{role: "assistant", content: response.content})

              {:ok, new_state}

            error ->
              error
          end
        end
      end

      sample = %{id: "test_1", input: "What is 2+2?"}
      state = TaskState.new(sample)

      generate_fn = fn state, opts ->
        assert opts[:temperature] == 0.7
        assert state.sample_id == "test_1"
        {:ok, %{content: "4", finish_reason: "stop", usage: %{tokens: 10}}}
      end

      {:ok, new_state} = GenerateUsingSolver.solve(state, generate_fn)

      assert Enum.at(new_state.messages, -1).content == "4"
    end

    test "solver propagates generate function errors" do
      defmodule GenerateErrorSolver do
        use Solver

        @impl true
        def solve(state, generate_fn) do
          generate_fn.(state, %{})
        end
      end

      sample = %{id: "test_1", input: "test"}
      state = TaskState.new(sample)

      generate_fn = fn _state, _opts ->
        {:error, :api_error}
      end

      assert {:error, :api_error} = GenerateErrorSolver.solve(state, generate_fn)
    end
  end

  describe "__using__ macro" do
    test "using Solver sets the behaviour" do
      # Check that our test modules have the behaviour set
      behaviours = SimpleSolver.__info__(:attributes)[:behaviour] || []
      assert Solver in behaviours
    end
  end
end
