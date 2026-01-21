defmodule AnomaExplorer.Alchemy do
  @moduledoc """
  Alchemy API client for blockchain data.

  Provides functions for:
  - JSON-RPC calls (eth_getLogs, eth_blockNumber)
  - Asset transfers API (alchemy_getAssetTransfers)
  - Response parsing and normalization
  """

  alias AnomaExplorer.Config

  @http_client Application.compile_env(
                 :anoma_explorer,
                 :http_client,
                 AnomaExplorer.HTTPClient.FinchClient
               )

  # Public API

  @doc """
  Fetches the current block number for a network.
  """
  @spec get_block_number(String.t(), String.t()) :: {:ok, integer()} | {:error, term()}
  def get_block_number(network, api_key) do
    url = Config.network_rpc_url(network, api_key)
    request = build_request("eth_blockNumber", [], 1)

    with {:ok, response} <- @http_client.post(url, request, []),
         {:ok, result} <- parse_response(response) do
      {:ok, parse_hex(result)}
    end
  end

  @doc """
  Fetches logs for a contract within a block range.
  """
  @spec get_logs(
          String.t(),
          String.t(),
          String.t(),
          integer() | String.t(),
          integer() | String.t()
        ) ::
          {:ok, [map()]} | {:error, term()}
  def get_logs(network, api_key, contract_address, from_block, to_block) do
    url = Config.network_rpc_url(network, api_key)

    params = %{
      fromBlock: to_hex_block(from_block),
      toBlock: to_hex_block(to_block),
      address: contract_address
    }

    request = build_request("eth_getLogs", [params], 1)

    with {:ok, response} <- @http_client.post(url, request, []),
         {:ok, logs} when is_list(logs) <- parse_response(response) do
      parsed_logs =
        Enum.map(logs, fn log ->
          parse_log(log, network, contract_address)
        end)

      {:ok, parsed_logs}
    end
  end

  @doc """
  Fetches asset transfers for a contract within a block range.
  """
  @spec get_asset_transfers(
          String.t(),
          String.t(),
          String.t(),
          integer() | String.t(),
          integer() | String.t(),
          keyword()
        ) ::
          {:ok, [map()], String.t() | nil} | {:error, term()}
  def get_asset_transfers(network, api_key, contract_address, from_block, to_block, opts \\ []) do
    url = Config.network_rpc_url(network, api_key)

    params = %{
      fromBlock: to_hex_block(from_block),
      toBlock: to_hex_block(to_block),
      toAddress: contract_address,
      category: ["external", "internal", "erc20", "erc721", "erc1155"],
      withMetadata: true,
      maxCount: to_hex_block(opts[:max_count] || 100)
    }

    params =
      if opts[:page_key] do
        Map.put(params, :pageKey, opts[:page_key])
      else
        params
      end

    request = build_request("alchemy_getAssetTransfers", [params], 1)

    with {:ok, response} <- @http_client.post(url, request, []),
         {:ok, result} when is_map(result) <- parse_response(response) do
      transfers =
        result
        |> Map.get("transfers", [])
        |> Enum.map(fn transfer ->
          parse_transfer(transfer, network, contract_address)
        end)

      page_key = Map.get(result, "pageKey")

      {:ok, transfers, page_key}
    end
  end

  # Request/Response helpers

  @doc """
  Builds a JSON-RPC request.
  """
  @spec build_request(String.t(), list(), integer()) :: map()
  def build_request(method, params, id) do
    %{
      jsonrpc: "2.0",
      id: id,
      method: method,
      params: params
    }
  end

  @doc """
  Parses a JSON-RPC response.
  """
  @spec parse_response(map()) :: {:ok, term()} | {:error, term()}
  def parse_response(%{"result" => result}), do: {:ok, result}
  def parse_response(%{"error" => error}), do: {:error, error}
  def parse_response(_), do: {:error, :no_result}

  @doc """
  Parses a hex string to integer.
  """
  @spec parse_hex(String.t() | nil) :: integer() | nil
  def parse_hex(nil), do: nil

  def parse_hex("0x" <> hex) do
    case Integer.parse(hex, 16) do
      {int, ""} -> int
      _ -> nil
    end
  end

  def parse_hex(_), do: nil

  @doc """
  Converts a block number to hex string.
  """
  @spec to_hex_block(integer() | String.t()) :: String.t()
  def to_hex_block(block) when is_integer(block),
    do: "0x" <> String.downcase(Integer.to_string(block, 16))

  def to_hex_block(block) when is_binary(block), do: block

  @doc """
  Parses a raw log entry into a normalized map.
  """
  @spec parse_log(map(), String.t(), String.t()) :: map()
  def parse_log(raw_log, network, contract_address) do
    topics = Map.get(raw_log, "topics", [])

    %{
      network: network,
      contract_address: contract_address,
      kind: "log",
      tx_hash: raw_log["transactionHash"],
      block_number: parse_hex(raw_log["blockNumber"]),
      log_index: parse_hex(raw_log["logIndex"]),
      tx_index: parse_hex(raw_log["transactionIndex"]),
      topic0: List.first(topics),
      topics: topics,
      data: raw_log["data"],
      raw: raw_log
    }
  end

  @doc """
  Parses a raw asset transfer into a normalized map.
  """
  @spec parse_transfer(map(), String.t(), String.t()) :: map()
  def parse_transfer(raw_transfer, network, contract_address) do
    %{
      network: network,
      contract_address: contract_address,
      kind: "transfer",
      tx_hash: raw_transfer["hash"],
      block_number: parse_hex(raw_transfer["blockNum"]),
      from: raw_transfer["from"],
      to: raw_transfer["to"],
      value_wei: parse_value(raw_transfer),
      timestamp: parse_timestamp(raw_transfer),
      raw: raw_transfer
    }
  end

  # Private helpers

  defp parse_value(%{"rawContract" => %{"value" => value}}) when is_binary(value) do
    case parse_hex(value) do
      nil -> nil
      int -> Decimal.new(int)
    end
  end

  defp parse_value(_), do: nil

  defp parse_timestamp(%{"metadata" => %{"blockTimestamp" => ts}}) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, datetime, _} -> DateTime.truncate(datetime, :second)
      _ -> nil
    end
  end

  defp parse_timestamp(_), do: nil
end
