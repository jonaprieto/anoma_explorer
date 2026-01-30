defmodule AnomaExplorer.Settings.Cache do
  @moduledoc """
  ETS-based cache for contract addresses, app settings, and networks.

  Provides fast concurrent reads for address, setting, and network lookups.
  The GenServer owns the ETS table and handles cache population.

  Cache key structures:
  - Contract addresses: {protocol_id, category, version, network} -> address
  - Protocol names: {:protocol_name, name} -> protocol_id
  - App settings: {:app_setting, key} -> value
  - Networks: {:network_chain_id, chain_id} -> network_map
  """
  use GenServer

  require Logger

  alias AnomaExplorer.Settings.ContractAddress
  alias AnomaExplorer.Settings.AppSetting
  alias AnomaExplorer.Settings.Network

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

  # ============================================
  # App Settings Cache
  # ============================================

  @doc """
  Gets an app setting value from cache.
  Returns {:ok, value} or :not_found.
  """
  @spec get_app_setting(String.t()) :: {:ok, String.t()} | :not_found
  def get_app_setting(key) do
    case :ets.lookup(@table_name, {:app_setting, key}) do
      [{_, value}] -> {:ok, value}
      [] -> :not_found
    end
  end

  @doc """
  Puts an app setting value into the cache.
  """
  @spec put_app_setting(String.t(), String.t()) :: :ok
  def put_app_setting(key, value) do
    :ets.insert(@table_name, {{:app_setting, key}, value})
    :ok
  end

  @doc """
  Deletes an app setting from the cache.
  """
  @spec delete_app_setting(String.t()) :: :ok
  def delete_app_setting(key) do
    :ets.delete(@table_name, {:app_setting, key})
    :ok
  end

  # ============================================
  # Network Cache
  # ============================================

  @doc """
  Gets a network by chain_id from cache.
  Returns {:ok, network_map} or :not_found.
  """
  @spec get_network_by_chain_id(integer()) :: {:ok, map()} | :not_found
  def get_network_by_chain_id(chain_id) do
    case :ets.lookup(@table_name, {:network_chain_id, chain_id}) do
      [{_, network}] -> {:ok, network}
      [] -> :not_found
    end
  end

  @doc """
  Puts a network into the cache, indexed by chain_id.
  Only caches networks that have a chain_id.
  """
  @spec put_network(Network.t()) :: :ok
  def put_network(%Network{chain_id: nil}), do: :ok

  def put_network(%Network{} = network) do
    network_map = %{
      id: network.id,
      name: network.name,
      display_name: network.display_name,
      chain_id: network.chain_id,
      explorer_url: network.explorer_url,
      rpc_url: network.rpc_url,
      is_testnet: network.is_testnet,
      active: network.active
    }

    :ets.insert(@table_name, {{:network_chain_id, network.chain_id}, network_map})
    :ok
  end

  @doc """
  Deletes a network from cache by chain_id.
  """
  @spec delete_network(integer() | nil) :: :ok
  def delete_network(nil), do: :ok

  def delete_network(chain_id) do
    :ets.delete(@table_name, {:network_chain_id, chain_id})
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
          addresses: counts.addresses,
          app_settings: counts.app_settings,
          networks: counts.networks
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
      app_settings_count = load_app_settings()
      network_count = load_networks()

      {:ok,
       %{
         protocols: protocol_count,
         addresses: address_count,
         app_settings: app_settings_count,
         networks: network_count
       }}
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

  defp load_app_settings do
    alias AnomaExplorer.Repo

    settings = Repo.all(AppSetting)

    Enum.each(settings, fn setting ->
      put_app_setting(setting.key, setting.value)
    end)

    length(settings)
  end

  defp load_networks do
    alias AnomaExplorer.Repo
    import Ecto.Query

    networks =
      Network
      |> where([n], n.active == true and not is_nil(n.chain_id))
      |> Repo.all()

    Enum.each(networks, fn network ->
      put_network(network)
    end)

    length(networks)
  end
end
