defmodule CrucibleHarness.Tool do
  @moduledoc """
  Tool definition for model tool-calling flows.
  """

  @type handler ::
          (map() -> {:ok, term()} | {:error, term()} | term())

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          parameters: map(),
          handler: handler()
        }

  defstruct [:name, :description, :parameters, :handler]

  @doc """
  Build a tool from keyword options.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.get(opts, :description),
      parameters: Keyword.get(opts, :parameters, %{}),
      handler: Keyword.fetch!(opts, :handler)
    }
  end

  @doc """
  Normalize a list of tool specs into Tool structs.
  """
  @spec normalize_tools([t() | map() | {String.t(), handler()}]) :: [t() | map()]
  def normalize_tools(tools) when is_list(tools) do
    Enum.map(tools, fn
      %__MODULE__{} = tool ->
        tool

      {name, handler} when is_binary(name) and is_function(handler, 1) ->
        new(name: name, handler: handler)

      %{name: name, handler: handler} = map when is_binary(name) and is_function(handler, 1) ->
        new(
          name: name,
          handler: handler,
          description: Map.get(map, :description),
          parameters: Map.get(map, :parameters, %{})
        )

      %{"name" => name, "handler" => handler} = map
      when is_binary(name) and is_function(handler, 1) ->
        new(
          name: name,
          handler: handler,
          description: Map.get(map, "description"),
          parameters: Map.get(map, "parameters", %{})
        )

      other ->
        other
    end)
  end

  @doc """
  Find a tool by name in a list.
  """
  @spec find([t() | map()], String.t()) :: t() | map() | nil
  def find(tools, name) do
    Enum.find(tools, fn tool -> tool_name(tool) == name end)
  end

  @doc """
  Execute a tool handler.
  """
  @spec execute(t() | map(), map()) :: {:ok, term()} | {:error, term()}
  def execute(%__MODULE__{handler: handler}, args) do
    apply_handler(handler, args)
  end

  def execute(%{handler: handler}, args) when is_function(handler, 1) do
    apply_handler(handler, args)
  end

  def execute(_tool, _args), do: {:error, :invalid_tool}

  defp tool_name(%__MODULE__{name: name}), do: name
  defp tool_name(%{name: name}), do: name
  defp tool_name(%{"name" => name}), do: name
  defp tool_name(_), do: nil

  defp apply_handler(handler, args) when is_function(handler, 1) do
    case handler.(args) do
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
      other -> {:ok, other}
    end
  end
end
