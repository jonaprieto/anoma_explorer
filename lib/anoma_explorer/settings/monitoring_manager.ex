defmodule AnomaExplorer.Settings.MonitoringManager do
  @moduledoc """
  GenServer that manages automatic monitoring of contract addresses.

  Subscribes to Settings PubSub and:
  - On startup: spawns ingestion workers for all active addresses
  - On address activated: starts monitoring
  - On address deactivated: cancels pending Oban jobs

  This provides automatic lifecycle management for contract monitoring.
  """
  use GenServer

  require Logger

  alias AnomaExplorer.Settings

  @check_interval :timer.seconds(30)

  # ============================================
  # Client API
  # ============================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers monitoring for a specific contract address.
  """
  def start_monitoring(address) do
    GenServer.cast(__MODULE__, {:start_monitoring, address})
  end

  @doc """
  Manually stops monitoring for a specific contract address.
  """
  def stop_monitoring(address) do
    GenServer.cast(__MODULE__, {:stop_monitoring, address})
  end

  @doc """
  Gets the current monitoring status.
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

    # Schedule initial monitoring setup after a short delay
    # This allows other services to start first
    Process.send_after(self(), :init_monitoring, :timer.seconds(2))

    state = %{
      monitored: MapSet.new(),
      started_at: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl true
  def handle_info(:init_monitoring, state) do
    Logger.info("[MonitoringManager] Initializing monitoring for active contracts")

    new_state = start_all_active_monitoring(state)

    # Schedule periodic health check
    schedule_health_check()

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Verify all active addresses are being monitored
    active_addresses = Settings.list_active_addresses()
    active_keys = MapSet.new(active_addresses, &address_key/1)

    # Find addresses that should be monitored but aren't
    missing = MapSet.difference(active_keys, state.monitored)

    new_state =
      if MapSet.size(missing) > 0 do
        Logger.info("[MonitoringManager] Health check found #{MapSet.size(missing)} missing monitors")

        Enum.reduce(missing, state, fn key, acc ->
          # Find the address and start monitoring
          case find_address_by_key(active_addresses, key) do
            nil -> acc
            address -> do_start_monitoring(address, acc)
          end
        end)
      else
        state
      end

    schedule_health_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:settings_changed, {:address_created, address}}, state) do
    new_state =
      if address.active do
        Logger.info("[MonitoringManager] New active address created, starting monitoring")
        do_start_monitoring(address, state)
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
          # Address was activated
          Logger.info("[MonitoringManager] Address activated, starting monitoring")
          do_start_monitoring(address, state)

        not address.active and MapSet.member?(state.monitored, key) ->
          # Address was deactivated
          Logger.info("[MonitoringManager] Address deactivated, stopping monitoring")
          do_stop_monitoring(address, state)

        true ->
          # Active status unchanged, might be address update
          state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:settings_changed, {:address_deleted, address}}, state) do
    new_state =
      if MapSet.member?(state.monitored, address_key(address)) do
        Logger.info("[MonitoringManager] Address deleted, stopping monitoring")
        do_stop_monitoring(address, state)
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
  def handle_cast({:start_monitoring, address}, state) do
    {:noreply, do_start_monitoring(address, state)}
  end

  @impl true
  def handle_cast({:stop_monitoring, address}, state) do
    {:noreply, do_stop_monitoring(address, state)}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      monitored_count: MapSet.size(state.monitored),
      monitored_keys: MapSet.to_list(state.monitored),
      started_at: state.started_at
    }

    {:reply, status, state}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp start_all_active_monitoring(state) do
    active_addresses = Settings.list_active_addresses()

    Logger.info("[MonitoringManager] Found #{length(active_addresses)} active addresses to monitor")

    Enum.reduce(active_addresses, state, fn address, acc ->
      do_start_monitoring(address, acc)
    end)
  end

  defp do_start_monitoring(address, state) do
    key = address_key(address)

    if MapSet.member?(state.monitored, key) do
      # Already monitoring
      state
    else
      # Start monitoring - enqueue Oban job for ingestion
      case enqueue_ingestion_job(address) do
        {:ok, _job} ->
          Logger.debug("[MonitoringManager] Started monitoring #{inspect(key)}")
          %{state | monitored: MapSet.put(state.monitored, key)}

        {:error, reason} ->
          Logger.error("[MonitoringManager] Failed to start monitoring #{inspect(key)}: #{inspect(reason)}")
          state
      end
    end
  end

  defp do_stop_monitoring(address, state) do
    key = address_key(address)

    if MapSet.member?(state.monitored, key) do
      # Cancel any pending jobs for this address
      cancel_ingestion_jobs(address)

      Logger.debug("[MonitoringManager] Stopped monitoring #{inspect(key)}")
      %{state | monitored: MapSet.delete(state.monitored, key)}
    else
      state
    end
  end

  defp address_key(address) do
    {address.protocol_id, address.category, address.version, address.network}
  end

  defp find_address_by_key(addresses, key) do
    Enum.find(addresses, fn a -> address_key(a) == key end)
  end

  defp enqueue_ingestion_job(address) do
    # Check if Oban and the ingestion worker module exist
    # This allows the module to work even if ingestion isn't fully set up yet
    if Code.ensure_loaded?(Oban) and function_exported?(Oban, :insert, 1) do
      job_args = %{
        "protocol_id" => address.protocol_id,
        "category" => address.category,
        "version" => address.version,
        "network" => address.network,
        "address" => address.address,
        "type" => "initial_sync"
      }

      # Use a generic ingestion worker - can be customized based on category
      worker_module = get_worker_module(address.category)

      if worker_module && Code.ensure_loaded?(worker_module) do
        job_args
        |> worker_module.new()
        |> Oban.insert()
      else
        # Fallback: just log that we would start monitoring
        Logger.info("[MonitoringManager] Would start monitoring #{address.network}/#{address.address} (worker not configured)")
        {:ok, :no_worker}
      end
    else
      Logger.debug("[MonitoringManager] Oban not available, skipping job enqueue")
      {:ok, :oban_not_available}
    end
  end

  defp cancel_ingestion_jobs(address) do
    if Code.ensure_loaded?(Oban) and function_exported?(Oban, :cancel_all_jobs, 1) do
      # Cancel jobs matching this address
      import Ecto.Query

      query =
        from j in Oban.Job,
          where: j.state in ["available", "scheduled", "retryable"],
          where:
            fragment("?->>'network' = ?", j.args, ^address.network) and
              fragment("?->>'address' = ?", j.args, ^address.address)

      case Oban.cancel_all_jobs(query) do
        {:ok, count} when count > 0 ->
          Logger.info("[MonitoringManager] Cancelled #{count} pending jobs for #{address.network}/#{address.address}")

        _ ->
          :ok
      end
    end
  end

  defp get_worker_module(category) do
    case category do
      "protocol_adapter" -> AnomaExplorer.Workers.ProtocolAdapterWorker
      "erc20_forwarder" -> AnomaExplorer.Workers.Erc20ForwarderWorker
      _ -> nil
    end
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @check_interval)
  end
end
