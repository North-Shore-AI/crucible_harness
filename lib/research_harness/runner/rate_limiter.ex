defmodule CrucibleHarness.Runner.RateLimiter do
  @moduledoc """
  Rate limiter using token bucket algorithm to prevent API overload.
  """

  use GenServer

  defstruct [
    # requests per second
    :rate,
    # maximum tokens in bucket
    :capacity,
    # current tokens
    :tokens,
    # last refill timestamp
    :last_refill,
    # queue of waiting processes
    :waiting
  ]

  # Client API

  def start_link(rate) do
    GenServer.start_link(__MODULE__, rate, name: __MODULE__)
  end

  @doc """
  Acquires a token before making a request. Blocks if no tokens available.
  """
  def acquire do
    GenServer.call(__MODULE__, :acquire, :infinity)
  end

  # Server Callbacks

  @impl true
  def init(rate) do
    state = %__MODULE__{
      rate: rate,
      # 10 seconds worth of tokens
      capacity: rate * 10,
      tokens: rate * 10,
      last_refill: System.monotonic_time(:millisecond),
      waiting: :queue.new()
    }

    # Schedule periodic refill
    schedule_refill()

    {:ok, state}
  end

  @impl true
  def handle_call(:acquire, from, state) do
    if state.tokens >= 1 do
      # Token available, grant immediately
      {:reply, :ok, %{state | tokens: state.tokens - 1}}
    else
      # No tokens, add to waiting queue
      new_waiting = :queue.in(from, state.waiting)
      {:noreply, %{state | waiting: new_waiting}}
    end
  end

  @impl true
  def handle_info(:refill, state) do
    # Refill tokens based on time elapsed
    now = System.monotonic_time(:millisecond)
    elapsed = now - state.last_refill

    new_tokens =
      min(
        state.capacity,
        state.tokens + elapsed * state.rate / 1000
      )

    # Process waiting requests
    new_state =
      %{state | tokens: new_tokens, last_refill: now}
      |> process_waiting()

    schedule_refill()
    {:noreply, new_state}
  end

  # Private Functions

  defp process_waiting(state) do
    case :queue.out(state.waiting) do
      {{:value, from}, new_waiting} when state.tokens >= 1 ->
        GenServer.reply(from, :ok)
        process_waiting(%{state | tokens: state.tokens - 1, waiting: new_waiting})

      _ ->
        state
    end
  end

  defp schedule_refill do
    # Refill every 100ms
    Process.send_after(self(), :refill, 100)
  end
end
