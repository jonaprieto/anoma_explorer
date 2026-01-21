defmodule AnomaExplorer.Workers.IngestionWorkerTest do
  use AnomaExplorer.DataCase, async: false
  use Oban.Testing, repo: AnomaExplorer.Repo

  import Mox

  alias AnomaExplorer.Workers.IngestionWorker

  @network "eth-mainnet"
  @contract "0x742d35cc6634c0532925a3b844bc9e7595f0ab12"

  setup :verify_on_exit!

  describe "perform/1" do
    test "successfully syncs logs for a network" do
      stub(AnomaExplorer.HTTPClientMock, :post, fn _url, body, _headers ->
        case body.method do
          "eth_blockNumber" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0x100"}}

          "eth_getLogs" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => []}}
        end
      end)

      args = %{
        "network" => @network,
        "contract_address" => @contract,
        "api_key" => "test_key"
      }

      assert :ok = perform_job(IngestionWorker, args)
    end

    test "returns error tuple on API failure" do
      stub(AnomaExplorer.HTTPClientMock, :post, fn _url, _body, _headers ->
        {:error, :timeout}
      end)

      args = %{
        "network" => @network,
        "contract_address" => @contract,
        "api_key" => "test_key"
      }

      assert {:error, :timeout} = perform_job(IngestionWorker, args)
    end
  end

  describe "new/1 job creation" do
    test "creates a job changeset with correct args" do
      job_changeset =
        IngestionWorker.new(%{
          "network" => @network,
          "contract_address" => @contract,
          "api_key" => "test_key",
          "poll_interval" => 20
        })

      assert job_changeset.valid?
      assert job_changeset.changes.args["network"] == @network
      assert job_changeset.changes.args["contract_address"] == @contract
      assert job_changeset.changes.queue == "ingestion"
    end
  end

  describe "enqueue_for_network/4" do
    test "creates and inserts job successfully" do
      stub(AnomaExplorer.HTTPClientMock, :post, fn _url, body, _headers ->
        case body.method do
          "eth_blockNumber" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0x100"}}

          "eth_getLogs" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => []}}
        end
      end)

      # With inline mode, jobs are executed immediately
      # We just verify the insert returns successfully
      result =
        IngestionWorker.enqueue_for_network(
          @network,
          @contract,
          "test_key",
          poll_interval: 20
        )

      assert {:ok, %Oban.Job{}} = result
    end
  end

  describe "schedule_all_networks/3" do
    test "creates jobs for all networks" do
      stub(AnomaExplorer.HTTPClientMock, :post, fn _url, body, _headers ->
        case body.method do
          "eth_blockNumber" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0x100"}}

          "eth_getLogs" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => []}}
        end
      end)

      networks = ["eth-mainnet", "polygon-mainnet", "arb-mainnet"]

      results = IngestionWorker.schedule_all_networks(networks, @contract, "test_key")

      # All should succeed
      assert length(results) == 3

      assert Enum.all?(results, fn
               {:ok, %Oban.Job{}} -> true
               _ -> false
             end)
    end
  end
end
