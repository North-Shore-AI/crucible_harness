defmodule CrucibleHarness.Errors.DLQ do
  @moduledoc false

  def write(task, retry_result, path) do
    entry =
      task
      |> Map.new()
      |> Map.merge(%{
        retry_result: retry_result,
        timestamp: DateTime.utc_now()
      })
      |> sanitize_term()

    json = Jason.encode!(entry)
    :ok = File.mkdir_p(Path.dirname(path))
    File.write(path, json <> "\n", [:append])
  end

  def read(path) do
    if File.exists?(path) do
      entries =
        path
        |> File.stream!(:line, [])
        |> Enum.map(fn line -> Jason.decode!(line, keys: :atoms!) end)

      {:ok, entries}
    else
      {:ok, []}
    end
  end

  defp sanitize_term(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end

  defp sanitize_term(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> sanitize_term()
  end

  defp sanitize_term(%{} = map) do
    map
    |> Enum.map(fn {k, v} -> {k, sanitize_term(v)} end)
    |> Enum.into(%{})
  end

  defp sanitize_term(list) when is_list(list), do: Enum.map(list, &sanitize_term/1)

  defp sanitize_term(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> sanitize_term()
  end

  defp sanitize_term(other), do: other
end
