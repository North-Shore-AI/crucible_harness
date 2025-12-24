# Crucible Harness: inspect-ai Solver/Generate Additions

**Date:** 2025-12-23
**Status:** Implementation Specification
**Purpose:** Add Solver, TaskState, and Generate abstractions from inspect-ai

---

## Scope

crucible_harness gets the **execution orchestration** patterns from inspect-ai:

| inspect-ai | crucible_harness | Purpose |
|------------|------------------|---------|
| `Solver` protocol | `CrucibleHarness.Solver` | Step abstraction |
| `chain()` | `CrucibleHarness.Solver.Chain` | Sequential composition |
| `TaskState` | `CrucibleHarness.TaskState` | State threading |
| `Generate` protocol | `CrucibleHarness.Generate` | Abstract LLM interface |
| `generate()` solver | `CrucibleHarness.Solver.Generate` | Built-in solver |

**NOT here:** Task, Sample, Scorer (those go in eval_ex)

---

## Module Specifications

### 1. CrucibleHarness.Solver

**File:** `lib/research_harness/solver.ex`

```elixir
defmodule CrucibleHarness.Solver do
  @moduledoc """
  Behaviour for composable execution steps.
  Maps to inspect-ai's Solver protocol.
  """

  alias CrucibleHarness.TaskState

  @type generate_fn :: (TaskState.t(), keyword() -> {:ok, TaskState.t()} | {:error, term()})

  @callback solve(state :: TaskState.t(), generate :: generate_fn()) ::
    {:ok, TaskState.t()} | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour CrucibleHarness.Solver
    end
  end
end
```

### 2. CrucibleHarness.Solver.Chain

**File:** `lib/research_harness/solver/chain.ex`

```elixir
defmodule CrucibleHarness.Solver.Chain do
  @moduledoc """
  Compose solvers sequentially. Stops if state.completed is true.
  """

  use CrucibleHarness.Solver

  defstruct solvers: []

  def new(solvers), do: %__MODULE__{solvers: List.flatten(solvers)}

  @impl true
  def solve(%__MODULE__{solvers: solvers}, state, generate) do
    Enum.reduce_while(solvers, {:ok, state}, fn solver, {:ok, acc} ->
      case solver.solve(acc, generate) do
        {:ok, new_state} ->
          if new_state.completed, do: {:halt, {:ok, new_state}}, else: {:cont, {:ok, new_state}}
        error -> {:halt, error}
      end
    end)
  end
end
```

### 3. CrucibleHarness.TaskState

**File:** `lib/research_harness/task_state.ex`

```elixir
defmodule CrucibleHarness.TaskState do
  @moduledoc """
  State object threaded through solver pipeline.
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
    :sample_id, :input,
    messages: [], output: nil, completed: false,
    metadata: %{}, store: %{}
  ]

  def new(sample) do
    %__MODULE__{
      sample_id: sample[:id],
      input: sample[:input],
      messages: input_to_messages(sample[:input]),
      metadata: sample[:metadata] || %{}
    }
  end

  def complete(state), do: %{state | completed: true}
  def add_message(state, msg), do: %{state | messages: state.messages ++ [msg]}
  def set_output(state, output), do: %{state | output: output}

  defp input_to_messages(input) when is_binary(input), do: [%{role: "user", content: input}]
  defp input_to_messages(messages) when is_list(messages), do: messages
end
```

### 4. CrucibleHarness.Generate

**File:** `lib/research_harness/generate.ex`

```elixir
defmodule CrucibleHarness.Generate do
  @moduledoc """
  Behaviour for LLM generation backends.
  Implementations wrap specific clients (tinkex, openai_ex, etc.)
  """

  @type config :: %{
    model: String.t(),
    temperature: float(),
    max_tokens: pos_integer(),
    stop: [String.t()]
  }

  @type response :: %{
    content: String.t(),
    finish_reason: String.t(),
    usage: map()
  }

  @callback generate(messages :: [map()], config :: config()) ::
    {:ok, response()} | {:error, term()}
end
```

### 5. CrucibleHarness.Solver.Generate

**File:** `lib/research_harness/solver/generate.ex`

```elixir
defmodule CrucibleHarness.Solver.Generate do
  @moduledoc """
  Solver that calls the generate function and updates state.
  """

  use CrucibleHarness.Solver

  defstruct config: %{}

  def new(config \\ %{}), do: %__MODULE__{config: config}

  @impl true
  def solve(%__MODULE__{config: config}, state, generate_fn) do
    case generate_fn.(state, config) do
      {:ok, response} ->
        {:ok, state
        |> CrucibleHarness.TaskState.add_message(%{role: "assistant", content: response.content})
        |> CrucibleHarness.TaskState.set_output(response)}
      error -> error
    end
  end
end
```

---

## File Structure

```
lib/research_harness/
├── solver.ex                  # NEW: Solver behaviour
├── solver/
│   ├── chain.ex               # NEW: Sequential composition
│   └── generate.ex            # NEW: LLM call solver
├── task_state.ex              # NEW: State struct
├── generate.ex                # NEW: LLM backend behaviour
└── (existing modules unchanged)
```

---

## Effort Estimate

| Component | LOC |
|-----------|-----|
| Solver behaviour | 20 |
| Chain | 30 |
| TaskState | 40 |
| Generate behaviour | 20 |
| Solver.Generate | 25 |
| Tests | 80 |
| **Total** | **~215** |

---

**Document Status:** Complete
**Last Updated:** 2025-12-23
