defmodule AnomaExplorer.Settings.Cache do
  @moduledoc """
  ETS-based cache for contract addresses.

  Provides fast concurrent reads for address lookups.
  The GenServer owns the ETS table and handles cache population.

  Cache key structure: {protocol_id, category, version, network} -> address
  """
  use GenServer

  require Logger

  alias AnomaExplorer.Settings.ContractAddress

  @table_name :contract_addresses_cache

  # ============================================
  # Client API
  # ============================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets an address from cache by protocol_id, category, version, and network.
  Returns {:ok, address} or :not_found.
  """
  @spec get(integer(), String.t(), String.t(), String.t()) :: {:ok, String.t()} | :not_found
  def get(protocol_id, category, version, network) do
    key = cache_key(protocol_id, category, version, network)

    case :ets.lookup(@table_name, key) do
      [{^key, address}] -> {:ok, address}
      [] -> :not_found
    end
  end

  @doc """
  Gets an address from cache by protocol name, category, version, and network.
  Returns {:ok, address} or :not_found.

  This is a convenience function that looks up the protocol_id first.
  """
  @spec get_by_protocol_name(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | :not_found
  def get_by_protocol_name(protocol_name, category, version, network) do
    # Use protocol name index for lookup
    case :ets.lookup(@table_name, {:protocol_name, protocol_name}) do
      [{_, protocol_id}] -> get(protocol_id, category, version, network)
      [] -> :not_found
    end
  end

  @doc """
  Puts a contract address into the cache.
  """
  @spec put(ContractAddress.t()) :: :ok
  def put(%ContractAddress{
        protocol_id: protocol_id,
        category: category,
        version: version,
        network: network,
        address: address,
        active: true
      }) do
    put_address(protocol_id, category, version, network, address)
  end

  def put(%ContractAddress{
        protocol_id: protocol_id,
        category: category,
        version: version,
        network: network,
        active: false
      }) do
    delete(protocol_id, category, version, network)
  end

  @doc """
  Puts an address directly into the cache.
  """
  @spec put_address(integer(), String.t(), String.t(), String.t(), String.t()) :: :ok
  def put_address(protocol_id, category, version, network, address) do
    key = cache_key(protocol_id, category, version, network)
    :ets.insert(@table_name, {key, address})
    :ok
  end

  @doc """
  Indexes a protocol name to its ID for fast lookups.
  """
  @spec index_protocol(String.t(), integer()) :: :ok
  def index_protocol(name, id) do
    :ets.insert(@table_name, {{:protocol_name, name}, id})
    :ok
  end

  @doc """
  Removes a protocol name index from the cache.
  """
  @spec delete_protocol_index(String.t()) :: :ok
  def delete_protocol_index(name) do
    :ets.delete(@table_name, {:protocol_name, name})
    :ok
  end

  @doc """
  Deletes an entry from cache.
  """
  @spec delete(integer(), String.t(), String.t(), String.t()) :: :ok
  def delete(protocol_id, category, version, network) do
    key = cache_key(protocol_id, category, version, network)
    :ets.delete(@table_name, key)
    :ok
  end

  @doc """
  Reloads all settings from database into cache.
  """
  @spec reload_all() :: :ok
  def reload_all do
    GenServer.call(__MODULE__, :reload_all)
  end

  @doc """
  Clears the entire cache.
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  @doc """
  Returns all cached addresses as a list.
  Useful for debugging.
  """
  @spec all() :: list()
  def all do
    :ets.tab2list(@table_name)
  end

  # ============================================
  # Server Callbacks
  # ============================================

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])

    # Load initial data from database
    case load_all_data() do
      {:ok, counts} ->
        Logger.info("Settings cache initialized",
          protocols: counts.protocols,
          addresses: counts.addresses
        )

      {:error, reason} ->
        Logger.error("Failed to initialize settings cache", reason: inspect(reason))
    end

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call(:reload_all, _from, state) do
    clear()
    load_all_data()
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp cache_key(protocol_id, category, version, network) do
    {protocol_id, category, version, network}
  end

  defp load_all_data do
    try do
      protocol_count = load_protocols()
      address_count = load_contract_addresses()
      {:ok, %{protocols: protocol_count, addresses: address_count}}
    rescue
      e -> {:error, e}
    end
  end

  defp load_protocols do
    alias AnomaExplorer.Repo
    alias AnomaExplorer.Settings.Protocol
    import Ecto.Query

    protocols =
      Protocol
      |> where([p], p.active == true)
      |> Repo.all()

    Enum.each(protocols, fn protocol ->
      index_protocol(protocol.name, protocol.id)
    end)

    length(protocols)
  end

  defp load_contract_addresses do
    alias AnomaExplorer.Repo
    import Ecto.Query

    addresses =
      ContractAddress
      |> where([c], c.active == true)
      |> Repo.all()

    Enum.each(addresses, fn address ->
      put_address(
        address.protocol_id,
        address.category,
        address.version,
        address.network,
        address.address
      )
    end)

    length(addresses)
  end
end
