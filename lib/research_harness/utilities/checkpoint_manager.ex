defmodule CrucibleHarness.Utilities.CheckpointManager do
  @moduledoc """
  Manages checkpoints to enable experiment resumption after failures.
  """

  @doc """
  Creates a checkpoint for the current experiment state.
  """
  def checkpoint(experiment_id, results) do
    checkpoint_data = %{
      experiment_id: experiment_id,
      timestamp: DateTime.utc_now(),
      completed_results: results,
      random_state: capture_random_state()
    }

    path = checkpoint_path(experiment_id)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(checkpoint_data))

    :ok
  end

  @doc """
  Restores an experiment from a checkpoint.
  """
  def restore(experiment_id) do
    path = checkpoint_path(experiment_id)

    if File.exists?(path) do
      data = File.read!(path) |> :erlang.binary_to_term()
      restore_random_state(data.random_state)
      {:ok, data}
    else
      {:error, :no_checkpoint}
    end
  end

  @doc """
  Lists all available checkpoints.
  """
  def list_checkpoints do
    checkpoint_dir = get_checkpoint_dir()

    if File.exists?(checkpoint_dir) do
      File.ls!(checkpoint_dir)
      |> Enum.filter(&String.ends_with?(&1, ".checkpoint"))
      |> Enum.map(&String.replace(&1, ".checkpoint", ""))
    else
      []
    end
  end

  @doc """
  Deletes a checkpoint.
  """
  def delete_checkpoint(experiment_id) do
    path = checkpoint_path(experiment_id)

    if File.exists?(path) do
      File.rm!(path)
      :ok
    else
      {:error, :not_found}
    end
  end

  # Private Functions

  defp checkpoint_path(experiment_id) do
    Path.join([get_checkpoint_dir(), "#{experiment_id}.checkpoint"])
  end

  defp get_checkpoint_dir do
    Application.get_env(:research_harness, :checkpoint_dir, "./checkpoints")
  end

  defp capture_random_state do
    :rand.export_seed()
  end

  defp restore_random_state(state) do
    :rand.seed(state)
  end
end
