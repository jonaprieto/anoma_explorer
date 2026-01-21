defmodule AnomaExplorer.Config do
  @moduledoc """
  Configuration validation and parsing for AnomaExplorer.

  Validates and parses environment variables:
  - CONTRACT_ADDRESS: Ethereum address (0x + 40 hex chars, downcased)
  - ALCHEMY_API_KEY: API key for Alchemy
  - ALCHEMY_NETWORKS: Comma-separated list of networks
  - POLL_INTERVAL_SECONDS: Polling interval (default 20)
  - START_BLOCK: Starting block number (optional)
  - BACKFILL_BLOCKS: Number of blocks to backfill (default 50_000)
  - PAGE_SIZE: Results per page (default 100)
  - MAX_REQ_PER_SECOND: Rate limit (default 5)
  - LOG_CHUNK_BLOCKS: Block chunk size for logs (default 2_000)
  """

  @supported_networks ~w(
    eth-mainnet
    eth-sepolia
    arb-mainnet
    arb-sepolia
    polygon-mainnet
    polygon-amoy
    base-mainnet
    base-sepolia
    optimism-mainnet
    optimism-sepolia
  )

  @doc """
  Returns the list of supported Alchemy network identifiers.
  """
  @spec supported_networks() :: [String.t()]
  def supported_networks, do: @supported_networks

  @doc """
  Validates an Ethereum contract address.

  Requirements:
  - Must start with "0x"
  - Must have exactly 40 hex characters after the prefix
  - Will be downcased for consistency
  """
  @spec validate_contract_address(String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  def validate_contract_address(nil), do: {:error, "CONTRACT_ADDRESS is required"}
  def validate_contract_address(""), do: {:error, "CONTRACT_ADDRESS cannot be empty"}

  def validate_contract_address(address) when is_binary(address) do
    downcased = String.downcase(address)

    with {:ok, _} <- validate_prefix(downcased),
         {:ok, hex_part} <- extract_hex_part(downcased),
         :ok <- validate_hex_length(hex_part),
         :ok <- validate_hex_chars(hex_part) do
      {:ok, downcased}
    end
  end

  defp validate_prefix("0x" <> _), do: {:ok, :valid}
  defp validate_prefix(_), do: {:error, "CONTRACT_ADDRESS must start with 0x"}

  defp extract_hex_part("0x" <> hex), do: {:ok, hex}

  defp validate_hex_length(hex) when byte_size(hex) == 40, do: :ok

  defp validate_hex_length(_),
    do: {:error, "CONTRACT_ADDRESS must have exactly 40 hex characters after 0x"}

  defp validate_hex_chars(hex) do
    if Regex.match?(~r/^[0-9a-f]+$/, hex) do
      :ok
    else
      {:error, "CONTRACT_ADDRESS contains invalid hex characters"}
    end
  end

  @doc """
  Parses a comma-separated list of network identifiers.

  Each network must be in the supported networks list.
  """
  @spec parse_networks(String.t() | nil) :: {:ok, [String.t()]} | {:error, String.t()}
  def parse_networks(nil), do: {:error, "ALCHEMY_NETWORKS is required"}
  def parse_networks(""), do: {:error, "ALCHEMY_NETWORKS cannot be empty"}

  def parse_networks(networks_string) when is_binary(networks_string) do
    networks =
      networks_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if Enum.empty?(networks) do
      {:error, "ALCHEMY_NETWORKS cannot be empty"}
    else
      case validate_all_networks(networks) do
        :ok -> {:ok, networks}
        {:error, _} = error -> error
      end
    end
  end

  defp validate_all_networks(networks) do
    invalid = Enum.reject(networks, &(&1 in @supported_networks))

    if Enum.empty?(invalid) do
      :ok
    else
      {:error,
       "Unknown networks: #{Enum.join(invalid, ", ")}. Supported: #{Enum.join(@supported_networks, ", ")}"}
    end
  end

  @doc """
  Parses a positive integer from a string.

  Returns the default value if input is nil (when default is provided).
  """
  @spec parse_positive_integer(String.t() | nil, atom(), integer() | nil) ::
          {:ok, integer()} | {:error, String.t()}
  def parse_positive_integer(value, name, default \\ nil)

  def parse_positive_integer(nil, _name, default) when is_integer(default) and default > 0 do
    {:ok, default}
  end

  def parse_positive_integer(nil, name, _default) do
    {:error, "#{name} is required"}
  end

  def parse_positive_integer(value, name, _default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> {:ok, int}
      {int, ""} when int <= 0 -> {:error, "#{name} must be a positive integer"}
      _ -> {:error, "#{name} must be a valid integer"}
    end
  end

  @doc """
  Builds the Alchemy RPC URL for a given network.
  """
  @spec network_rpc_url(String.t(), String.t()) :: String.t()
  def network_rpc_url(network, api_key) do
    "https://#{network}.g.alchemy.com/v2/#{api_key}"
  end

  @doc """
  Loads and validates all configuration from environment variables.

  Returns a map with all validated config values or raises on error.
  """
  @spec load!() :: map()
  def load! do
    contract_address = fetch_env!("CONTRACT_ADDRESS", &validate_contract_address/1)
    api_key = fetch_required_env!("ALCHEMY_API_KEY")
    networks = fetch_env!("ALCHEMY_NETWORKS", &parse_networks/1)

    poll_interval = fetch_int_env("POLL_INTERVAL_SECONDS", 20)
    start_block = fetch_optional_int_env("START_BLOCK")
    backfill_blocks = fetch_int_env("BACKFILL_BLOCKS", 50_000)
    page_size = fetch_int_env("PAGE_SIZE", 100)
    max_req_per_second = fetch_int_env("MAX_REQ_PER_SECOND", 5)
    log_chunk_blocks = fetch_int_env("LOG_CHUNK_BLOCKS", 2_000)

    %{
      contract_address: contract_address,
      api_key: api_key,
      networks: networks,
      poll_interval_seconds: poll_interval,
      start_block: start_block,
      backfill_blocks: backfill_blocks,
      page_size: page_size,
      max_req_per_second: max_req_per_second,
      log_chunk_blocks: log_chunk_blocks
    }
  end

  defp fetch_env!(name, validator) do
    value = System.get_env(name)

    case validator.(value) do
      {:ok, validated} -> validated
      {:error, msg} -> raise "Configuration error: #{msg}"
    end
  end

  defp fetch_required_env!(name) do
    case System.get_env(name) do
      nil -> raise "Configuration error: #{name} is required"
      "" -> raise "Configuration error: #{name} cannot be empty"
      value -> value
    end
  end

  defp fetch_int_env(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> parse_positive_integer!(value, name)
    end
  end

  defp fetch_optional_int_env(name) do
    case System.get_env(name) do
      nil -> nil
      value -> parse_positive_integer!(value, name)
    end
  end

  defp parse_positive_integer!(value, name) do
    case parse_positive_integer(value, name) do
      {:ok, int} -> int
      {:error, msg} -> raise "Configuration error: #{msg}"
    end
  end
end
