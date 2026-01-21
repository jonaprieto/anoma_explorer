defmodule AnomaExplorer.AlchemyTest do
  use ExUnit.Case, async: true

  import Mox

  alias AnomaExplorer.Alchemy

  # Ensure mocks are verified
  setup :verify_on_exit!

  describe "build_request/3" do
    test "builds eth_getLogs request" do
      params = %{
        fromBlock: "0x1",
        toBlock: "0x100",
        address: "0x742d35cc6634c0532925a3b844bc9e7595f0ab12"
      }

      request = Alchemy.build_request("eth_getLogs", [params], 1)

      assert request == %{
               jsonrpc: "2.0",
               id: 1,
               method: "eth_getLogs",
               params: [params]
             }
    end

    test "builds eth_blockNumber request" do
      request = Alchemy.build_request("eth_blockNumber", [], 1)

      assert request == %{
               jsonrpc: "2.0",
               id: 1,
               method: "eth_blockNumber",
               params: []
             }
    end
  end

  describe "parse_hex/1" do
    test "parses valid hex block number" do
      assert Alchemy.parse_hex("0x1234") == 4660
    end

    test "parses zero" do
      assert Alchemy.parse_hex("0x0") == 0
    end

    test "parses large number" do
      assert Alchemy.parse_hex("0xbebc20") == 12_500_000
    end

    test "returns nil for nil input" do
      assert Alchemy.parse_hex(nil) == nil
    end

    test "returns nil for invalid hex" do
      assert Alchemy.parse_hex("invalid") == nil
    end
  end

  describe "parse_log/1" do
    test "parses log entry" do
      raw_log = %{
        "address" => "0x742d35cc6634c0532925a3b844bc9e7595f0ab12",
        "topics" => [
          "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
          "0x0000000000000000000000001234567890123456789012345678901234567890",
          "0x0000000000000000000000000987654321098765432109876543210987654321"
        ],
        "data" => "0x00000000000000000000000000000000000000000000000000000000000003e8",
        "blockNumber" => "0xbebc20",
        "transactionHash" => "0xabc123",
        "transactionIndex" => "0x5",
        "logIndex" => "0x2",
        "removed" => false
      }

      parsed =
        Alchemy.parse_log(raw_log, "eth-mainnet", "0x742d35cc6634c0532925a3b844bc9e7595f0ab12")

      assert parsed.network == "eth-mainnet"
      assert parsed.contract_address == "0x742d35cc6634c0532925a3b844bc9e7595f0ab12"
      assert parsed.kind == "log"
      assert parsed.tx_hash == "0xabc123"
      assert parsed.block_number == 12_500_000
      assert parsed.log_index == 2
      assert parsed.tx_index == 5
      assert parsed.topic0 == "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
      assert length(parsed.topics) == 3
      assert parsed.data == "0x00000000000000000000000000000000000000000000000000000000000003e8"
      assert parsed.raw == raw_log
    end

    test "handles log without topics" do
      raw_log = %{
        "address" => "0x742d35cc6634c0532925a3b844bc9e7595f0ab12",
        "topics" => [],
        "data" => "0x",
        "blockNumber" => "0x1",
        "transactionHash" => "0xdef456",
        "transactionIndex" => "0x0",
        "logIndex" => "0x0",
        "removed" => false
      }

      parsed =
        Alchemy.parse_log(raw_log, "eth-mainnet", "0x742d35cc6634c0532925a3b844bc9e7595f0ab12")

      assert parsed.topic0 == nil
      assert parsed.topics == []
    end
  end

  describe "parse_transfer/1" do
    test "parses asset transfer" do
      raw_transfer = %{
        "blockNum" => "0xbebc20",
        "hash" => "0xtx123",
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
        "metadata" => %{
          "blockTimestamp" => "2024-01-15T10:30:00.000Z"
        }
      }

      parsed = Alchemy.parse_transfer(raw_transfer, "eth-mainnet", "0xcontract")

      assert parsed.network == "eth-mainnet"
      assert parsed.contract_address == "0xcontract"
      assert parsed.kind == "transfer"
      assert parsed.tx_hash == "0xtx123"
      assert parsed.block_number == 12_500_000
      assert parsed.from == "0xsender"
      assert parsed.to == "0xreceiver"
      assert parsed.raw == raw_transfer
    end
  end

  describe "parse_response/1" do
    test "parses successful result" do
      response = %{"jsonrpc" => "2.0", "id" => 1, "result" => "0x1234"}

      assert {:ok, "0x1234"} = Alchemy.parse_response(response)
    end

    test "parses error response" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "error" => %{"code" => -32600, "message" => "Invalid request"}
      }

      assert {:error, %{"code" => -32600, "message" => "Invalid request"}} =
               Alchemy.parse_response(response)
    end

    test "handles missing result" do
      response = %{"jsonrpc" => "2.0", "id" => 1}

      assert {:error, :no_result} = Alchemy.parse_response(response)
    end
  end

  describe "to_hex_block/1" do
    test "converts integer to hex" do
      assert Alchemy.to_hex_block(12_500_000) == "0xbebc20"
    end

    test "converts zero" do
      assert Alchemy.to_hex_block(0) == "0x0"
    end

    test "passes through string" do
      assert Alchemy.to_hex_block("latest") == "latest"
      assert Alchemy.to_hex_block("0x100") == "0x100"
    end
  end
end
