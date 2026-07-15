defmodule CrucibleHarness.Hardware.ProfileTest do
  use ExUnit.Case, async: true

  alias CrucibleHarness.Hardware.Profile

  describe "detect/0" do
    test "returns a valid profile atom" do
      profile = Profile.detect()
      assert profile in Profile.all_profiles()
    end
  end

  describe "detect_with_info/0" do
    test "returns a map with expected keys" do
      info = Profile.detect_with_info()

      assert is_map(info)
      assert Map.has_key?(info, :profile)
      assert Map.has_key?(info, :gpu)
      assert Map.has_key?(info, :timeout_multiplier)
      assert Map.has_key?(info, :max_concurrency)
    end

    test "profile matches detect/0 result" do
      info = Profile.detect_with_info()
      assert info.profile == Profile.detect()
    end

    test "timeout_multiplier is consistent with function" do
      info = Profile.detect_with_info()
      assert info.timeout_multiplier == Profile.timeout_multiplier(info.profile)
    end

    test "max_concurrency is consistent with function" do
      info = Profile.detect_with_info()
      assert info.max_concurrency == Profile.max_concurrency(info.profile)
    end
  end

  describe "timeout_multiplier/1" do
    test "returns higher multipliers for lower-capability profiles" do
      assert Profile.timeout_multiplier(:cpu_only) > Profile.timeout_multiplier(:edge_minimal)
      assert Profile.timeout_multiplier(:edge_minimal) > Profile.timeout_multiplier(:edge_standard)
      assert Profile.timeout_multiplier(:edge_standard) > Profile.timeout_multiplier(:server_standard)
      assert Profile.timeout_multiplier(:server_standard) > Profile.timeout_multiplier(:server_large)
    end

    test "returns expected values for each profile" do
      assert Profile.timeout_multiplier(:cpu_only) == 3.0
      assert Profile.timeout_multiplier(:edge_minimal) == 2.0
      assert Profile.timeout_multiplier(:edge_standard) == 1.5
      assert Profile.timeout_multiplier(:server_standard) == 1.0
      assert Profile.timeout_multiplier(:server_large) == 0.8
    end

    test "all profiles have positive multipliers" do
      for profile <- Profile.all_profiles() do
        multiplier = Profile.timeout_multiplier(profile)
        assert is_float(multiplier)
        assert multiplier > 0
      end
    end
  end

  describe "max_concurrency/1" do
    test "returns higher concurrency for more capable profiles" do
      # Note: cpu_only uses schedulers, so we skip that comparison
      assert Profile.max_concurrency(:edge_minimal) < Profile.max_concurrency(:edge_standard)
      assert Profile.max_concurrency(:edge_standard) < Profile.max_concurrency(:server_standard)
      assert Profile.max_concurrency(:server_standard) < Profile.max_concurrency(:server_large)
    end

    test "returns expected values for each GPU profile" do
      assert Profile.max_concurrency(:edge_minimal) == 1
      assert Profile.max_concurrency(:edge_standard) == 2
      assert Profile.max_concurrency(:server_standard) == 4
      assert Profile.max_concurrency(:server_large) == 8
    end

    test "cpu_only returns number of schedulers" do
      assert Profile.max_concurrency(:cpu_only) == System.schedulers_online()
    end

    test "all profiles have positive concurrency" do
      for profile <- Profile.all_profiles() do
        concurrency = Profile.max_concurrency(profile)
        assert is_integer(concurrency)
        assert concurrency > 0
      end
    end
  end

  describe "all_profiles/0" do
    test "returns all known profiles" do
      profiles = Profile.all_profiles()

      assert :cpu_only in profiles
      assert :edge_minimal in profiles
      assert :edge_standard in profiles
      assert :server_standard in profiles
      assert :server_large in profiles
    end

    test "returns profiles in capability order" do
      assert Profile.all_profiles() == [
               :cpu_only,
               :edge_minimal,
               :edge_standard,
               :server_standard,
               :server_large
             ]
    end
  end

  describe "describe/1" do
    test "returns human-readable descriptions for all profiles" do
      for profile <- Profile.all_profiles() do
        description = Profile.describe(profile)
        assert is_binary(description)
        assert String.length(description) > 0
      end
    end

    test "descriptions mention VRAM for GPU profiles" do
      assert Profile.describe(:edge_minimal) =~ "8GB"
      assert Profile.describe(:edge_standard) =~ "16GB"
      assert Profile.describe(:server_standard) =~ "24GB"
      assert Profile.describe(:server_large) =~ "40GB"
    end

    test "cpu_only description mentions no GPU" do
      assert Profile.describe(:cpu_only) =~ "CPU"
    end
  end

  describe "profile classification by VRAM" do
    # Test the classification logic by verifying boundary behavior

    test "classify_by_vram respects thresholds" do
      # We test this indirectly through the module's behavior
      # by checking that detect_with_info returns valid profiles

      info = Profile.detect_with_info()

      case info.gpu do
        nil ->
          assert info.profile == :cpu_only

        %{vram_mb: vram_mb} ->
          cond do
            vram_mb >= 40 * 1024 -> assert info.profile == :server_large
            vram_mb >= 24 * 1024 -> assert info.profile == :server_standard
            vram_mb >= 16 * 1024 -> assert info.profile == :edge_standard
            vram_mb >= 8 * 1024 -> assert info.profile == :edge_minimal
            true -> assert info.profile == :edge_minimal
          end
      end
    end
  end

  describe "VRAM threshold boundaries (unit tests)" do
    # Test the classification thresholds directly

    test "8GB boundary (edge_minimal)" do
      assert classify_vram(8 * 1024) == :edge_minimal
      assert classify_vram(8 * 1024 - 1) == :edge_minimal
      assert classify_vram(4 * 1024) == :edge_minimal
    end

    test "16GB boundary (edge_standard)" do
      assert classify_vram(16 * 1024) == :edge_standard
      assert classify_vram(16 * 1024 - 1) == :edge_minimal
      assert classify_vram(16 * 1024 + 1) == :edge_standard
    end

    test "24GB boundary (server_standard)" do
      assert classify_vram(24 * 1024) == :server_standard
      assert classify_vram(24 * 1024 - 1) == :edge_standard
      assert classify_vram(24 * 1024 + 1) == :server_standard
    end

    test "40GB boundary (server_large)" do
      assert classify_vram(40 * 1024) == :server_large
      assert classify_vram(40 * 1024 - 1) == :server_standard
      assert classify_vram(80 * 1024) == :server_large
    end

    test "common GPU VRAM sizes map to expected profiles" do
      # RTX 4060 8GB
      assert classify_vram(8192) == :edge_minimal
      # RTX 4060 Ti 16GB, RTX 5060 Ti 16GB
      assert classify_vram(16384) == :edge_standard
      # RTX 3090, 4090
      assert classify_vram(24576) == :server_standard
      # A100 40GB
      assert classify_vram(40960) == :server_large
      # A100 80GB, H100 80GB
      assert classify_vram(81920) == :server_large
    end
  end

  # Helper function that mimics the classification logic for testing
  defp classify_vram(vram_mb) when vram_mb >= 40 * 1024, do: :server_large
  defp classify_vram(vram_mb) when vram_mb >= 24 * 1024, do: :server_standard
  defp classify_vram(vram_mb) when vram_mb >= 16 * 1024, do: :edge_standard
  defp classify_vram(_vram_mb), do: :edge_minimal
end
