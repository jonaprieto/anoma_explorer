defmodule AnomaExplorer.ChainVerifier do
  @moduledoc """
  Verifies contract addresses using blockchain explorer APIs.

  Uses the Etherscan V2 API which supports multiple chains with a single API key.
  Verifies that an address is a deployed contract and optionally
  retrieves contract information.
  """

  require Logger

  @type verification_result ::
          {:ok, :verified, map()}
          | {:ok, :unverified}
          | {:error, :not_contract}
          | {:error, :network_unsupported}
          | {:error, :api_error, String.t()}

  # Etherscan V2 API base URL (works for all supported chains)
  @etherscan_v2_api "https://api.etherscan.io/v2/api"

  # Map network names to their chain IDs for Etherscan V2 API
  @chain_ids %{
    # Ethereum
    "eth-mainnet" => 1,
    "eth-sepolia" => 11155111,
    # Base
    "base-mainnet" => 8453,
    "base-sepolia" => 84532,
    # Arbitrum
    "arbitrum-mainnet" => 42161,
    "arb-mainnet" => 42161,
    "arbitrum-sepolia" => 421614,
    "arb-sepolia" => 421614,
    # Polygon
    "polygon-mainnet" => 137,
    "polygon-amoy" => 80002,
    # Optimism
    "optimism-mainnet" => 10,
    "op-mainnet" => 10,
    "optimism-sepolia" => 11155420,
    "op-sepolia" => 11155420,
    # BSC
    "bsc-mainnet" => 56,
    "bsc-testnet" => 97,
    # Avalanche
    "avalanche-mainnet" => 43114,
    "avalanche-fuji" => 43113
  }

  @doc """
  Verifies a contract address on the specified network.

  Returns:
  - `{:ok, :verified, info}` - Contract exists and source code is verified
  - `{:ok, :unverified}` - Contract exists but source code is not verified
  - `{:error, :not_contract}` - Address is not a contract (EOA or invalid)
  - `{:error, :network_unsupported}` - Network not supported for verification
  - `{:error, :api_error, reason}` - API call failed
  """
  @spec verify(String.t(), String.t()) :: verification_result()
  def verify(network, address) do
    case get_chain_id(network) do
      nil ->
        {:error, :network_unsupported}

      chain_id ->
        api_key = get_api_key()
        do_verify(chain_id, address, api_key)
    end
  end

  @doc """
  Checks if a network is supported for verification.
  """
  @spec network_supported?(String.t()) :: boolean()
  def network_supported?(network) do
    Map.has_key?(@chain_ids, network)
  end

  @doc """
  Returns the list of supported networks.
  """
  @spec supported_networks() :: [String.t()]
  def supported_networks do
    Map.keys(@chain_ids)
  end

  # Private functions

  defp get_chain_id(network) do
    Map.get(@chain_ids, network)
  end

  defp get_api_key do
    # Etherscan V2 uses a single API key for all chains
    Application.get_env(:anoma_explorer, :etherscan_api_key)
  end

  defp do_verify(chain_id, address, api_key) do
    with {:ok, is_contract} <- check_is_contract(chain_id, address, api_key),
         true <- is_contract do
      check_contract_verified(chain_id, address, api_key)
    else
      false ->
        {:error, :not_contract}

      {:error, reason} ->
        {:error, :api_error, inspect(reason)}
    end
  end

  defp check_is_contract(chain_id, address, api_key) do
    url = build_url(chain_id, "proxy", "eth_getCode", %{address: address}, api_key)

    case http_get(url) do
      {:ok, %{"result" => result}} when result not in [nil, "0x", "0x0"] ->
        {:ok, true}

      {:ok, %{"result" => _}} ->
        {:ok, false}

      {:ok, %{"error" => error}} ->
        Logger.warning("Chain verifier API error: #{inspect(error)}")
        {:error, error}

      {:error, reason} ->
        Logger.warning("Chain verifier HTTP error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp check_contract_verified(chain_id, address, api_key) do
    url = build_url(chain_id, "contract", "getabi", %{address: address}, api_key)

    case http_get(url) do
      {:ok, %{"status" => "1", "result" => abi}} ->
        {:ok, :verified, %{abi: abi}}

      {:ok, %{"status" => "0", "result" => "Contract source code not verified"}} ->
        {:ok, :unverified}

      {:ok, %{"status" => "0", "message" => "NOTOK", "result" => result}} ->
        if String.contains?(result, "not verified") do
          {:ok, :unverified}
        else
          {:error, :api_error, result}
        end

      {:ok, response} ->
        Logger.warning("Unexpected verification response: #{inspect(response)}")
        {:ok, :unverified}

      {:error, reason} ->
        {:error, :api_error, inspect(reason)}
    end
  end

  defp build_url(chain_id, module, action, params, api_key) do
    query_params =
      %{chainid: chain_id, module: module, action: action}
      |> Map.merge(params)
      |> maybe_add_api_key(api_key)
      |> URI.encode_query()

    "#{@etherscan_v2_api}?#{query_params}"
  end

  defp maybe_add_api_key(params, nil), do: params
  defp maybe_add_api_key(params, ""), do: params
  defp maybe_add_api_key(params, key), do: Map.put(params, :apikey, key)

  defp http_get(url) do
    request = Finch.build(:get, url)

    case Finch.request(request, AnomaExplorer.Finch, receive_timeout: 15_000) do
      {:ok, %Finch.Response{status: status, body: body}} when status in 200..299 ->
        Jason.decode(body)

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
