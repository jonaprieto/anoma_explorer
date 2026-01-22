defmodule AnomaExplorer.Indexer.Networks do
  @moduledoc """
  Network name mappings and block explorer URLs for chain IDs.
  """

  @chain_info %{
    1 => %{name: "Ethereum", short: "ETH", explorer: "https://etherscan.io"},
    5 => %{name: "Goerli", short: "Goerli", explorer: "https://goerli.etherscan.io"},
    10 => %{name: "Optimism", short: "OP", explorer: "https://optimistic.etherscan.io"},
    56 => %{name: "BNB Chain", short: "BNB", explorer: "https://bscscan.com"},
    100 => %{name: "Gnosis", short: "Gnosis", explorer: "https://gnosisscan.io"},
    137 => %{name: "Polygon", short: "Polygon", explorer: "https://polygonscan.com"},
    250 => %{name: "Fantom", short: "FTM", explorer: "https://ftmscan.com"},
    324 => %{name: "zkSync Era", short: "zkSync", explorer: "https://explorer.zksync.io"},
    420 => %{
      name: "Optimism Goerli",
      short: "OP Goerli",
      explorer: "https://goerli-optimism.etherscan.io"
    },
    8453 => %{name: "Base", short: "Base", explorer: "https://basescan.org"},
    42161 => %{name: "Arbitrum One", short: "Arb", explorer: "https://arbiscan.io"},
    42170 => %{name: "Arbitrum Nova", short: "Arb Nova", explorer: "https://nova.arbiscan.io"},
    43114 => %{name: "Avalanche", short: "AVAX", explorer: "https://snowtrace.io"},
    59144 => %{name: "Linea", short: "Linea", explorer: "https://lineascan.build"},
    80001 => %{
      name: "Polygon Mumbai",
      short: "Mumbai",
      explorer: "https://mumbai.polygonscan.com"
    },
    80002 => %{name: "Polygon Amoy", short: "Amoy", explorer: "https://amoy.polygonscan.com"},
    84531 => %{name: "Base Goerli", short: "Base Goerli", explorer: "https://goerli.basescan.org"},
    84532 => %{name: "Base Sepolia", short: "Base Sep", explorer: "https://sepolia.basescan.org"},
    421_613 => %{
      name: "Arbitrum Goerli",
      short: "Arb Goerli",
      explorer: "https://goerli.arbiscan.io"
    },
    421_614 => %{
      name: "Arbitrum Sepolia",
      short: "Arb Sep",
      explorer: "https://sepolia.arbiscan.io"
    },
    534_352 => %{name: "Scroll", short: "Scroll", explorer: "https://scrollscan.com"},
    11_155_111 => %{name: "Sepolia", short: "Sepolia", explorer: "https://sepolia.etherscan.io"},
    11_155_420 => %{
      name: "Optimism Sepolia",
      short: "OP Sep",
      explorer: "https://sepolia-optimism.etherscan.io"
    }
  }

  @doc """
  Returns the display name for a chain ID.
  """
  @spec name(integer() | nil) :: String.t()
  def name(nil), do: "Unknown"

  def name(chain_id) when is_integer(chain_id) do
    case Map.get(@chain_info, chain_id) do
      %{name: name} -> name
      nil -> "Chain #{chain_id}"
    end
  end

  @doc """
  Returns a short name for a chain ID (for badges).
  """
  @spec short_name(integer() | nil) :: String.t()
  def short_name(nil), do: "?"

  def short_name(chain_id) when is_integer(chain_id) do
    case Map.get(@chain_info, chain_id) do
      %{short: short} -> short
      nil -> "#{chain_id}"
    end
  end

  @doc """
  Returns the block explorer URL for a chain ID.
  """
  @spec explorer_url(integer() | nil) :: String.t() | nil
  def explorer_url(nil), do: nil

  def explorer_url(chain_id) when is_integer(chain_id) do
    case Map.get(@chain_info, chain_id) do
      %{explorer: url} -> url
      nil -> nil
    end
  end

  @doc """
  Returns the URL for a specific block on the chain's explorer.
  """
  @spec block_url(integer() | nil, integer() | nil) :: String.t() | nil
  def block_url(nil, _), do: nil
  def block_url(_, nil), do: nil

  def block_url(chain_id, block_number) do
    case explorer_url(chain_id) do
      nil -> nil
      base_url -> "#{base_url}/block/#{block_number}"
    end
  end

  @doc """
  Returns the URL for a specific transaction on the chain's explorer.
  """
  @spec tx_url(integer() | nil, String.t() | nil) :: String.t() | nil
  def tx_url(nil, _), do: nil
  def tx_url(_, nil), do: nil

  def tx_url(chain_id, tx_hash) do
    case explorer_url(chain_id) do
      nil -> nil
      base_url -> "#{base_url}/tx/#{tx_hash}"
    end
  end

  @doc """
  Returns the URL for a specific address on the chain's explorer.
  """
  @spec address_url(integer() | nil, String.t() | nil) :: String.t() | nil
  def address_url(nil, _), do: nil
  def address_url(_, nil), do: nil

  def address_url(chain_id, address) do
    case explorer_url(chain_id) do
      nil -> nil
      base_url -> "#{base_url}/address/#{address}"
    end
  end

  @doc """
  Returns full chain info for a chain ID.
  """
  @spec chain_info(integer() | nil) :: map()
  def chain_info(nil), do: %{name: "Unknown", short: "?", explorer: nil, chain_id: nil}

  def chain_info(chain_id) when is_integer(chain_id) do
    case Map.get(@chain_info, chain_id) do
      nil -> %{name: "Chain #{chain_id}", short: "#{chain_id}", explorer: nil, chain_id: chain_id}
      info -> Map.put(info, :chain_id, chain_id)
    end
  end

  @doc """
  Returns a list of all known chains for dropdown selects.
  Returns a list of {chain_id, name} tuples sorted by name.
  """
  @spec list_chains() :: [{integer(), String.t()}]
  def list_chains do
    @chain_info
    |> Enum.map(fn {chain_id, %{name: name}} -> {chain_id, name} end)
    |> Enum.sort_by(fn {_id, name} -> name end)
  end
end
