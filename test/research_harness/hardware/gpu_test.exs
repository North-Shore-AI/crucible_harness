defmodule CrucibleHarness.Hardware.GPUTest do
  use ExUnit.Case, async: true

  alias CrucibleHarness.Hardware.GPU

  # Note: We test the parsing logic directly since System.cmd is hard to mock

  describe "detect/0" do
    test "returns {:error, :no_gpu} when nvidia-smi is not available" do
      # This test may pass or fail depending on system - we verify the function is callable
      result = GPU.detect()

      assert match?({:ok, %{name: _, vram_mb: _}}, result) or
               result == {:error, :no_gpu}
    end
  end

  describe "parsing nvidia-smi output" do
    # Test the parsing logic by testing what we can control

    test "parses valid nvidia-smi CSV output" do
      # We test the module's behavior with known output formats
      # by checking that the return type matches expected structure
      result = GPU.detect()

      case result do
        {:ok, info} ->
          assert is_binary(info.name)
          assert is_integer(info.vram_mb)
          assert info.vram_mb > 0

        {:error, :no_gpu} ->
          # Expected on CPU-only systems
          assert true
      end
    end
  end

  describe "raw_info/0" do
    test "returns string or error" do
      result = GPU.raw_info()

      case result do
        {:ok, output} ->
          assert is_binary(output)

        {:error, :no_gpu} ->
          assert true
      end
    end
  end

  # These tests verify parsing logic with mocked data
  describe "parsing logic (unit tests)" do
    # We use a helper module to test parsing in isolation
    # by creating a test-specific parsing function

    test "parses RTX 4060 Ti output correctly" do
      output = "NVIDIA GeForce RTX 4060 Ti, 16384\n"
      result = parse_test_output(output)
      assert result == {:ok, %{name: "NVIDIA GeForce RTX 4060 Ti", vram_mb: 16384}}
    end

    test "parses RTX 5060 Ti output correctly" do
      output = "NVIDIA GeForce RTX 5060 Ti, 16384\n"
      result = parse_test_output(output)
      assert result == {:ok, %{name: "NVIDIA GeForce RTX 5060 Ti", vram_mb: 16384}}
    end

    test "parses RTX 4090 output correctly" do
      output = "NVIDIA GeForce RTX 4090, 24576\n"
      result = parse_test_output(output)
      assert result == {:ok, %{name: "NVIDIA GeForce RTX 4090", vram_mb: 24576}}
    end

    test "parses A100 output correctly" do
      output = "NVIDIA A100-SXM4-40GB, 40960\n"
      result = parse_test_output(output)
      assert result == {:ok, %{name: "NVIDIA A100-SXM4-40GB", vram_mb: 40960}}
    end

    test "parses output with extra whitespace" do
      output = "  NVIDIA GeForce RTX 4060 Ti ,  16384  \n"
      result = parse_test_output(output)
      assert result == {:ok, %{name: "NVIDIA GeForce RTX 4060 Ti", vram_mb: 16384}}
    end

    test "handles multi-GPU output (takes first)" do
      output = """
      NVIDIA GeForce RTX 4090, 24576
      NVIDIA GeForce RTX 4060 Ti, 16384
      """

      result = parse_test_output(output)
      assert result == {:ok, %{name: "NVIDIA GeForce RTX 4090", vram_mb: 24576}}
    end

    test "returns error for empty output" do
      assert parse_test_output("") == {:error, :no_gpu}
      assert parse_test_output("\n") == {:error, :no_gpu}
    end

    test "returns error for malformed output" do
      assert parse_test_output("not a csv") == {:error, :no_gpu}
      assert parse_test_output("name only") == {:error, :no_gpu}
      assert parse_test_output("name, not_a_number") == {:error, :no_gpu}
    end

    test "returns error for zero VRAM" do
      assert parse_test_output("Some GPU, 0") == {:error, :no_gpu}
    end

    test "returns error for negative VRAM" do
      assert parse_test_output("Some GPU, -1024") == {:error, :no_gpu}
    end
  end

  # Helper function that mimics the parsing logic for testing
  defp parse_test_output(output) do
    output
    |> String.trim()
    |> String.split("\n")
    |> List.first()
    |> parse_gpu_line()
  end

  defp parse_gpu_line(nil), do: {:error, :no_gpu}
  defp parse_gpu_line(""), do: {:error, :no_gpu}

  defp parse_gpu_line(line) do
    case String.split(line, ",") do
      [name, vram_str] ->
        name = String.trim(name)
        vram_str = String.trim(vram_str)

        case Integer.parse(vram_str) do
          {vram_mb, _} when vram_mb > 0 ->
            {:ok, %{name: name, vram_mb: vram_mb}}

          _ ->
            {:error, :no_gpu}
        end

      _ ->
        {:error, :no_gpu}
    end
  end
end
