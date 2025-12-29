defmodule CrucibleHarness.Validation.MetricValidator do
  @moduledoc false

  def validate(metrics, schemas, config \\ %{}) do
    coerce_types = Map.get(config, :coerce_types, false)

    {errors, validated} = validate_metrics(metrics, schemas, coerce_types, nil)

    if errors == [] do
      {:ok, validated}
    else
      {:error, errors}
    end
  end

  def handle_validation_error(errors, config) do
    case Map.get(config, :on_invalid, :abort) do
      :log_and_continue -> {:warning, errors}
      :log_and_retry -> {:retry, errors}
      _ -> {:error, errors}
    end
  end

  defp validate_metrics(metrics, schemas, coerce_types, prefix) do
    Enum.reduce(schemas, {[], %{}}, fn {field, schema}, {errs, acc} ->
      validate_field(field, schema, metrics, coerce_types, prefix, {errs, acc})
    end)
  end

  defp validate_field(field, schema, metrics, coerce_types, prefix, {errs, acc}) do
    case Map.fetch(metrics, field) do
      :error ->
        handle_missing_field(field, schema, prefix, {errs, acc})

      {:ok, value} ->
        handle_existing_field(field, value, schema, coerce_types, prefix, {errs, acc})
    end
  end

  defp handle_missing_field(field, schema, prefix, {errs, acc}) do
    if Map.get(schema, :required, true) do
      {[error_entry(prefixed_field(field, prefix), :missing, nil) | errs], acc}
    else
      default = Map.get(schema, :default)
      updated_acc = if is_nil(default), do: acc, else: Map.put(acc, field, default)
      {errs, updated_acc}
    end
  end

  defp handle_existing_field(field, value, schema, coerce_types, prefix, {errs, acc}) do
    {field_errors, validated_value} =
      validate_value(field, value, schema, coerce_types, prefix)

    {errs ++ field_errors, Map.put(acc, field, validated_value)}
  end

  defp validate_value(field, value, %{type: :float} = schema, coerce_types, prefix) do
    case coerce_number(value, :float, coerce_types) do
      {:ok, number} ->
        {range_errors(field, number, schema, prefix), number}

      :error ->
        {[error_entry(prefixed_field(field, prefix), :type_error, value)], value}
    end
  end

  defp validate_value(field, value, %{type: :number} = schema, coerce_types, prefix) do
    case coerce_number(value, :number, coerce_types) do
      {:ok, number} ->
        {range_errors(field, number, schema, prefix), number}

      :error ->
        {[error_entry(prefixed_field(field, prefix), :type_error, value)], value}
    end
  end

  defp validate_value(field, value, %{type: :map} = schema, coerce_types, prefix) do
    if is_map(value) do
      validate_metrics(
        value,
        Map.get(schema, :schema, %{}),
        coerce_types,
        prefixed_field(field, prefix)
      )
    else
      {[error_entry(prefixed_field(field, prefix), :type_error, value)], value}
    end
  end

  defp coerce_number(value, :float, true) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> {:ok, float}
      _ -> :error
    end
  end

  defp coerce_number(value, :number, true) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} ->
        {:ok, int}

      _ ->
        case Float.parse(value) do
          {float, _} -> {:ok, float}
          _ -> :error
        end
    end
  end

  defp coerce_number(value, _, _) when is_number(value), do: {:ok, value}
  defp coerce_number(_value, _type, _coerce), do: :error

  defp range_errors(field, value, schema, prefix) do
    errors = []

    errors =
      case Map.get(schema, :min) do
        nil ->
          errors

        min when value < min ->
          [error_entry(prefixed_field(field, prefix), :below_min, value) | errors]

        _ ->
          errors
      end

    errors =
      case Map.get(schema, :max) do
        nil ->
          errors

        max when value > max ->
          [error_entry(prefixed_field(field, prefix), :above_max, value) | errors]

        _ ->
          errors
      end

    Enum.reverse(errors)
  end

  defp prefixed_field(field, nil), do: field
  defp prefixed_field(field, prefix) when is_atom(prefix), do: "#{prefix}.#{field}"
  defp prefixed_field(field, prefix) when is_binary(prefix), do: "#{prefix}.#{field}"

  defp error_entry(field, reason, value) do
    %{field: field, error: reason, value: value}
  end
end
