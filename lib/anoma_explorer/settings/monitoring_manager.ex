defmodule AnomaExplorer.Settings.MonitoringManager do
  @moduledoc """
  GenServer that tracks active contract addresses.

  Subscribes to Settings PubSub and maintains a set of active addresses.
  This provides a foundation for future indexing integrations (e.g., envio hyperindex).
  """
  use GenServer

  require Logger

  alias AnomaExplorer.Settings

  # ============================================
  # Client API
  # ============================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current monitoring status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Gets the list of currently monitored address keys.
  """
  def monitored_addresses do
    GenServer.call(__MODULE__, :monitored_addresses)
  end

  # ============================================
  # Server Callbacks
  # ============================================

  @impl true
  def init(_opts) do
    # Subscribe to settings changes
    Settings.subscribe()

    # Schedule initial setup after a short delay
    Process.send_after(self(), :init_monitoring, :timer.seconds(2))

    state = %{
      monitored: MapSet.new(),
      started_at: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl true
  def handle_info(:init_monitoring, state) do
    Logger.info("[MonitoringManager] Initializing tracking for active contracts")

    active_addresses = Settings.list_active_addresses()
    monitored = MapSet.new(active_addresses, &address_key/1)

    Logger.info("[MonitoringManager] Tracking #{MapSet.size(monitored)} active addresses")

    {:noreply, %{state | monitored: monitored}}
  end

  @impl true
  def handle_info({:settings_changed, {:address_created, address}}, state) do
    new_state =
      if address.active do
        key = address_key(address)
        Logger.debug("[MonitoringManager] New active address: #{inspect(key)}")
        %{state | monitored: MapSet.put(state.monitored, key)}
      else
        state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:settings_changed, {:address_updated, address}}, state) do
    key = address_key(address)

    new_state =
      cond do
        address.active and not MapSet.member?(state.monitored, key) ->
          Logger.debug("[MonitoringManager] Address activated: #{inspect(key)}")
          %{state | monitored: MapSet.put(state.monitored, key)}

        not address.active and MapSet.member?(state.monitored, key) ->
          Logger.debug("[MonitoringManager] Address deactivated: #{inspect(key)}")
          %{state | monitored: MapSet.delete(state.monitored, key)}

        true ->
          state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:settings_changed, {:address_deleted, address}}, state) do
    key = address_key(address)

    new_state =
      if MapSet.member?(state.monitored, key) do
        Logger.debug("[MonitoringManager] Address deleted: #{inspect(key)}")
        %{state | monitored: MapSet.delete(state.monitored, key)}
      else
        state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:settings_changed, _event}, state) do
    # Ignore other settings events (protocol changes, etc.)
    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      monitored_count: MapSet.size(state.monitored),
      started_at: state.started_at
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:monitored_addresses, _from, state) do
    {:reply, MapSet.to_list(state.monitored), state}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp address_key(address) do
    {address.protocol_id, address.category, address.version, address.network}
  end
end
