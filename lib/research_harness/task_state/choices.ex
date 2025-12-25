defmodule CrucibleHarness.TaskState.Choice do
  @moduledoc """
  Single multiple-choice option with correctness metadata.
  """

  @type t :: %__MODULE__{
          value: String.t(),
          correct: boolean() | nil,
          original_position: non_neg_integer()
        }

  defstruct [:value, :correct, :original_position]
end

defmodule CrucibleHarness.TaskState.Choices do
  @moduledoc """
  Collection of choices for multiple-choice tasks.
  """

  alias CrucibleHarness.TaskState.Choice

  @type t :: %__MODULE__{items: [Choice.t()]}

  defstruct items: []

  @doc """
  Build a Choices struct from a list of strings or Choice structs.
  """
  @spec new([String.t() | Choice.t()]) :: t()
  def new(choices) when is_list(choices) do
    items =
      choices
      |> Enum.with_index()
      |> Enum.map(fn
        {%Choice{} = choice, _idx} ->
          choice

        {value, idx} ->
          %Choice{value: to_string(value), correct: nil, original_position: idx}
      end)

    %__MODULE__{items: items}
  end

  @doc """
  Mark a choice as correct or incorrect.
  """
  @spec mark_choice(t(), non_neg_integer(), boolean()) :: t()
  def mark_choice(%__MODULE__{items: items} = choices, index, correct) do
    updated =
      List.update_at(items, index, fn item ->
        %{item | correct: correct}
      end)

    %{choices | items: updated}
  end

  @doc """
  Shuffle the choices, preserving original positions relative to the pre-shuffle order.
  """
  @spec shuffle(t(), keyword()) :: t()
  def shuffle(%__MODULE__{items: items} = choices, opts \\ []) do
    seed = Keyword.get(opts, :seed)
    positions = Enum.to_list(0..(length(items) - 1))
    shuffled_positions = shuffle_positions(positions, seed)

    shuffled_items =
      Enum.map(shuffled_positions, fn idx ->
        item = Enum.at(items, idx)
        %{item | original_position: idx}
      end)

    %{choices | items: shuffled_items}
  end

  defp shuffle_positions(positions, nil), do: Enum.shuffle(positions)

  defp shuffle_positions(positions, seed) when is_integer(seed) do
    previous_seed = :rand.export_seed()
    :rand.seed(:exsplus, {seed, seed, seed})
    shuffled = Enum.shuffle(positions)
    :rand.seed(previous_seed)
    shuffled
  end
end
