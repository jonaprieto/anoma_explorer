defmodule AnomaExplorer.AlchemyClientTest do
  use ExUnit.Case, async: true

  import Mox

  alias AnomaExplorer.Alchemy

  setup :verify_on_exit!

  describe "get_block_number/2" do
    test "returns parsed block number on success" do
      expect(AnomaExplorer.HTTPClientMock, :post, fn url, body, _headers ->
        assert String.contains?(url, "eth-mainnet.g.alchemy.com")
        assert body.method == "eth_blockNumber"

        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0xbebc20"}}
      end)

      assert {:ok, 12_500_000} = Alchemy.get_block_number("eth-mainnet", "test_key")
    end

    test "returns error on RPC error" do
      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, _body, _headers ->
        {:ok,
         %{"jsonrpc" => "2.0", "id" => 1, "error" => %{"code" => -32600, "message" => "Invalid"}}}
      end)

      assert {:error, %{"code" => -32600}} = Alchemy.get_block_number("eth-mainnet", "test_key")
    end

    test "returns error on HTTP failure" do
      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, _body, _headers ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Alchemy.get_block_number("eth-mainnet", "test_key")
    end
  end

  describe "get_logs/5" do
    test "returns parsed logs on success" do
      expect(AnomaExplorer.HTTPClientMock, :post, fn url, body, _headers ->
        assert String.contains?(url, "polygon-mainnet.g.alchemy.com")
        assert body.method == "eth_getLogs"
        [params] = body.params
        assert params.fromBlock == "0x1"
        assert params.toBlock == "0x100"
        assert params.address == "0xcontract"

        {:ok,
         %{
           "jsonrpc" => "2.0",
           "id" => 1,
           "result" => [
             %{
               "address" => "0xcontract",
               "topics" => ["0xtopic0"],
               "data" => "0xdata",
               "blockNumber" => "0x64",
               "transactionHash" => "0xtx1",
               "transactionIndex" => "0x0",
               "logIndex" => "0x0",
               "removed" => false
             },
             %{
               "address" => "0xcontract",
               "topics" => ["0xtopic0", "0xtopic1"],
               "data" => "0xdata2",
               "blockNumber" => "0x65",
               "transactionHash" => "0xtx2",
               "transactionIndex" => "0x1",
               "logIndex" => "0x3",
               "removed" => false
             }
           ]
         }}
      end)

      assert {:ok, logs} = Alchemy.get_logs("polygon-mainnet", "test_key", "0xcontract", 1, 256)

      assert length(logs) == 2

      [log1, log2] = logs

      assert log1.network == "polygon-mainnet"
      assert log1.contract_address == "0xcontract"
      assert log1.kind == "log"
      assert log1.block_number == 100
      assert log1.tx_hash == "0xtx1"
      assert log1.log_index == 0

      assert log2.block_number == 101
      assert log2.log_index == 3
      assert length(log2.topics) == 2
    end

    test "returns empty list when no logs" do
      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, _body, _headers ->
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => []}}
      end)

      assert {:ok, []} = Alchemy.get_logs("eth-mainnet", "test_key", "0xcontract", 1, 100)
    end
  end

  describe "get_asset_transfers/6" do
    test "returns parsed transfers with page key" do
      expect(AnomaExplorer.HTTPClientMock, :post, fn url, body, _headers ->
        assert String.contains?(url, "base-mainnet.g.alchemy.com")
        assert body.method == "alchemy_getAssetTransfers"

        {:ok,
         %{
           "jsonrpc" => "2.0",
           "id" => 1,
           "result" => %{
             "transfers" => [
               %{
                 "blockNum" => "0xbebc20",
                 "hash" => "0xtx1",
                 "from" => "0xsender",
                 "to" => "0xreceiver",
                 "value" => 1.5,
                 "asset" => "ETH",
                 "category" => "external",
                 "rawContract" => %{
                   "value" => "0x14d1120d7b160000",
                   "address" => nil,
                   "decimal" => "0x12"
                 },
                 "metadata" => %{"blockTimestamp" => "2024-01-15T10:30:00.000Z"}
               }
             ],
             "pageKey" => "next_page_token"
           }
         }}
      end)

      assert {:ok, transfers, page_key} =
               Alchemy.get_asset_transfers(
                 "base-mainnet",
                 "test_key",
                 "0xcontract",
                 1,
                 12_500_000
               )

      assert length(transfers) == 1
      assert page_key == "next_page_token"

      [transfer] = transfers
      assert transfer.network == "base-mainnet"
      assert transfer.kind == "transfer"
      assert transfer.block_number == 12_500_000
      assert transfer.from == "0xsender"
      assert transfer.to == "0xreceiver"
    end

    test "passes page_key option for pagination" do
      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, body, _headers ->
        [params] = body.params
        assert params.pageKey == "my_page_key"

        {:ok,
         %{
           "jsonrpc" => "2.0",
           "id" => 1,
           "result" => %{"transfers" => [], "pageKey" => nil}
         }}
      end)

      assert {:ok, [], nil} =
               Alchemy.get_asset_transfers("eth-mainnet", "test_key", "0xcontract", 1, 100,
                 page_key: "my_page_key"
               )
    end
  end
end
