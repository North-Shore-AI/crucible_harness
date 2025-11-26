defmodule CrucibleHarness.ValidationTest do
  use ExUnit.Case, async: true

  alias CrucibleHarness.Validation.{MetricValidator, Schema}

  describe "metric schema definition" do
    test "creates schema for float metric" do
      schema = Schema.float(min: 0.0, max: 1.0, required: true)

      assert schema.type == :float
      assert schema.min == 0.0
      assert schema.max == 1.0
      assert schema.required == true
    end

    test "creates schema for number metric" do
      schema = Schema.number(min: 0, unit: :milliseconds)

      assert schema.type == :number
      assert schema.min == 0
      assert schema.unit == :milliseconds
    end

    test "creates schema for map metric with nested schema" do
      schema =
        Schema.map(
          schema: %{
            value: Schema.number(min: 0),
            confidence: Schema.float(min: 0.0, max: 1.0)
          }
        )

      assert schema.type == :map
      assert is_map(schema.schema)
    end
  end

  describe "metric validation" do
    setup do
      schemas = %{
        accuracy: Schema.float(min: 0.0, max: 1.0, required: true),
        latency: Schema.number(min: 0, required: true),
        cost: Schema.float(min: 0.0, required: false, default: 0.0),
        custom: Schema.map(schema: %{value: Schema.number(min: 0)})
      }

      {:ok, schemas: schemas}
    end

    test "validates correct metrics", %{schemas: schemas} do
      result = %{
        accuracy: 0.85,
        latency: 123,
        cost: 0.01,
        custom: %{value: 42}
      }

      assert {:ok, ^result} = MetricValidator.validate(result, schemas)
    end

    test "detects missing required metric", %{schemas: schemas} do
      result = %{
        latency: 123,
        cost: 0.01
      }

      assert {:error, errors} = MetricValidator.validate(result, schemas)
      assert Enum.any?(errors, fn e -> e.field == :accuracy and e.error == :missing end)
    end

    test "allows missing optional metric and uses default", %{schemas: schemas} do
      result = %{
        accuracy: 0.85,
        latency: 123
      }

      assert {:ok, validated} = MetricValidator.validate(result, schemas)
      assert validated.cost == 0.0
    end

    test "detects type errors", %{schemas: schemas} do
      result = %{
        accuracy: "not a number",
        latency: 123,
        cost: 0.01
      }

      assert {:error, errors} = MetricValidator.validate(result, schemas)
      assert Enum.any?(errors, fn e -> e.field == :accuracy and e.error == :type_error end)
    end

    test "detects range violations (too low)", %{schemas: schemas} do
      result = %{
        accuracy: -0.5,
        latency: 123,
        cost: 0.01
      }

      assert {:error, errors} = MetricValidator.validate(result, schemas)

      assert Enum.any?(errors, fn e ->
               e.field == :accuracy and e.error == :below_min
             end)
    end

    test "detects range violations (too high)", %{schemas: schemas} do
      result = %{
        accuracy: 1.5,
        latency: 123,
        cost: 0.01
      }

      assert {:error, errors} = MetricValidator.validate(result, schemas)

      assert Enum.any?(errors, fn e ->
               e.field == :accuracy and e.error == :above_max
             end)
    end

    test "coerces string to float when enabled", %{schemas: schemas} do
      result = %{
        accuracy: "0.85",
        latency: "123",
        cost: 0.01
      }

      config = %{coerce_types: true}

      assert {:ok, validated} = MetricValidator.validate(result, schemas, config)
      assert validated.accuracy == 0.85
      assert validated.latency == 123
    end

    test "does not coerce when disabled", %{schemas: schemas} do
      result = %{
        accuracy: "0.85",
        latency: 123,
        cost: 0.01
      }

      config = %{coerce_types: false}

      assert {:error, errors} = MetricValidator.validate(result, schemas, config)
      assert Enum.any?(errors, fn e -> e.field == :accuracy and e.error == :type_error end)
    end

    test "validates nested map schemas", %{schemas: schemas} do
      result = %{
        accuracy: 0.85,
        latency: 123,
        cost: 0.01,
        custom: %{value: 42}
      }

      assert {:ok, ^result} = MetricValidator.validate(result, schemas)
    end

    test "detects errors in nested maps", %{schemas: schemas} do
      result = %{
        accuracy: 0.85,
        latency: 123,
        cost: 0.01,
        custom: %{value: -10}
      }

      assert {:error, errors} = MetricValidator.validate(result, schemas)

      assert Enum.any?(errors, fn e ->
               e.field == "custom.value" and e.error == :below_min
             end)
    end

    test "validates multiple errors at once", %{schemas: schemas} do
      result = %{
        accuracy: 1.5,
        # Above max
        latency: -100,
        # Below min
        cost: "invalid"
        # Type error
      }

      assert {:error, errors} = MetricValidator.validate(result, schemas)
      assert length(errors) >= 3
    end
  end

  describe "validation actions" do
    test "log_and_continue returns warning" do
      config = %{on_invalid: :log_and_continue}
      errors = [%{field: :accuracy, error: :type_error, value: "invalid"}]

      assert {:warning, ^errors} = MetricValidator.handle_validation_error(errors, config)
    end

    test "log_and_retry returns retry signal" do
      config = %{on_invalid: :log_and_retry}
      errors = [%{field: :accuracy, error: :type_error, value: "invalid"}]

      assert {:retry, ^errors} = MetricValidator.handle_validation_error(errors, config)
    end

    test "abort returns error" do
      config = %{on_invalid: :abort}
      errors = [%{field: :accuracy, error: :type_error, value: "invalid"}]

      assert {:error, ^errors} = MetricValidator.handle_validation_error(errors, config)
    end
  end

  describe "schema helpers" do
    test "percentage schema is 0-100 float" do
      schema = Schema.percentage()

      assert schema.type == :float
      assert schema.min == 0.0
      assert schema.max == 100.0
    end

    test "probability schema is 0-1 float" do
      schema = Schema.probability()

      assert schema.type == :float
      assert schema.min == 0.0
      assert schema.max == 1.0
    end

    test "positive_number schema has min 0" do
      schema = Schema.positive_number()

      assert schema.type == :number
      assert schema.min == 0
    end

    test "duration_ms schema is positive number with unit" do
      schema = Schema.duration_ms()

      assert schema.type == :number
      assert schema.min == 0
      assert schema.unit == :milliseconds
    end
  end
end
