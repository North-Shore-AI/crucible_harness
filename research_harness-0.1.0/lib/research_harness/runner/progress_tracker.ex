defmodule ResearchHarness.Runner.ProgressTracker do
  @moduledoc """
  Tracks and reports progress for running experiments.
  """

  use GenServer

  defstruct [
    :experiment_id,
    :total_tasks,
    :completed_tasks,
    :failed_tasks,
    :start_time,
    :estimated_completion,
    :subscribers
  ]

  # Client API

  def start_link(experiment_id, total_tasks) do
    GenServer.start_link(__MODULE__, {experiment_id, total_tasks}, name: __MODULE__)
  end

  def update(num_completed) do
    GenServer.cast(__MODULE__, {:update, num_completed})
  end

  def subscribe(pid) do
    GenServer.call(__MODULE__, {:subscribe, pid})
  end

  def get_progress do
    GenServer.call(__MODULE__, :get_progress)
  end

  # Server Callbacks

  @impl true
  def init({experiment_id, total_tasks}) do
    state = %__MODULE__{
      experiment_id: experiment_id,
      total_tasks: total_tasks,
      completed_tasks: 0,
      failed_tasks: 0,
      start_time: DateTime.utc_now(),
      estimated_completion: nil,
      subscribers: []
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:update, num_completed}, state) do
    new_completed = state.completed_tasks + num_completed
    progress_pct = new_completed / state.total_tasks * 100

    # Calculate estimated completion time
    elapsed = DateTime.diff(DateTime.utc_now(), state.start_time, :second)
    rate = if elapsed > 0, do: new_completed / elapsed, else: 0
    remaining = state.total_tasks - new_completed
    eta_seconds = if rate > 0, do: remaining / rate, else: nil

    estimated_completion =
      if eta_seconds do
        DateTime.add(DateTime.utc_now(), round(eta_seconds), :second)
      end

    # Create progress update
    progress_update = %{
      experiment_id: state.experiment_id,
      completed: new_completed,
      total: state.total_tasks,
      progress_pct: progress_pct,
      estimated_completion: estimated_completion
    }

    # Notify subscribers
    Enum.each(state.subscribers, fn pid ->
      send(pid, {:progress_update, progress_update})
    end)

    # Log progress
    log_progress(progress_pct, new_completed, state.total_tasks, estimated_completion)

    new_state = %{
      state
      | completed_tasks: new_completed,
        estimated_completion: estimated_completion
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: [pid | state.subscribers]}}
  end

  @impl true
  def handle_call(:get_progress, _from, state) do
    progress = %{
      experiment_id: state.experiment_id,
      completed: state.completed_tasks,
      total: state.total_tasks,
      progress_pct: state.completed_tasks / state.total_tasks * 100,
      estimated_completion: state.estimated_completion
    }

    {:reply, progress, state}
  end

  # Private Functions

  defp log_progress(progress_pct, completed, total, eta) do
    eta_str = format_eta(eta)

    IO.write(
      "\rProgress: #{Float.round(progress_pct, 2)}% (#{completed}/#{total}) ETA: #{eta_str}"
    )
  end

  defp format_eta(nil), do: "calculating..."

  defp format_eta(datetime) do
    diff = DateTime.diff(datetime, DateTime.utc_now(), :second)
    hours = div(diff, 3600)
    minutes = div(rem(diff, 3600), 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}m"
      minutes > 0 -> "#{minutes}m"
      true -> "< 1m"
    end
  end
end
