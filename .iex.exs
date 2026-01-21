# AnomaExplorer IEx Helpers
# Load with: iex -S mix or iex -S mix phx.server

alias AnomaExplorer.Repo
alias AnomaExplorer.Config
alias AnomaExplorer.Activity
alias AnomaExplorer.Ingestion
alias AnomaExplorer.Ingestion.Sync
alias AnomaExplorer.Alchemy
alias AnomaExplorer.Workers.IngestionWorker

# Import Ecto.Query for interactive queries
import Ecto.Query

IO.puts("\n=== AnomaExplorer IEx Helpers ===\n")

defmodule H do
  @moduledoc """
  Helper functions for IEx exploration.

  Available functions:
  - caddr/0         - Get configured contract address
  - nets/0          - Get configured networks
  - supported/0     - List all supported networks
  - rpc_url/1       - Get RPC URL for a network
  - ingest_once/1   - Run one ingestion cycle for a network
  - latest/2        - Fetch latest n activity rows
  - anoma_addrs/0   - Show known Anoma contract addresses
  """

  # Known Anoma Protocol Adapter addresses
  @protocol_adapters %{
    "eth-sepolia" => "0x2E539c08414DCaBF06305d4095e11096F3d7e612",
    "base-sepolia" => "0x9ED43C229480659bF6B6607C46d7B96c6D760cBB",
    "base-mainnet" => "0x9ED43C229480659bF6B6607C46d7B96c6D760cBB"
  }

  # Known ERC20 Forwarder addresses
  @erc20_forwarders %{
    "eth-sepolia" => "0xa04942494174eD85A11416E716262eC0AE0a065d",
    "eth-mainnet" => "0x0D38C332135f9f0de4dcc4a6F9c918b72e2A1Df3",
    "base-sepolia" => "0xA73Ce304460F17C3530b58BA95bCD3B89Bd38D69",
    "base-mainnet" => "0xA73Ce304460F17C3530b58BA95bCD3B89Bd38D69",
    "optimism-mainnet" => "0xA73Ce304460F17C3530b58BA95bCD3B89Bd38D69",
    "arb-mainnet" => "0xA73Ce304460F17C3530b58BA95bCD3B89Bd38D69"
  }

  @doc "Get the configured contract address (from env)"
  def caddr do
    case System.get_env("CONTRACT_ADDRESS") do
      nil -> {:error, "CONTRACT_ADDRESS not set"}
      addr -> AnomaExplorer.Config.validate_contract_address(addr)
    end
  end

  @doc "Get the configured networks (from env)"
  def nets do
    case System.get_env("ALCHEMY_NETWORKS") do
      nil -> {:error, "ALCHEMY_NETWORKS not set"}
      networks -> AnomaExplorer.Config.parse_networks(networks)
    end
  end

  @doc "List all supported Alchemy networks"
  def supported do
    AnomaExplorer.Config.supported_networks()
  end

  @doc "Get RPC URL for a network (requires ALCHEMY_API_KEY)"
  def rpc_url(network) do
    case System.get_env("ALCHEMY_API_KEY") do
      nil -> {:error, "ALCHEMY_API_KEY not set"}
      key -> AnomaExplorer.Config.network_rpc_url(network, key)
    end
  end

  @doc "Show known Anoma contract addresses"
  def anoma_addrs do
    IO.puts("""

    Anoma Protocol Adapter Addresses:
    #{format_addrs(@protocol_adapters)}

    ERC20 Forwarder Addresses:
    #{format_addrs(@erc20_forwarders)}
    """)
  end

  defp format_addrs(map) do
    map
    |> Enum.map(fn {net, addr} -> "  #{net}: #{addr}" end)
    |> Enum.join("\n")
  end

  @doc "Get Protocol Adapter address for a network"
  def pa_addr(network), do: Map.get(@protocol_adapters, network, :not_found)

  @doc "Get ERC20 Forwarder address for a network"
  def forwarder_addr(network), do: Map.get(@erc20_forwarders, network, :not_found)

  @doc "Run one ingestion cycle for a network"
  def ingest_once(network) do
    api_key = System.get_env("ALCHEMY_API_KEY")
    contract = System.get_env("CONTRACT_ADDRESS")

    cond do
      is_nil(api_key) ->
        {:error, "ALCHEMY_API_KEY not set"}

      is_nil(contract) ->
        {:error, "CONTRACT_ADDRESS not set"}

      true ->
        AnomaExplorer.Ingestion.Sync.sync_logs(network, contract, api_key)
    end
  end

  @doc "Fetch latest n activity rows for a network (or all if network is nil)"
  def latest(network \\ nil, n \\ 10) do
    opts = [limit: n]
    opts = if network, do: Keyword.put(opts, :network, network), else: opts
    AnomaExplorer.Activity.list_activities(opts)
  end

  @doc "Get current block number for a network"
  def block(network) do
    case System.get_env("ALCHEMY_API_KEY") do
      nil -> {:error, "ALCHEMY_API_KEY not set"}
      key -> AnomaExplorer.Alchemy.get_block_number(network, key)
    end
  end

  @doc "Print helper usage"
  def help do
    IO.puts("""

    AnomaExplorer IEx Helpers
    ========================

    Configuration:
      H.caddr()         - Get configured contract address
      H.nets()          - Get configured networks
      H.supported()     - List all supported Alchemy networks
      H.rpc_url(net)    - Get RPC URL for a network

    Anoma Addresses:
      H.anoma_addrs()       - Show all known Anoma contract addresses
      H.pa_addr(net)        - Get Protocol Adapter address for network
      H.forwarder_addr(net) - Get ERC20 Forwarder address for network

    Ingestion:
      H.ingest_once(net)  - Run one sync cycle for a network
      H.latest(net, n)    - Get latest n activities (net optional)
      H.block(net)        - Get current block number

    Environment variables needed:
      CONTRACT_ADDRESS    - Ethereum address to track (use Anoma addresses above)
      ALCHEMY_API_KEY     - Your Alchemy API key
      ALCHEMY_NETWORKS    - Comma-separated networks

    Example setup for Anoma on Base Sepolia:
      export CONTRACT_ADDRESS=0x9ED43C229480659bF6B6607C46d7B96c6D760cBB
      export ALCHEMY_API_KEY=your_key_here
      export ALCHEMY_NETWORKS=base-sepolia

    Example setup for ERC20 Forwarder on mainnet chains:
      export CONTRACT_ADDRESS=0xA73Ce304460F17C3530b58BA95bCD3B89Bd38D69
      export ALCHEMY_NETWORKS=base-mainnet,optimism-mainnet,arb-mainnet
    """)
  end
end

IO.puts("Type H.help() for available helper functions")
IO.puts("Type H.anoma_addrs() to see known Anoma contract addresses\n")
