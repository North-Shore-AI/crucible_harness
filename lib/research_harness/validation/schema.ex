defmodule CrucibleHarness.Validation.Schema do
  @moduledoc false

  def float(opts \\ []) do
    build_schema(:float, opts)
  end

  def number(opts \\ []) do
    build_schema(:number, opts)
  end

  def map(opts \\ []) do
    opts = Keyword.put_new(opts, :required, false)
    build_schema(:map, opts)
  end

  def percentage do
    float(min: 0.0, max: 100.0)
  end

  def probability do
    float(min: 0.0, max: 1.0)
  end

  def positive_number do
    number(min: 0)
  end

  def duration_ms do
    number(min: 0, unit: :milliseconds)
  end

  defp build_schema(type, opts) do
    %{
      type: type,
      required: Keyword.get(opts, :required, true),
      min: Keyword.get(opts, :min),
      max: Keyword.get(opts, :max),
      default: Keyword.get(opts, :default),
      unit: Keyword.get(opts, :unit),
      schema: Keyword.get(opts, :schema, %{})
    }
  end
end
