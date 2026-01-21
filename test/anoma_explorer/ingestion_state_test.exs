defmodule AnomaExplorer.IngestionStateTest do
  use AnomaExplorer.DataCase, async: true

  alias AnomaExplorer.Ingestion
  alias AnomaExplorer.Ingestion.IngestionState

  @valid_attrs %{
    network: "eth-mainnet",
    contract_address: "0x742d35cc6634c0532925a3b844bc9e7595f0ab12"
  }

  describe "ingestion_state schema" do
    test "valid attributes create changeset" do
      changeset = IngestionState.changeset(%IngestionState{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires network" do
      attrs = Map.delete(@valid_attrs, :network)
      changeset = IngestionState.changeset(%IngestionState{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).network
    end

    test "requires contract_address" do
      attrs = Map.delete(@valid_attrs, :contract_address)
      changeset = IngestionState.changeset(%IngestionState{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).contract_address
    end

    test "allows nil block numbers" do
      changeset = IngestionState.changeset(%IngestionState{}, @valid_attrs)
      assert changeset.valid?
      assert get_field(changeset, :last_seen_block_tx) == nil
      assert get_field(changeset, :last_seen_block_logs) == nil
    end

    test "accepts block numbers" do
      attrs = Map.merge(@valid_attrs, %{last_seen_block_tx: 100, last_seen_block_logs: 200})
      changeset = IngestionState.changeset(%IngestionState{}, attrs)
      assert changeset.valid?
    end
  end

  describe "get_or_create_state/2" do
    test "creates new state if not exists" do
      {:ok, state} =
        Ingestion.get_or_create_state("eth-mainnet", "0x742d35cc6634c0532925a3b844bc9e7595f0ab12")

      assert state.network == "eth-mainnet"
      assert state.contract_address == "0x742d35cc6634c0532925a3b844bc9e7595f0ab12"
      assert state.last_seen_block_tx == nil
      assert state.last_seen_block_logs == nil
    end

    test "returns existing state" do
      {:ok, state1} =
        Ingestion.get_or_create_state("eth-mainnet", "0x742d35cc6634c0532925a3b844bc9e7595f0ab12")

      {:ok, state2} =
        Ingestion.get_or_create_state("eth-mainnet", "0x742d35cc6634c0532925a3b844bc9e7595f0ab12")

      assert state1.id == state2.id
    end
  end

  describe "unique constraint" do
    test "network + contract_address must be unique" do
      {:ok, _} =
        Ingestion.get_or_create_state("eth-mainnet", "0x742d35cc6634c0532925a3b844bc9e7595f0ab12")

      # Direct insert should fail
      changeset = IngestionState.changeset(%IngestionState{}, @valid_attrs)
      assert {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).network
    end

    test "different networks allow same contract" do
      {:ok, _} =
        Ingestion.get_or_create_state("eth-mainnet", "0x742d35cc6634c0532925a3b844bc9e7595f0ab12")

      {:ok, state2} =
        Ingestion.get_or_create_state(
          "polygon-mainnet",
          "0x742d35cc6634c0532925a3b844bc9e7595f0ab12"
        )

      assert state2.network == "polygon-mainnet"
    end
  end

  describe "update_state/2" do
    test "updates last_seen_block_tx" do
      {:ok, state} =
        Ingestion.get_or_create_state("eth-mainnet", "0x742d35cc6634c0532925a3b844bc9e7595f0ab12")

      {:ok, updated} = Ingestion.update_state(state, %{last_seen_block_tx: 12345})
      assert updated.last_seen_block_tx == 12345
    end

    test "updates last_seen_block_logs" do
      {:ok, state} =
        Ingestion.get_or_create_state("eth-mainnet", "0x742d35cc6634c0532925a3b844bc9e7595f0ab12")

      {:ok, updated} = Ingestion.update_state(state, %{last_seen_block_logs: 67890})
      assert updated.last_seen_block_logs == 67890
    end

    test "updates both block numbers" do
      {:ok, state} =
        Ingestion.get_or_create_state("eth-mainnet", "0x742d35cc6634c0532925a3b844bc9e7595f0ab12")

      {:ok, updated} =
        Ingestion.update_state(state, %{last_seen_block_tx: 100, last_seen_block_logs: 200})

      assert updated.last_seen_block_tx == 100
      assert updated.last_seen_block_logs == 200
    end
  end

  describe "get_state/2" do
    test "returns nil if not exists" do
      assert Ingestion.get_state("eth-mainnet", "0x0000000000000000000000000000000000000000") ==
               nil
    end

    test "returns state if exists" do
      {:ok, _} =
        Ingestion.get_or_create_state("eth-mainnet", "0x742d35cc6634c0532925a3b844bc9e7595f0ab12")

      state = Ingestion.get_state("eth-mainnet", "0x742d35cc6634c0532925a3b844bc9e7595f0ab12")
      assert state.network == "eth-mainnet"
    end
  end
end
