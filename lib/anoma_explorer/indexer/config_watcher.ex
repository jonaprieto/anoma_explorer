defmodule AnomaExplorer.Indexer.ConfigWatcher do
  @moduledoc """
  GenServer that watches for settings changes and regenerates indexer config.

  Subscribes to Settings PubSub and regenerates config.yaml when:
  - Contract addresses are created, updated, or deleted
  - Networks are created, updated, or deleted

  Also generates initial config on startup after a short delay.
  """
  use GenServer

  require Logger

  alias AnomaExplorer.Settings
  alias AnomaExplorer.Indexer.ConfigGenerator

  @init_delay :timer.seconds(5)

  # ============================================
  # Client API
  # ============================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers config regeneration.
  """
  def regenerate do
    GenServer.cast(__MODULE__, :regenerate)
  end

  @doc """
  Gets the current watcher status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # ============================================
  # Server Callbacks
  # ============================================

  @impl true
  def init(_opts) do
    # Subscribe to settings changes
    Settings.subscribe()

    # Schedule initial config generation after delay
    Process.send_after(self(), :generate_initial_config, @init_delay)

    state = %{
      last_generated: nil,
      generation_count: 0,
      errors: []
    }

    Logger.info("[ConfigWatcher] Started, will generate initial config in #{div(@init_delay, 1000)}s")

    {:ok, state}
  end

  @impl true
  def handle_info(:generate_initial_config, state) do
    Logger.info("[ConfigWatcher] Generating initial config.yaml")
    new_state = do_generate(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:settings_changed, event}, state) do
    if should_regenerate?(event) do
      Logger.info("[ConfigWatcher] Settings changed (#{event_type(event)}), regenerating config.yaml")
      new_state = do_generate(state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:regenerate, state) do
    Logger.info("[ConfigWatcher] Manual regeneration requested")
    new_state = do_generate(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      last_generated: state.last_generated,
      generation_count: state.generation_count,
      config_path: ConfigGenerator.config_path(),
      recent_errors: Enum.take(state.errors, 5)
    }

    {:reply, status, state}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp do_generate(state) do
    case ConfigGenerator.generate() do
      :ok ->
        %{state |
          last_generated: DateTime.utc_now(),
          generation_count: state.generation_count + 1
        }

      {:error, reason} ->
        error = %{
          timestamp: DateTime.utc_now(),
          reason: inspect(reason)
        }

        %{state | errors: [error | state.errors] |> Enum.take(10)}
    end
  end

  defp should_regenerate?(event) do
    case event do
      {:address_created, _} -> true
      {:address_updated, _} -> true
      {:address_deleted, _} -> true
      {:network_created, _} -> true
      {:network_updated, _} -> true
      {:network_deleted, _} -> true
      _ -> false
    end
  end

  defp event_type({type, _}), do: type
  defp event_type(other), do: other
end
