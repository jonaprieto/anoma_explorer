defmodule AnomaExplorer.Ingestion.SyncTest do
  use AnomaExplorer.DataCase, async: false

  import Mox

  alias AnomaExplorer.Activity
  alias AnomaExplorer.Ingestion
  alias AnomaExplorer.Ingestion.Sync

  @network "eth-mainnet"
  @contract "0x742d35cc6634c0532925a3b844bc9e7595f0ab12"
  @api_key "test_api_key"

  setup :verify_on_exit!

  describe "sync_logs/4" do
    test "fetches logs and inserts activities" do
      # Mock: get current block number
      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, body, _headers ->
        assert body.method == "eth_blockNumber"
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0x100"}}
      end)

      # Mock: get logs (first chunk)
      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, body, _headers ->
        assert body.method == "eth_getLogs"
        [params] = body.params
        assert params.address == @contract

        {:ok, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => [
            %{
              "address" => @contract,
              "topics" => ["0xtopic0"],
              "data" => "0xdata",
              "blockNumber" => "0x50",
              "transactionHash" => "0xtx1",
              "transactionIndex" => "0x0",
              "logIndex" => "0x0",
              "removed" => false
            },
            %{
              "address" => @contract,
              "topics" => ["0xtopic1"],
              "data" => "0xdata2",
              "blockNumber" => "0x60",
              "transactionHash" => "0xtx2",
              "transactionIndex" => "0x1",
              "logIndex" => "0x1",
              "removed" => false
            }
          ]
        }}
      end)

      {:ok, state} = Ingestion.get_or_create_state(@network, @contract)
      assert state.last_seen_block_logs == nil

      {:ok, result} = Sync.sync_logs(@network, @contract, @api_key, chunk_size: 256)

      assert result.inserted_count == 2
      assert result.last_block == 256  # 0x100 = 256

      # Verify activities were inserted
      activities = Activity.list_activities(network: @network)
      assert length(activities) == 2

      # Verify state was updated
      updated_state = Ingestion.get_state(@network, @contract)
      assert updated_state.last_seen_block_logs == 256
    end

    test "resumes from last seen block" do
      # Create initial state with last_seen_block_logs
      {:ok, _state} = Ingestion.get_or_create_state(@network, @contract)
      {:ok, _state} = Ingestion.update_state(
        Ingestion.get_state(@network, @contract),
        %{last_seen_block_logs: 100}
      )

      # Mock: get current block number
      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, body, _headers ->
        assert body.method == "eth_blockNumber"
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0xc8"}}  # 200
      end)

      # Mock: get logs - should start from block 101
      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, body, _headers ->
        [params] = body.params
        # Should start from last_seen + 1
        assert params.fromBlock == "0x65"  # 101
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => []}}
      end)

      {:ok, result} = Sync.sync_logs(@network, @contract, @api_key, chunk_size: 256)

      assert result.inserted_count == 0
      assert result.last_block == 200
    end

    test "is idempotent - duplicate logs are not inserted twice" do
      log_data = %{
        "address" => @contract,
        "topics" => ["0xtopic0"],
        "data" => "0xdata",
        "blockNumber" => "0x50",
        "transactionHash" => "0xtx1",
        "transactionIndex" => "0x0",
        "logIndex" => "0x0",
        "removed" => false
      }

      # First sync
      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, _body, _headers ->
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0x100"}}
      end)

      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, _body, _headers ->
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => [log_data]}}
      end)

      {:ok, result1} = Sync.sync_logs(@network, @contract, @api_key, chunk_size: 256)
      assert result1.inserted_count == 1

      # Reset state to re-sync same range
      {:ok, _} = Ingestion.update_state(
        Ingestion.get_state(@network, @contract),
        %{last_seen_block_logs: nil}
      )

      # Second sync with same data
      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, _body, _headers ->
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0x100"}}
      end)

      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, _body, _headers ->
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => [log_data]}}
      end)

      {:ok, result2} = Sync.sync_logs(@network, @contract, @api_key, chunk_size: 256)
      # Should still "insert" 1 (upsert), but not create duplicate
      assert result2.inserted_count == 1

      # Verify only 1 activity exists
      activities = Activity.list_activities(network: @network)
      assert length(activities) == 1
    end

    test "handles empty logs response" do
      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, _body, _headers ->
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0x100"}}
      end)

      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, _body, _headers ->
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => []}}
      end)

      {:ok, result} = Sync.sync_logs(@network, @contract, @api_key, chunk_size: 256)

      assert result.inserted_count == 0
      assert result.last_block == 256
    end

    test "handles API error gracefully" do
      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, _body, _headers ->
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0x100"}}
      end)

      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, _body, _headers ->
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "error" => %{"code" => -32600, "message" => "Invalid"}}}
      end)

      {:error, _reason} = Sync.sync_logs(@network, @contract, @api_key, chunk_size: 256)

      # State should not be updated on error
      state = Ingestion.get_state(@network, @contract)
      assert state == nil || state.last_seen_block_logs == nil
    end
  end

  describe "sync_logs/4 with backfill" do
    test "uses backfill_blocks when no start_block and no state" do
      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, body, _headers ->
        assert body.method == "eth_blockNumber"
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0xc350"}}  # 50000
      end)

      expect(AnomaExplorer.HTTPClientMock, :post, fn _url, body, _headers ->
        [params] = body.params
        # With backfill_blocks: 1000, should start at 50000 - 1000 = 49000 = 0xbf68
        assert params.fromBlock == "0xbf68"
        {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => []}}
      end)

      {:ok, result} = Sync.sync_logs(@network, @contract, @api_key, backfill_blocks: 1000, chunk_size: 5000)

      assert result.last_block == 50000
    end
  end
end
