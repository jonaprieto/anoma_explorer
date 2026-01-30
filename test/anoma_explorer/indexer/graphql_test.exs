defmodule AnomaExplorer.Indexer.GraphQLTest do
  @moduledoc """
  Tests for the GraphQL client that queries the Envio Hyperindex endpoint.
  """
  use AnomaExplorer.DataCase, async: false

  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Settings.AppSetting
  alias AnomaExplorer.Settings.Cache, as: SettingsCache

  import Mox

  # Ensure Mox verifications happen at the end of each test
  setup :verify_on_exit!

  setup do
    # Configure to use mock HTTP client
    Application.put_env(:anoma_explorer, :graphql_http_client, AnomaExplorer.GraphQLHTTPClientMock)

    # Clear the cache before each test to avoid interference
    case GenServer.whereis(AnomaExplorer.Indexer.Cache) do
      nil -> :ok
      _pid -> AnomaExplorer.Indexer.Cache.clear()
    end

    on_exit(fn ->
      Application.delete_env(:anoma_explorer, :graphql_http_client)
    end)

    :ok
  end

  describe "get_stats/0" do
    test "returns aggregated statistics when response is successful" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:ok,
         %{
           "transactions" => [%{"id" => "1"}, %{"id" => "2"}],
           "resources" => [
             %{"id" => "r1", "isConsumed" => true},
             %{"id" => "r2", "isConsumed" => false},
             %{"id" => "r3", "isConsumed" => false}
           ],
           "actions" => [%{"id" => "a1"}],
           "compliances" => [%{"id" => "c1"}, %{"id" => "c2"}],
           "logics" => [%{"id" => "l1"}]
         }}
      end)

      assert {:ok, stats} = GraphQL.get_stats()
      assert stats.transactions == 2
      assert stats.resources == 3
      assert stats.consumed == 1
      assert stats.created == 2
      assert stats.actions == 1
      assert stats.compliances == 2
      assert stats.logics == 1
    end

    test "returns error when not configured" do
      clear_envio_url()

      assert {:error, :not_configured} = GraphQL.get_stats()
    end

    test "handles empty response gracefully" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:ok,
         %{
           "transactions" => [],
           "resources" => [],
           "actions" => [],
           "compliances" => [],
           "logics" => []
         }}
      end)

      assert {:ok, stats} = GraphQL.get_stats()
      assert stats.transactions == 0
      assert stats.resources == 0
      assert stats.consumed == 0
      assert stats.created == 0
      assert stats.actions == 0
      assert stats.compliances == 0
      assert stats.logics == 0
    end

    test "handles nil fields in response" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:ok,
         %{
           "transactions" => nil,
           "resources" => nil,
           "actions" => nil,
           "compliances" => nil,
           "logics" => nil
         }}
      end)

      assert {:ok, stats} = GraphQL.get_stats()
      assert stats.transactions == 0
      assert stats.resources == 0
    end
  end

  describe "list_transactions/1" do
    test "returns list of transactions with default pagination" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:ok,
         %{
           "Transaction" => [
             %{
               "id" => "tx1",
               "txHash" => "0xabc123",
               "blockNumber" => 1000,
               "timestamp" => 1_700_000_000,
               "chainId" => 1,
               "tags" => ["tag1"],
               "logicRefs" => ["ref1"]
             }
           ]
         }}
      end)

      assert {:ok, transactions} = GraphQL.list_transactions()
      assert length(transactions) == 1
      assert hd(transactions)["txHash"] == "0xabc123"
    end

    test "applies tx_hash filter correctly" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        assert query =~ "txHash: {_ilike:"
        assert query =~ "abc123"
        {:ok, %{"Transaction" => []}}
      end)

      assert {:ok, []} = GraphQL.list_transactions(tx_hash: "abc123")
    end

    test "applies chain_id filter correctly" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        assert query =~ "chainId: {_eq: 42_161}"
        {:ok, %{"Transaction" => []}}
      end)

      assert {:ok, []} = GraphQL.list_transactions(chain_id: 42161)
    end

    test "applies block range filters" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        assert query =~ "blockNumber: {_gte: 100}"
        assert query =~ "blockNumber: {_lte: 200}"
        {:ok, %{"Transaction" => []}}
      end)

      assert {:ok, []} = GraphQL.list_transactions(block_min: 100, block_max: 200)
    end

    test "returns empty list when no transactions found" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:ok, %{"Transaction" => []}}
      end)

      assert {:ok, []} = GraphQL.list_transactions()
    end

    test "handles missing Transaction key" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:ok, %{}}
      end)

      assert {:ok, []} = GraphQL.list_transactions()
    end

    test "applies pagination correctly" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        assert query =~ "limit: 50"
        assert query =~ "offset: 100"
        {:ok, %{"Transaction" => []}}
      end)

      assert {:ok, []} = GraphQL.list_transactions(limit: 50, offset: 100)
    end
  end

  describe "get_transaction/1" do
    test "returns transaction with related data" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:ok,
         %{
           "Transaction" => [
             %{
               "id" => "tx1",
               "txHash" => "0xfull",
               "blockNumber" => 1000,
               "timestamp" => 1_700_000_000,
               "chainId" => 1,
               "contractAddress" => "0xcontract",
               "tags" => ["tag1", "tag2"],
               "logicRefs" => ["ref1", "ref2"],
               "resources" => [
                 %{"id" => "r1", "tag" => "resource_tag", "isConsumed" => false}
               ],
               "actions" => [
                 %{"id" => "a1", "actionTreeRoot" => "0xroot", "tagCount" => 2}
               ]
             }
           ]
         }}
      end)

      assert {:ok, tx} = GraphQL.get_transaction("tx1")
      assert tx["txHash"] == "0xfull"
      assert length(tx["resources"]) == 1
      assert length(tx["actions"]) == 1
    end

    test "returns not_found when transaction doesn't exist" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:ok, %{"Transaction" => []}}
      end)

      assert {:error, :not_found} = GraphQL.get_transaction("nonexistent")
    end
  end

  describe "list_resources/1" do
    test "returns list of resources" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:ok,
         %{
           "Resource" => [
             %{
               "id" => "r1",
               "tag" => "0xtag",
               "isConsumed" => false,
               "blockNumber" => 1000,
               "chainId" => 1,
               "logicRef" => "0xlogic",
               "quantity" => 100,
               "decodingStatus" => "success",
               "transaction" => %{"id" => "tx1", "txHash" => "0xhash"}
             }
           ]
         }}
      end)

      assert {:ok, resources} = GraphQL.list_resources()
      assert length(resources) == 1
      assert hd(resources)["tag"] == "0xtag"
    end

    test "applies is_consumed filter" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        assert query =~ "isConsumed: {_eq: true}"
        {:ok, %{"Resource" => []}}
      end)

      assert {:ok, []} = GraphQL.list_resources(is_consumed: true)
    end

    test "applies tag filter" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        assert query =~ "tag: {_ilike:"
        {:ok, %{"Resource" => []}}
      end)

      assert {:ok, []} = GraphQL.list_resources(tag: "test_tag")
    end

    test "applies decoding_status filter" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        assert query =~ "decodingStatus: {_eq: \"success\"}"
        {:ok, %{"Resource" => []}}
      end)

      assert {:ok, []} = GraphQL.list_resources(decoding_status: "success")
    end
  end

  describe "list_actions/1" do
    test "returns list of actions" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:ok,
         %{
           "Action" => [
             %{
               "id" => "a1",
               "actionTreeRoot" => "0xroot",
               "tagCount" => 5,
               "blockNumber" => 1000,
               "chainId" => 1,
               "timestamp" => 1_700_000_000,
               "transaction" => %{"id" => "tx1", "txHash" => "0xhash"}
             }
           ]
         }}
      end)

      assert {:ok, actions} = GraphQL.list_actions()
      assert length(actions) == 1
      assert hd(actions)["tagCount"] == 5
    end

    test "applies action_tree_root filter" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        assert query =~ "actionTreeRoot: {_ilike:"
        {:ok, %{"Action" => []}}
      end)

      assert {:ok, []} = GraphQL.list_actions(action_tree_root: "0xroot")
    end
  end

  describe "list_compliance_units/1" do
    test "returns list of compliance units" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:ok,
         %{
           "ComplianceUnit" => [
             %{
               "id" => "cu1",
               "index" => 0,
               "consumedNullifier" => "0xnull",
               "createdCommitment" => "0xcommit",
               "consumedLogicRef" => "0xconsumed",
               "createdLogicRef" => "0xcreated",
               "unitDeltaX" => "100",
               "unitDeltaY" => "200",
               "action" => %{
                 "id" => "a1",
                 "blockNumber" => 1000,
                 "chainId" => 1,
                 "timestamp" => 1_700_000_000,
                 "transaction" => %{"id" => "tx1", "txHash" => "0xhash"}
               }
             }
           ]
         }}
      end)

      assert {:ok, units} = GraphQL.list_compliance_units()
      assert length(units) == 1
      assert hd(units)["consumedNullifier"] == "0xnull"
    end

    test "applies nullifier filter" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        assert query =~ "consumedNullifier: {_ilike:"
        {:ok, %{"ComplianceUnit" => []}}
      end)

      assert {:ok, []} = GraphQL.list_compliance_units(nullifier: "0xnull")
    end
  end

  describe "list_nullifiers/1" do
    test "returns list of nullifiers from compliance units" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        assert query =~ "consumedNullifier: {_is_null: false}"

        {:ok,
         %{
           "ComplianceUnit" => [
             %{
               "id" => "cu1",
               "consumedNullifier" => "0xnull1",
               "consumedLogicRef" => "0xlogic",
               "action" => %{"id" => "a1"}
             }
           ]
         }}
      end)

      assert {:ok, nullifiers} = GraphQL.list_nullifiers()
      assert length(nullifiers) == 1
    end
  end

  describe "list_commitments/1" do
    test "returns list of commitments from compliance units" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        assert query =~ "createdCommitment: {_is_null: false}"

        {:ok,
         %{
           "ComplianceUnit" => [
             %{
               "id" => "cu1",
               "createdCommitment" => "0xcommit1",
               "createdLogicRef" => "0xlogic",
               "action" => %{"id" => "a1"}
             }
           ]
         }}
      end)

      assert {:ok, commitments} = GraphQL.list_commitments()
      assert length(commitments) == 1
    end
  end

  describe "error handling" do
    test "handles GraphQL errors in response" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:error, {:graphql_error, [%{"message" => "Field 'invalid' not found"}]}}
      end)

      assert {:error, {:graphql_error, _}} = GraphQL.get_stats()
    end

    test "handles HTTP errors" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:error, {:http_error, 500, "Internal Server Error"}}
      end)

      assert {:error, {:http_error, 500, _}} = GraphQL.get_stats()
    end

    test "handles connection errors" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:error, {:connection_error, :timeout}}
      end)

      assert {:error, {:connection_error, :timeout}} = GraphQL.get_stats()
    end

    test "handles decode errors" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, _query, _timeout, _connect_timeout ->
        {:error, {:decode_error, %Jason.DecodeError{}}}
      end)

      assert {:error, {:decode_error, _}} = GraphQL.get_stats()
    end
  end

  describe "execute_raw/1" do
    test "returns full response including data" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql_raw, fn _url, _query, _timeout, _connect_timeout ->
        {:ok, %{"data" => %{"__schema" => %{"types" => []}}}}
      end)

      assert {:ok, response} = GraphQL.execute_raw("{ __schema { types { name } } }")
      assert Map.has_key?(response, "data")
    end

    test "returns response with errors if present" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql_raw, fn _url, _query, _timeout, _connect_timeout ->
        {:ok, %{"data" => nil, "errors" => [%{"message" => "Syntax error"}]}}
      end)

      assert {:ok, response} = GraphQL.execute_raw("invalid query")
      assert Map.has_key?(response, "errors")
    end

    test "returns error when not configured" do
      clear_envio_url()

      assert {:error, :not_configured} = GraphQL.execute_raw("{ test }")
    end
  end

  describe "string escaping" do
    test "escapes special characters in filter values" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        # Verify quotes are escaped
        assert query =~ "\\\""
        {:ok, %{"Transaction" => []}}
      end)

      assert {:ok, []} = GraphQL.list_transactions(tx_hash: ~s(test"value))
    end

    test "escapes SQL LIKE wildcards" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        # % and _ should be escaped
        assert query =~ "\\%"
        assert query =~ "\\_"
        {:ok, %{"Transaction" => []}}
      end)

      assert {:ok, []} = GraphQL.list_transactions(tx_hash: "test%_value")
    end

    test "escapes backslashes" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        # Backslashes should be escaped
        assert query =~ "\\\\"
        {:ok, %{"Transaction" => []}}
      end)

      assert {:ok, []} = GraphQL.list_transactions(tx_hash: "test\\value")
    end

    test "escapes newlines and tabs" do
      insert_envio_url("https://test.envio.dev/graphql")

      AnomaExplorer.GraphQLHTTPClientMock
      |> expect(:post_graphql, fn _url, query, _timeout, _connect_timeout ->
        assert query =~ "\\n"
        assert query =~ "\\t"
        {:ok, %{"Transaction" => []}}
      end)

      assert {:ok, []} = GraphQL.list_transactions(tx_hash: "test\n\tvalue")
    end
  end

  # Helper functions

  defp insert_envio_url(url) do
    setting =
      Repo.insert!(
        %AppSetting{key: "envio_graphql_url", value: url},
        on_conflict: {:replace, [:value]},
        conflict_target: :key
      )

    SettingsCache.put_app_setting("envio_graphql_url", url)
    setting
  end

  defp clear_envio_url do
    Repo.delete_all(AppSetting)
    SettingsCache.delete_app_setting("envio_graphql_url")
    Application.delete_env(:anoma_explorer, :envio_graphql_url)
  end
end
