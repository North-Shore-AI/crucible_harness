defmodule CrucibleHarness.Hardware.Profile do
  @moduledoc """
  Hardware profile classification for experiment tuning and reporting.

  Classifies the machine into stable profiles based on detected GPU/VRAM,
  providing safe concurrency and timeout recommendations.

  ## Profiles

  - `:edge_minimal` - 8GB VRAM (e.g., RTX 3060, 4060 8GB)
  - `:edge_standard` - 16GB VRAM (e.g., RTX 4060 Ti 16GB, 5060 Ti 16GB)
  - `:server_standard` - 24GB VRAM (e.g., RTX 3090, 4090)
  - `:server_large` - 40GB+ VRAM (e.g., A100, H100)
  - `:cpu_only` - No GPU detected

  ## Example

      iex> CrucibleHarness.Hardware.Profile.detect()
      :edge_standard

      iex> CrucibleHarness.Hardware.Profile.timeout_multiplier(:edge_standard)
      1.5

      iex> CrucibleHarness.Hardware.Profile.max_concurrency(:edge_standard)
      2
  """

  alias CrucibleHarness.Hardware.GPU

  @type profile ::
          :edge_minimal
          | :edge_standard
          | :server_standard
          | :server_large
          | :cpu_only

  @type profile_info :: %{
          profile: profile(),
          gpu: GPU.gpu_info() | nil,
          timeout_multiplier: float(),
          max_concurrency: pos_integer()
        }

  # VRAM thresholds in MB for profile classification
  @edge_minimal_threshold 8 * 1024
  @edge_standard_threshold 16 * 1024
  @server_standard_threshold 24 * 1024
  @server_large_threshold 40 * 1024

  @doc """
  Detects the hardware profile based on GPU/VRAM availability.

  Returns a profile atom suitable for experiment metadata.

  ## Examples

      :edge_standard = Profile.detect()
      :cpu_only = Profile.detect()
  """
  @spec detect() :: profile()
  def detect do
    case GPU.detect() do
      {:ok, %{vram_mb: vram_mb}} -> classify_by_vram(vram_mb)
      {:error, :no_gpu} -> :cpu_only
    end
  end

  @doc """
  Detects the hardware profile with full details.

  Returns a map containing the profile, raw GPU info (if present),
  and computed tuning parameters.

  ## Examples

      %{
        profile: :edge_standard,
        gpu: %{name: "NVIDIA GeForce RTX 4060 Ti", vram_mb: 16384},
        timeout_multiplier: 1.5,
        max_concurrency: 2
      } = Profile.detect_with_info()
  """
  @spec detect_with_info() :: profile_info()
  def detect_with_info do
    gpu_result = GPU.detect()
    profile = profile_from_gpu_result(gpu_result)

    %{
      profile: profile,
      gpu: gpu_info_or_nil(gpu_result),
      timeout_multiplier: timeout_multiplier(profile),
      max_concurrency: max_concurrency(profile)
    }
  end

  @doc """
  Returns the timeout multiplier for a given profile.

  Edge hardware gets longer timeouts due to lower compute capacity.
  Server hardware uses shorter multipliers.

  ## Examples

      2.0 = Profile.timeout_multiplier(:edge_minimal)
      1.5 = Profile.timeout_multiplier(:edge_standard)
      1.0 = Profile.timeout_multiplier(:server_standard)
  """
  @spec timeout_multiplier(profile()) :: float()
  def timeout_multiplier(:cpu_only), do: 3.0
  def timeout_multiplier(:edge_minimal), do: 2.0
  def timeout_multiplier(:edge_standard), do: 1.5
  def timeout_multiplier(:server_standard), do: 1.0
  def timeout_multiplier(:server_large), do: 0.8

  @doc """
  Returns the recommended max concurrency for a given profile.

  Lower VRAM systems should run fewer concurrent GPU tasks
  to avoid OOM errors.

  ## Examples

      1 = Profile.max_concurrency(:edge_minimal)
      2 = Profile.max_concurrency(:edge_standard)
      4 = Profile.max_concurrency(:server_standard)
  """
  @spec max_concurrency(profile()) :: pos_integer()
  def max_concurrency(:cpu_only), do: System.schedulers_online()
  def max_concurrency(:edge_minimal), do: 1
  def max_concurrency(:edge_standard), do: 2
  def max_concurrency(:server_standard), do: 4
  def max_concurrency(:server_large), do: 8

  @doc """
  Returns all known profiles in order of capability.

  ## Examples

      [:cpu_only, :edge_minimal, :edge_standard, :server_standard, :server_large] =
        Profile.all_profiles()
  """
  @spec all_profiles() :: [profile()]
  def all_profiles do
    [:cpu_only, :edge_minimal, :edge_standard, :server_standard, :server_large]
  end

  @doc """
  Returns a human-readable description of a profile.

  ## Examples

      "Edge Standard (16GB VRAM)" = Profile.describe(:edge_standard)
  """
  @spec describe(profile()) :: String.t()
  def describe(:cpu_only), do: "CPU Only (no GPU)"
  def describe(:edge_minimal), do: "Edge Minimal (8GB VRAM)"
  def describe(:edge_standard), do: "Edge Standard (16GB VRAM)"
  def describe(:server_standard), do: "Server Standard (24GB VRAM)"
  def describe(:server_large), do: "Server Large (40GB+ VRAM)"

  # Private helpers

  defp profile_from_gpu_result({:ok, %{vram_mb: vram_mb}}), do: classify_by_vram(vram_mb)
  defp profile_from_gpu_result({:error, :no_gpu}), do: :cpu_only

  defp gpu_info_or_nil({:ok, info}), do: info
  defp gpu_info_or_nil({:error, _}), do: nil

  defp classify_by_vram(vram_mb) when vram_mb >= @server_large_threshold, do: :server_large
  defp classify_by_vram(vram_mb) when vram_mb >= @server_standard_threshold, do: :server_standard
  defp classify_by_vram(vram_mb) when vram_mb >= @edge_standard_threshold, do: :edge_standard
  defp classify_by_vram(vram_mb) when vram_mb >= @edge_minimal_threshold, do: :edge_minimal
  defp classify_by_vram(_vram_mb), do: :edge_minimal
end
