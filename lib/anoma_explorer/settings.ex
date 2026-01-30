defmodule AnomaExplorer.Settings do
  @moduledoc """
  Context module for managing protocols and contract addresses.

  Provides functions for CRUD operations and querying settings.
  Supports hierarchical structure: Protocol > Category > Version > Network.
  Settings are cached in ETS for fast reads.
  """
  import Ecto.Query

  alias AnomaExplorer.Repo
  alias AnomaExplorer.Settings.Protocol
  alias AnomaExplorer.Settings.ContractAddress
  alias AnomaExplorer.Settings.Network
  alias AnomaExplorer.Settings.AppSetting
  alias AnomaExplorer.Settings.Cache

  @pubsub AnomaExplorer.PubSub
  @topic "settings:changes"

  # ============================================
  # Protocol CRUD Operations
  # ============================================

  @doc """
  Creates a new protocol.
  """
  @spec create_protocol(map()) :: {:ok, Protocol.t()} | {:error, Ecto.Changeset.t()}
  def create_protocol(attrs) do
    %Protocol{}
    |> Protocol.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(fn p -> Cache.index_protocol(p.name, p.id) end)
    |> tap_ok(&broadcast_change({:protocol_created, &1}))
  end

  @doc """
  Updates an existing protocol.
  """
  @spec update_protocol(Protocol.t(), map()) ::
          {:ok, Protocol.t()} | {:error, Ecto.Changeset.t()}
  def update_protocol(%Protocol{} = protocol, attrs) do
    old_name = protocol.name

    protocol
    |> Protocol.changeset(attrs)
    |> Repo.update()
    |> tap_ok(fn p ->
      # If name changed, update cache index
      if p.name != old_name do
        Cache.index_protocol(p.name, p.id)
      end
    end)
    |> tap_ok(&broadcast_change({:protocol_updated, &1}))
  end

  @doc """
  Deletes a protocol.
  Only succeeds if protocol has no contract addresses.
  """
  @spec delete_protocol(Protocol.t()) ::
          {:ok, Protocol.t()} | {:error, Ecto.Changeset.t()}
  def delete_protocol(%Protocol{} = protocol) do
    Repo.delete(protocol)
    |> tap_ok(fn p -> Cache.delete_protocol_index(p.name) end)
    |> tap_ok(&broadcast_change({:protocol_deleted, &1}))
  end

  @doc """
  Gets a single protocol by ID.
  """
  @spec get_protocol(integer()) :: Protocol.t() | nil
  def get_protocol(id), do: Repo.get(Protocol, id)

  @doc """
  Gets a single protocol by ID, raising if not found.
  """
  @spec get_protocol!(integer()) :: Protocol.t()
  def get_protocol!(id), do: Repo.get!(Protocol, id)

  @doc """
  Gets a protocol by name.
  """
  @spec get_protocol_by_name(String.t()) :: Protocol.t() | nil
  def get_protocol_by_name(name) do
    Repo.get_by(Protocol, name: name)
  end

  @doc """
  Lists all protocols.

  ## Options
    * `:active` - Filter by active status (default: nil, shows all)
    * `:preload` - Preload associations (default: [])
  """
  @spec list_protocols(keyword()) :: [Protocol.t()]
  def list_protocols(opts \\ []) do
    Protocol
    |> filter_by_active(opts[:active])
    |> order_by([p], asc: p.name)
    |> preload_if(opts[:preload])
    |> Repo.all()
  end

  @doc """
  Returns a changeset for tracking protocol changes.
  """
  @spec change_protocol(Protocol.t(), map()) :: Ecto.Changeset.t()
  def change_protocol(%Protocol{} = protocol, attrs \\ %{}) do
    Protocol.changeset(protocol, attrs)
  end

  # ============================================
  # Network CRUD Operations
  # ============================================

  @doc """
  Creates a new network.
  Updates the cache on success.
  """
  @spec create_network(map()) :: {:ok, Network.t()} | {:error, Ecto.Changeset.t()}
  def create_network(attrs) do
    %Network{}
    |> Network.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(&Cache.put_network/1)
    |> tap_ok(&broadcast_change({:network_created, &1}))
  end

  @doc """
  Updates an existing network.
  Updates the cache on success.
  """
  @spec update_network(Network.t(), map()) :: {:ok, Network.t()} | {:error, Ecto.Changeset.t()}
  def update_network(%Network{} = network, attrs) do
    old_chain_id = network.chain_id

    network
    |> Network.changeset(attrs)
    |> Repo.update()
    |> tap_ok(fn updated ->
      # If chain_id changed, remove old cache entry
      if updated.chain_id != old_chain_id do
        Cache.delete_network(old_chain_id)
      end

      Cache.put_network(updated)
    end)
    |> tap_ok(&broadcast_change({:network_updated, &1}))
  end

  @doc """
  Deletes a network.
  Removes from cache on success.
  """
  @spec delete_network(Network.t()) :: {:ok, Network.t()} | {:error, Ecto.Changeset.t()}
  def delete_network(%Network{} = network) do
    Repo.delete(network)
    |> tap_ok(fn deleted -> Cache.delete_network(deleted.chain_id) end)
    |> tap_ok(&broadcast_change({:network_deleted, &1}))
  end

  @doc """
  Gets a single network by ID.
  """
  @spec get_network(integer()) :: Network.t() | nil
  def get_network(id), do: Repo.get(Network, id)

  @doc """
  Gets a single network by ID, raising if not found.
  """
  @spec get_network!(integer()) :: Network.t()
  def get_network!(id), do: Repo.get!(Network, id)

  @doc """
  Gets a network by name.
  """
  @spec get_network_by_name(String.t()) :: Network.t() | nil
  def get_network_by_name(name) do
    Repo.get_by(Network, name: name)
  end

  @doc """
  Lists all networks.

  ## Options
    * `:active` - Filter by active status (default: nil, shows all)
    * `:is_testnet` - Filter by testnet status (default: nil, shows all)
  """
  @spec list_networks(keyword()) :: [Network.t()]
  def list_networks(opts \\ []) do
    Network
    |> filter_by_active(opts[:active])
    |> filter_by_testnet(opts[:is_testnet])
    |> order_by([n], asc: n.is_testnet, asc: n.name)
    |> Repo.all()
  end

  @doc """
  Returns a changeset for tracking network changes.
  """
  @spec change_network(Network.t(), map()) :: Ecto.Changeset.t()
  def change_network(%Network{} = network, attrs \\ %{}) do
    Network.changeset(network, attrs)
  end

  # ============================================
  # Contract Address CRUD Operations
  # ============================================

  @doc """
  Creates a new contract address.
  Broadcasts change to subscribers and updates cache.
  """
  @spec create_contract_address(map()) ::
          {:ok, ContractAddress.t()} | {:error, Ecto.Changeset.t()}
  def create_contract_address(attrs) do
    %ContractAddress{}
    |> ContractAddress.changeset(normalize_address(attrs))
    |> Repo.insert()
    |> tap_ok(&Cache.put/1)
    |> tap_ok(&broadcast_change({:address_created, &1}))
  end

  @doc """
  Updates an existing contract address.
  """
  @spec update_contract_address(ContractAddress.t(), map()) ::
          {:ok, ContractAddress.t()} | {:error, Ecto.Changeset.t()}
  def update_contract_address(%ContractAddress{} = address, attrs) do
    address
    |> ContractAddress.changeset(normalize_address(attrs))
    |> Repo.update()
    |> tap_ok(&Cache.put/1)
    |> tap_ok(&broadcast_change({:address_updated, &1}))
  end

  @doc """
  Deletes a contract address.
  """
  @spec delete_contract_address(ContractAddress.t()) ::
          {:ok, ContractAddress.t()} | {:error, Ecto.Changeset.t()}
  def delete_contract_address(%ContractAddress{} = address) do
    Repo.delete(address)
    |> tap_ok(fn a -> Cache.delete(a.protocol_id, a.category, a.version, a.network) end)
    |> tap_ok(&broadcast_change({:address_deleted, &1}))
  end

  @doc """
  Gets a single contract address by ID.
  """
  @spec get_contract_address(integer()) :: ContractAddress.t() | nil
  def get_contract_address(id), do: Repo.get(ContractAddress, id)

  @doc """
  Gets a single contract address by ID, raising if not found.
  """
  @spec get_contract_address!(integer()) :: ContractAddress.t()
  def get_contract_address!(id), do: Repo.get!(ContractAddress, id)

  @doc """
  Lists all contract addresses with optional filters.

  ## Options
    * `:protocol_id` - Filter by protocol ID
    * `:category` - Filter by category
    * `:version` - Filter by version
    * `:network` - Filter by network
    * `:active` - Filter by active status (default: nil, shows all)
    * `:preload` - Preload associations (default: [])
  """
  @spec list_contract_addresses(keyword()) :: [ContractAddress.t()]
  def list_contract_addresses(opts \\ []) do
    ContractAddress
    |> filter_by_protocol_id(opts[:protocol_id])
    |> filter_by_category(opts[:category])
    |> filter_by_version(opts[:version])
    |> filter_by_network(opts[:network])
    |> filter_by_active(opts[:active])
    |> order_by([c], asc: c.category, asc: c.version, asc: c.network)
    |> preload_if(opts[:preload])
    |> Repo.all()
  end

  @doc """
  Returns a changeset for tracking contract address changes.
  """
  @spec change_contract_address(ContractAddress.t(), map()) :: Ecto.Changeset.t()
  def change_contract_address(%ContractAddress{} = address, attrs \\ %{}) do
    ContractAddress.changeset(address, attrs)
  end

  # ============================================
  # Query Functions
  # ============================================

  @doc """
  Gets the contract address for given protocol, category, version, and network.
  Uses cache for fast lookups.
  """
  @spec get_address(String.t() | integer(), String.t(), String.t(), String.t()) ::
          String.t() | nil
  def get_address(protocol, category, version, network) when is_binary(protocol) do
    case Cache.get_by_protocol_name(protocol, category, version, network) do
      {:ok, address} -> address
      :not_found -> fetch_and_cache_by_name(protocol, category, version, network)
    end
  end

  def get_address(protocol_id, category, version, network) when is_integer(protocol_id) do
    case Cache.get(protocol_id, category, version, network) do
      {:ok, address} -> address
      :not_found -> fetch_and_cache(protocol_id, category, version, network)
    end
  end

  @doc """
  Lists all addresses organized by protocol for UI display.
  Returns a nested structure: %{protocol => %{category => %{version => [addresses]}}}
  """
  @spec list_addresses_by_protocol() :: map()
  def list_addresses_by_protocol do
    list_protocols(
      preload: [
        contract_addresses:
          from(c in ContractAddress, order_by: [c.category, c.version, c.network])
      ]
    )
    |> Enum.map(fn protocol ->
      grouped =
        protocol.contract_addresses
        |> Enum.group_by(& &1.category)
        |> Enum.map(fn {category, addresses} ->
          by_version = Enum.group_by(addresses, & &1.version)
          {category, by_version}
        end)
        |> Map.new()

      {protocol, grouped}
    end)
    |> Map.new()
  end

  @doc """
  Gets all versions for a specific protocol and category.
  """
  @spec get_versions_for_contract(integer(), String.t()) :: [String.t()]
  def get_versions_for_contract(protocol_id, category) do
    ContractAddress
    |> where([c], c.protocol_id == ^protocol_id and c.category == ^category)
    |> select([c], c.version)
    |> distinct(true)
    |> order_by([c], desc: c.version)
    |> Repo.all()
  end

  @doc """
  Gets all active addresses for a given protocol and category across all versions and networks.
  """
  @spec get_active_addresses(integer(), String.t()) :: [ContractAddress.t()]
  def get_active_addresses(protocol_id, category) do
    list_contract_addresses(protocol_id: protocol_id, category: category, active: true)
  end

  @doc """
  Lists all active contract addresses.
  """
  @spec list_active_addresses() :: [ContractAddress.t()]
  def list_active_addresses do
    list_contract_addresses(active: true, preload: [:protocol])
  end

  # ============================================
  # App Settings (Key-Value Store)
  # ============================================

  @envio_url_key "envio_graphql_url"

  @doc """
  Gets an app setting by key.
  Uses ETS cache for fast lookups, falling back to database if not cached.
  """
  @spec get_app_setting(String.t()) :: String.t() | nil
  def get_app_setting(key) do
    case Cache.get_app_setting(key) do
      {:ok, value} ->
        value

      :not_found ->
        case Repo.get_by(AppSetting, key: key) do
          nil ->
            nil

          setting ->
            Cache.put_app_setting(key, setting.value)
            setting.value
        end
    end
  end

  @doc """
  Sets an app setting. Creates or updates the setting.
  Updates the cache on success.
  """
  @spec set_app_setting(String.t(), String.t(), String.t() | nil) ::
          {:ok, AppSetting.t()} | {:error, Ecto.Changeset.t()}
  def set_app_setting(key, value, description \\ nil) do
    result =
      case Repo.get_by(AppSetting, key: key) do
        nil ->
          %AppSetting{}
          |> AppSetting.changeset(%{key: key, value: value, description: description})
          |> Repo.insert()

        setting ->
          setting
          |> AppSetting.changeset(%{value: value, description: description})
          |> Repo.update()
      end

    result
    |> tap_ok(fn setting -> Cache.put_app_setting(setting.key, setting.value) end)
    |> tap_ok(&broadcast_change({:app_setting_updated, &1}))
  end

  @doc """
  Deletes an app setting by key.
  Removes from cache on success.
  """
  @spec delete_app_setting(String.t()) :: {:ok, AppSetting.t()} | {:error, :not_found}
  def delete_app_setting(key) do
    case Repo.get_by(AppSetting, key: key) do
      nil ->
        {:error, :not_found}

      setting ->
        case Repo.delete(setting) do
          {:ok, deleted} ->
            Cache.delete_app_setting(key)
            {:ok, deleted}

          error ->
            error
        end
    end
  end

  @doc """
  Gets the Envio GraphQL URL.
  Falls back to env var if not set in database.
  """
  @spec get_envio_url() :: String.t() | nil
  def get_envio_url do
    get_app_setting(@envio_url_key) ||
      Application.get_env(:anoma_explorer, :envio_graphql_url)
  end

  @doc """
  Sets the Envio GraphQL URL.
  Clears the indexer cache to ensure fresh data is fetched with the new endpoint.
  """
  @spec set_envio_url(String.t()) :: {:ok, AppSetting.t()} | {:error, Ecto.Changeset.t()}
  def set_envio_url(url) do
    result = set_app_setting(@envio_url_key, url, "Envio Hyperindex GraphQL endpoint URL")

    # Clear cache on URL change so queries use the new endpoint immediately
    case result do
      {:ok, _} -> AnomaExplorer.Indexer.Cache.clear()
      _ -> :ok
    end

    result
  end

  # ============================================
  # Legacy API (for backwards compatibility during migration)
  # ============================================

  @doc """
  Legacy function - lists settings by category.
  Maintained for backwards compatibility with existing LiveView.
  """
  @spec list_settings_by_category() :: map()
  def list_settings_by_category do
    list_contract_addresses()
    |> Enum.group_by(& &1.category)
  end

  @doc """
  Legacy function - gets a setting by ID.
  """
  def get_setting!(id), do: get_contract_address!(id)

  @doc """
  Legacy function - creates a setting.
  """
  def create_setting(attrs), do: create_contract_address(attrs)

  @doc """
  Legacy function - updates a setting.
  """
  def update_setting(setting, attrs), do: update_contract_address(setting, attrs)

  @doc """
  Legacy function - deletes a setting.
  """
  def delete_setting(setting), do: delete_contract_address(setting)

  @doc """
  Legacy function - changes setting.
  """
  def change_setting(setting, attrs \\ %{}), do: change_contract_address(setting, attrs)

  # ============================================
  # PubSub Broadcasting
  # ============================================

  @doc """
  Subscribe to setting changes.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  defp broadcast_change(event) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:settings_changed, event})
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp normalize_address(attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, :address) ->
        Map.put(attrs, :address, String.downcase(attrs[:address]))

      Map.has_key?(attrs, "address") ->
        Map.put(attrs, "address", String.downcase(attrs["address"]))

      true ->
        attrs
    end
  end

  defp filter_by_protocol_id(query, nil), do: query
  defp filter_by_protocol_id(query, id), do: where(query, [c], c.protocol_id == ^id)

  defp filter_by_category(query, nil), do: query
  defp filter_by_category(query, cat), do: where(query, [c], c.category == ^cat)

  defp filter_by_version(query, nil), do: query
  defp filter_by_version(query, ver), do: where(query, [c], c.version == ^ver)

  defp filter_by_network(query, nil), do: query
  defp filter_by_network(query, net), do: where(query, [c], c.network == ^net)

  defp filter_by_active(query, nil), do: query
  defp filter_by_active(query, active), do: where(query, [c], c.active == ^active)

  defp filter_by_testnet(query, nil), do: query
  defp filter_by_testnet(query, is_testnet), do: where(query, [n], n.is_testnet == ^is_testnet)

  defp preload_if(query, nil), do: query
  defp preload_if(query, []), do: query
  defp preload_if(query, preloads), do: preload(query, ^preloads)

  defp fetch_and_cache(protocol_id, category, version, network) do
    case Repo.one(
           from c in ContractAddress,
             where:
               c.protocol_id == ^protocol_id and c.category == ^category and
                 c.version == ^version and c.network == ^network and c.active == true,
             select: c.address
         ) do
      nil ->
        nil

      address ->
        Cache.put_address(protocol_id, category, version, network, address)
        address
    end
  end

  defp fetch_and_cache_by_name(protocol_name, category, version, network) do
    case get_protocol_by_name(protocol_name) do
      nil -> nil
      protocol -> fetch_and_cache(protocol.id, category, version, network)
    end
  end

  defp tap_ok({:ok, result} = response, fun) do
    fun.(result)
    response
  end

  defp tap_ok(error, _fun), do: error
end
