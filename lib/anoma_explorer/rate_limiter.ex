defmodule AnomaExplorer.RateLimiter do
  @moduledoc """
  Simple rate limiter using a token bucket algorithm.

  Tracks request counts per second and blocks if limit is exceeded.
  Uses ETS for fast concurrent access.
  """
  use GenServer

  @table_name :rate_limiter
  @default_max_requests 5

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Attempts to acquire a rate limit token.

  Returns :ok if allowed, or {:error, :rate_limited} if limit exceeded.
  """
  @spec acquire(String.t()) :: :ok | {:error, :rate_limited}
  def acquire(key \\ "default") do
    max_requests =
      Application.get_env(:anoma_explorer, :max_req_per_second, @default_max_requests)

    now = System.system_time(:second)

    case :ets.lookup(@table_name, key) do
      [{^key, count, timestamp}] when timestamp == now and count >= max_requests ->
        {:error, :rate_limited}

      [{^key, count, timestamp}] when timestamp == now ->
        :ets.insert(@table_name, {key, count + 1, timestamp})
        :ok

      _ ->
        :ets.insert(@table_name, {key, 1, now})
        :ok
    end
  end

  @doc """
  Waits until a rate limit token is available, then acquires it.

  Returns :ok when acquired, or {:error, :timeout} if wait exceeds max_wait_ms.
  """
  @spec wait_and_acquire(String.t(), integer()) :: :ok | {:error, :timeout}
  def wait_and_acquire(key \\ "default", max_wait_ms \\ 5000) do
    deadline = System.monotonic_time(:millisecond) + max_wait_ms
    do_wait_and_acquire(key, deadline)
  end

  defp do_wait_and_acquire(key, deadline) do
    case acquire(key) do
      :ok ->
        :ok

      {:error, :rate_limited} ->
        now = System.monotonic_time(:millisecond)

        if now >= deadline do
          {:error, :timeout}
        else
          # Wait until next second boundary
          Process.sleep(100)
          do_wait_and_acquire(key, deadline)
        end
    end
  end

  @doc """
  Gets current rate limit status for a key.
  """
  @spec status(String.t()) :: {integer(), integer()}
  def status(key \\ "default") do
    max_requests =
      Application.get_env(:anoma_explorer, :max_req_per_second, @default_max_requests)

    now = System.system_time(:second)

    case :ets.lookup(@table_name, key) do
      [{^key, count, timestamp}] when timestamp == now ->
        {count, max_requests}

      _ ->
        {0, max_requests}
    end
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :public, :set])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
