defmodule AnomaExplorer.ActivityTest do
  use AnomaExplorer.DataCase, async: true

  alias AnomaExplorer.Activity
  alias AnomaExplorer.Activity.ContractActivity

  @valid_attrs %{
    network: "eth-mainnet",
    contract_address: "0x742d35cc6634c0532925a3b844bc9e7595f0ab12",
    kind: "log",
    tx_hash: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
    block_number: 12345678,
    log_index: 0,
    raw: %{"test" => "data"}
  }

  describe "contract_activity schema" do
    test "valid attributes create changeset" do
      changeset = ContractActivity.changeset(%ContractActivity{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires network" do
      attrs = Map.delete(@valid_attrs, :network)
      changeset = ContractActivity.changeset(%ContractActivity{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).network
    end

    test "requires contract_address" do
      attrs = Map.delete(@valid_attrs, :contract_address)
      changeset = ContractActivity.changeset(%ContractActivity{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).contract_address
    end

    test "requires kind" do
      attrs = Map.delete(@valid_attrs, :kind)
      changeset = ContractActivity.changeset(%ContractActivity{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).kind
    end

    test "requires tx_hash" do
      attrs = Map.delete(@valid_attrs, :tx_hash)
      changeset = ContractActivity.changeset(%ContractActivity{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).tx_hash
    end

    test "requires block_number" do
      attrs = Map.delete(@valid_attrs, :block_number)
      changeset = ContractActivity.changeset(%ContractActivity{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).block_number
    end

    test "requires raw" do
      attrs = Map.delete(@valid_attrs, :raw)
      changeset = ContractActivity.changeset(%ContractActivity{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).raw
    end

    test "validates kind is one of tx, log, transfer" do
      attrs = Map.put(@valid_attrs, :kind, "invalid")
      changeset = ContractActivity.changeset(%ContractActivity{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).kind
    end

    test "accepts valid kinds" do
      for kind <- ["tx", "log", "transfer"] do
        attrs = Map.put(@valid_attrs, :kind, kind)
        changeset = ContractActivity.changeset(%ContractActivity{}, attrs)
        assert changeset.valid?, "Kind #{kind} should be valid"
      end
    end
  end

  describe "create_activity/1" do
    test "inserts valid activity" do
      assert {:ok, activity} = Activity.create_activity(@valid_attrs)
      assert activity.network == "eth-mainnet"
      assert activity.kind == "log"
      assert activity.block_number == 12345678
    end

    test "returns error for invalid attrs" do
      assert {:error, changeset} = Activity.create_activity(%{})
      refute changeset.valid?
    end
  end

  describe "unique constraints" do
    test "tx/transfer uniqueness: same network, contract, kind, tx_hash rejects duplicate" do
      tx_attrs = %{@valid_attrs | kind: "tx", log_index: nil}
      assert {:ok, _} = Activity.create_activity(tx_attrs)
      assert {:error, changeset} = Activity.create_activity(tx_attrs)
      assert "has already been taken" in errors_on(changeset).tx_hash
    end

    test "log uniqueness: same network, contract, kind, tx_hash, log_index rejects duplicate" do
      assert {:ok, _} = Activity.create_activity(@valid_attrs)
      assert {:error, changeset} = Activity.create_activity(@valid_attrs)
      assert "has already been taken" in errors_on(changeset).log_index
    end

    test "log uniqueness: different log_index allows insert" do
      assert {:ok, _} = Activity.create_activity(@valid_attrs)
      attrs2 = Map.put(@valid_attrs, :log_index, 1)
      assert {:ok, _} = Activity.create_activity(attrs2)
    end

    test "different network allows same tx_hash" do
      assert {:ok, _} = Activity.create_activity(@valid_attrs)
      attrs2 = Map.put(@valid_attrs, :network, "polygon-mainnet")
      assert {:ok, _} = Activity.create_activity(attrs2)
    end
  end

  describe "upsert_activity/1" do
    test "inserts new activity" do
      assert {:ok, activity} = Activity.upsert_activity(@valid_attrs)
      assert activity.block_number == 12345678
    end

    test "updates existing activity on conflict" do
      assert {:ok, _} = Activity.create_activity(@valid_attrs)
      updated_attrs = Map.put(@valid_attrs, :block_number, 99999999)
      assert {:ok, activity} = Activity.upsert_activity(updated_attrs)
      assert activity.block_number == 99999999
    end
  end

  describe "list_activities/1" do
    setup do
      # Create activities in different networks and blocks
      {:ok, a1} = Activity.create_activity(%{@valid_attrs | block_number: 100, log_index: 0})
      {:ok, a2} = Activity.create_activity(%{@valid_attrs | block_number: 200, log_index: 1})
      {:ok, a3} = Activity.create_activity(%{@valid_attrs | block_number: 300, log_index: 2, network: "polygon-mainnet"})
      {:ok, a4} = Activity.create_activity(%{@valid_attrs | block_number: 400, log_index: 3, kind: "tx"})

      %{activities: [a1, a2, a3, a4]}
    end

    test "returns all activities ordered by block_number desc", %{activities: _activities} do
      results = Activity.list_activities()
      assert length(results) == 4
      # Should be ordered by block_number desc
      assert hd(results).block_number == 400
    end

    test "filters by network" do
      results = Activity.list_activities(network: "polygon-mainnet")
      assert length(results) == 1
      assert hd(results).network == "polygon-mainnet"
    end

    test "filters by kind" do
      results = Activity.list_activities(kind: "tx")
      assert length(results) == 1
      assert hd(results).kind == "tx"
    end

    test "supports limit" do
      results = Activity.list_activities(limit: 2)
      assert length(results) == 2
    end

    test "supports cursor pagination with after_id" do
      all = Activity.list_activities()
      first_id = hd(all).id

      results = Activity.list_activities(after_id: first_id)
      assert length(results) == 3
      refute first_id in Enum.map(results, & &1.id)
    end
  end
end
