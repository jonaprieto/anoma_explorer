defmodule AnomaExplorerWeb.ActivityLiveTest do
  use AnomaExplorerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AnomaExplorer.Activity

  @contract "0x742d35cc6634c0532925a3b844bc9e7595f0ab12"

  setup do
    # Create some test activities
    {:ok, a1} =
      Activity.create_activity(%{
        network: "eth-mainnet",
        contract_address: @contract,
        kind: "log",
        tx_hash: "0xtx1",
        block_number: 100,
        log_index: 0,
        raw: %{}
      })

    {:ok, a2} =
      Activity.create_activity(%{
        network: "eth-mainnet",
        contract_address: @contract,
        kind: "tx",
        tx_hash: "0xtx2",
        block_number: 200,
        raw: %{}
      })

    {:ok, a3} =
      Activity.create_activity(%{
        network: "base-mainnet",
        contract_address: @contract,
        kind: "log",
        tx_hash: "0xtx3",
        block_number: 300,
        log_index: 1,
        raw: %{}
      })

    %{activities: [a1, a2, a3]}
  end

  describe "activity feed" do
    test "renders activity list", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/activity")

      assert html =~ "Activity Feed"
      assert html =~ "0xtx1"
      assert html =~ "0xtx2"
      assert html =~ "0xtx3"
    end

    test "shows block numbers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity")

      assert html =~ "100"
      assert html =~ "200"
      assert html =~ "300"
    end

    test "shows network badges", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity")

      assert html =~ "eth-mainnet"
      assert html =~ "base-mainnet"
    end

    test "shows kind badges", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity")

      assert html =~ "log"
      assert html =~ "tx"
    end
  end

  describe "filtering" do
    test "filters by network", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity")

      # Filter by eth-mainnet
      html =
        view
        |> element("form")
        |> render_change(%{"filter" => %{"network" => "eth-mainnet"}})

      assert html =~ "0xtx1"
      assert html =~ "0xtx2"
      refute html =~ "0xtx3"
    end

    test "filters by kind", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity")

      # Filter by log
      html =
        view
        |> element("form")
        |> render_change(%{"filter" => %{"kind" => "log"}})

      assert html =~ "0xtx1"
      refute html =~ "0xtx2"
      assert html =~ "0xtx3"
    end

    test "clears filters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity?network=eth-mainnet")

      html =
        view
        |> element("a", "Clear filters")
        |> render_click()

      assert html =~ "0xtx1"
      assert html =~ "0xtx2"
      assert html =~ "0xtx3"
    end
  end

  describe "realtime updates" do
    test "receives new activity via PubSub", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity")

      # Simulate broadcasting a new activity to the general topic
      new_activity = %{
        id: 999,
        network: "polygon-mainnet",
        contract_address: @contract,
        kind: "transfer",
        tx_hash: "0xnew_tx",
        block_number: 400,
        inserted_at: DateTime.utc_now()
      }

      # Broadcast to the general activities topic that LiveView subscribes to
      Phoenix.PubSub.broadcast(
        AnomaExplorer.PubSub,
        "activities:new",
        {:new_activity, new_activity}
      )

      # Give time for the message to be processed
      Process.sleep(50)

      html = render(view)
      assert html =~ "0xnew_tx"
    end
  end
end
