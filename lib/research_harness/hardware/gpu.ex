defmodule CrucibleHarness.Hardware.GPU do
  @moduledoc """
  Best-effort GPU/VRAM detection for edge hardware profiling.

  Uses `nvidia-smi` when available to detect basic GPU capabilities.
  Gracefully degrades to `{:error, :no_gpu}` when unavailable.

  ## Examples

      iex> CrucibleHarness.Hardware.GPU.detect()
      {:ok, %{name: "NVIDIA GeForce RTX 4060 Ti", vram_mb: 16384}}

      iex> CrucibleHarness.Hardware.GPU.detect()
      {:error, :no_gpu}
  """

  @type gpu_info :: %{name: String.t(), vram_mb: non_neg_integer()}

  @doc """
  Detects the first available GPU and its VRAM capacity.

  Returns `{:ok, gpu_info}` with GPU name and VRAM in megabytes,
  or `{:error, :no_gpu}` when no GPU is detected or nvidia-smi is unavailable.

  ## Examples

      {:ok, %{name: "NVIDIA GeForce RTX 4060 Ti", vram_mb: 16384}} = GPU.detect()
      {:error, :no_gpu} = GPU.detect()
  """
  @spec detect() :: {:ok, gpu_info()} | {:error, :no_gpu}
  def detect do
    detect_with_nvidia_smi()
  end

  @doc """
  Returns raw nvidia-smi output for debugging/metadata purposes.

  Returns `{:ok, raw_output}` on success, or `{:error, :no_gpu}` when unavailable.
  """
  @spec raw_info() :: {:ok, String.t()} | {:error, :no_gpu}
  def raw_info do
    case run_nvidia_smi(["--query-gpu=name,memory.total,driver_version", "--format=csv,noheader"]) do
      {:ok, output} -> {:ok, String.trim(output)}
      {:error, _} -> {:error, :no_gpu}
    end
  end

  # Private implementation

  defp detect_with_nvidia_smi do
    args = ["--query-gpu=name,memory.total", "--format=csv,noheader,nounits"]

    case run_nvidia_smi(args) do
      {:ok, output} -> parse_nvidia_smi_output(output)
      {:error, _reason} -> {:error, :no_gpu}
    end
  end

  defp run_nvidia_smi(args) do
    try do
      case System.cmd("nvidia-smi", args, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {_output, _exit_code} -> {:error, :nvidia_smi_failed}
      end
    rescue
      # ErlangError when nvidia-smi is not found
      ErlangError -> {:error, :nvidia_smi_not_found}
    catch
      # Catch any other errors (e.g., :enoent on some systems)
      :error, :enoent -> {:error, :nvidia_smi_not_found}
    end
  end

  defp parse_nvidia_smi_output(output) do
    output
    |> String.trim()
    |> String.split("\n")
    |> List.first()
    |> parse_gpu_line()
  end

  defp parse_gpu_line(nil), do: {:error, :no_gpu}

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
