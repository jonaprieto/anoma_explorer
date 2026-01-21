defmodule AnomaExplorerWeb.AnalyticsLiveTest do
  use AnomaExplorerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AnomaExplorer.Activity.ContractActivity
  alias AnomaExplorer.Repo

  @contract "0x742d35cc6634c0532925a3b844bc9e7595f0ab12"

  setup do
    # Create test activities
    today = Date.utc_today()
    yesterday = Date.add(today, -1)

    create_activity("eth-mainnet", today, "log")
    create_activity("eth-mainnet", today, "tx")
    create_activity("base-mainnet", yesterday, "log")

    :ok
  end

  describe "analytics dashboard" do
    test "renders dashboard with stats", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/analytics")

      assert html =~ "Analytics Dashboard"
      assert html =~ "Total Activities"
      assert html =~ "Active Networks"
      assert html =~ "Activity Types"
      assert html =~ "Avg per Day"
    end

    test "shows daily activity chart", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/analytics")

      assert html =~ "Daily Activity"
    end

    test "shows activity by type", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/analytics")

      assert html =~ "Activity by Type"
    end

    test "shows activity by network", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/analytics")

      assert html =~ "Activity by Network"
      assert html =~ "eth-mainnet"
      assert html =~ "base-mainnet"
    end
  end

  describe "filtering" do
    test "filters by network", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analytics")

      html =
        view
        |> element("form[phx-change=change_network]")
        |> render_change(%{"network" => "eth-mainnet"})

      # After filtering, stats should update
      assert html =~ "eth-mainnet"
    end

    test "changes time period", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analytics")

      html =
        view
        |> element("form[phx-change=change_days]")
        |> render_change(%{"days" => "7"})

      assert html =~ "Last 7 days"
    end
  end

  describe "URL params" do
    test "loads with days param", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/analytics?days=7")

      # The 7 days option should be selected
      assert html =~ "Last 7 days"
      assert html =~ ~s(selected)
    end

    test "loads with network param", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/analytics?network=eth-mainnet")

      assert html =~ "eth-mainnet"
    end
  end

  # Helper to create activity with specific date
  defp create_activity(network, date, kind) do
    datetime = DateTime.new!(date, ~T[12:00:00], "Etc/UTC")

    %ContractActivity{
      network: network,
      contract_address: @contract,
      kind: kind,
      tx_hash: "0x#{:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)}",
      block_number: :rand.uniform(1_000_000),
      log_index: if(kind == "log", do: 0, else: nil),
      raw: %{},
      inserted_at: datetime,
      updated_at: datetime
    }
    |> Repo.insert!()
  end
end
