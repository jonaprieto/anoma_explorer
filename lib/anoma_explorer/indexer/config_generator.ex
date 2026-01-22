defmodule AnomaExplorer.Indexer.ConfigGenerator do
  @moduledoc """
  Generates Envio Hyperindex config.yaml from database settings.

  Reads active networks and contract addresses from the database and generates
  a config.yaml file for the Envio indexer at runtime.
  """

  require Logger

  alias AnomaExplorer.Settings

  @indexer_path "indexer"
  @config_path Path.join(@indexer_path, "config.yaml")

  # PA-EVM events from IProtocolAdapter.sol and ICommitmentTree.sol
  @pa_evm_events [
    "TransactionExecuted(bytes32[] tags, bytes32[] logicRefs)",
    "ActionExecuted(bytes32 actionTreeRoot, uint256 actionTagCount)",
    "ForwarderCallExecuted(address indexed untrustedForwarder, bytes input, bytes output)",
    "ResourcePayload(bytes32 indexed tag, uint256 index, bytes blob)",
    "DiscoveryPayload(bytes32 indexed tag, uint256 index, bytes blob)",
    "ExternalPayload(bytes32 indexed tag, uint256 index, bytes blob)",
    "ApplicationPayload(bytes32 indexed tag, uint256 index, bytes blob)",
    "CommitmentTreeRootAdded(bytes32 root)"
  ]

  @doc """
  Generates config.yaml from current database settings.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec generate() :: :ok | {:error, term()}
  def generate do
    with {:ok, config} <- build_config(),
         {:ok, yaml_content} <- to_yaml(config),
         :ok <- ensure_indexer_dir(),
         :ok <- File.write(@config_path, yaml_content) do
      Logger.info("[ConfigGenerator] Generated config.yaml at #{@config_path}")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("[ConfigGenerator] Failed to generate config: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Returns the path to the generated config.yaml file.
  """
  @spec config_path() :: String.t()
  def config_path, do: @config_path

  @doc """
  Returns the path to the indexer directory.
  """
  @spec indexer_path() :: String.t()
  def indexer_path, do: @indexer_path

  @doc """
  Builds the config map from database settings.
  """
  @spec build_config() :: {:ok, map()} | {:error, term()}
  def build_config do
    try do
      networks = Settings.list_networks(active: true)
      addresses = Settings.list_contract_addresses(active: true, preload: [:protocol])

      config = %{
        "name" => "anoma-explorer-indexer",
        "contracts" => build_contracts_config(),
        "networks" => build_networks_config(networks, addresses),
        "unordered_multichain_mode" => true
      }

      {:ok, config}
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  defp build_contracts_config do
    [
      %{
        "name" => "ProtocolAdapter",
        "handler" => "src/EventHandlers.ts",
        "events" => @pa_evm_events
      }
    ]
  end

  defp build_networks_config(networks, addresses) do
    # Group addresses by network name
    addresses_by_network = Enum.group_by(addresses, & &1.network)

    networks
    |> Enum.filter(& &1.chain_id)
    |> Enum.map(fn network ->
      network_addresses = Map.get(addresses_by_network, network.name, [])

      # Filter for protocol_adapter category addresses
      pa_addresses =
        network_addresses
        |> Enum.filter(&(&1.category == "protocol_adapter"))
        |> Enum.map(& &1.address)

      %{
        "id" => network.chain_id,
        "start_block" => 0,
        "contracts" => [
          %{
            "name" => "ProtocolAdapter",
            "address" => pa_addresses
          }
        ]
      }
    end)
    |> Enum.filter(fn network_config ->
      # Only include networks that have at least one address
      network_config["contracts"]
      |> List.first()
      |> Map.get("address")
      |> length() > 0
    end)
  end

  defp to_yaml(config) do
    try do
      yaml = generate_yaml(config)
      {:ok, yaml}
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  defp generate_yaml(config) do
    """
    name: #{config["name"]}
    contracts:
    #{generate_contracts_yaml(config["contracts"])}
    field_selection:
      transaction_fields:
        - "hash"
    networks:
    #{generate_networks_yaml(config["networks"])}
    unordered_multichain_mode: #{config["unordered_multichain_mode"]}
    """
  end

  defp generate_contracts_yaml(contracts) do
    contracts
    |> Enum.map(fn contract ->
      events_yaml =
        contract["events"]
        |> Enum.map(fn event -> "      - event: \"#{event}\"" end)
        |> Enum.join("\n")

      """
        - name: #{contract["name"]}
          handler: #{contract["handler"]}
          events:
      #{events_yaml}
      """
    end)
    |> Enum.join("")
    |> String.trim_trailing()
  end

  defp generate_networks_yaml(networks) do
    networks
    |> Enum.map(fn network ->
      contracts_yaml =
        network["contracts"]
        |> Enum.map(fn contract ->
          addresses_yaml =
            contract["address"]
            |> Enum.map(fn addr -> "        - \"#{addr}\"" end)
            |> Enum.join("\n")

          """
              - name: #{contract["name"]}
                address:
          #{addresses_yaml}
          """
        end)
        |> Enum.join("")
        |> String.trim_trailing()

      """
        - id: #{network["id"]}
          start_block: #{network["start_block"]}
          contracts:
      #{contracts_yaml}
      """
    end)
    |> Enum.join("")
    |> String.trim_trailing()
  end

  defp ensure_indexer_dir do
    case File.mkdir_p(@indexer_path) do
      :ok -> :ok
      {:error, :eexist} -> :ok
      error -> error
    end
  end
end
