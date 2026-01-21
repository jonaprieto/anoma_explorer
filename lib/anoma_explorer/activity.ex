defmodule AnomaExplorer.Activity do
  @moduledoc """
  Context module for managing contract activity records.

  Provides functions for creating, querying, and upserting activity data.
  """
  import Ecto.Query

  alias AnomaExplorer.Repo
  alias AnomaExplorer.Activity.ContractActivity

  @doc """
  Creates a new contract activity record.
  """
  @spec create_activity(map()) :: {:ok, ContractActivity.t()} | {:error, Ecto.Changeset.t()}
  def create_activity(attrs) do
    %ContractActivity{}
    |> ContractActivity.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Upserts a contract activity record.

  On conflict, updates all fields except the unique key fields.
  """
  @spec upsert_activity(map()) :: {:ok, ContractActivity.t()} | {:error, Ecto.Changeset.t()}
  def upsert_activity(attrs) do
    changeset = ContractActivity.changeset(%ContractActivity{}, attrs)

    conflict_target =
      if attrs[:log_index] || attrs["log_index"] do
        {:unsafe_fragment, "(network, contract_address, kind, tx_hash, log_index) WHERE log_index IS NOT NULL"}
      else
        {:unsafe_fragment, "(network, contract_address, kind, tx_hash) WHERE log_index IS NULL"}
      end

    Repo.insert(changeset,
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: conflict_target,
      returning: true
    )
  end

  @doc """
  Upserts multiple activity records in a single transaction.

  Returns the count of records inserted/updated.
  """
  @spec upsert_activities([map()]) :: {:ok, integer()} | {:error, term()}
  def upsert_activities(activities) when is_list(activities) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(activities, fn attrs ->
        attrs
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    {count, _} =
      Repo.insert_all(
        ContractActivity,
        entries,
        on_conflict: {:replace_all_except, [:id, :inserted_at]},
        conflict_target: {:unsafe_fragment, "(network, contract_address, kind, tx_hash, log_index) WHERE log_index IS NOT NULL"}
      )

    {:ok, count}
  end

  @doc """
  Lists contract activities with optional filters and pagination.

  ## Options
    * `:network` - Filter by network
    * `:kind` - Filter by kind (tx, log, transfer)
    * `:contract_address` - Filter by contract address
    * `:limit` - Maximum number of results (default 50)
    * `:after_id` - Cursor for pagination (return records after this ID)
  """
  @spec list_activities(keyword()) :: [ContractActivity.t()]
  def list_activities(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    ContractActivity
    |> apply_filters(opts)
    |> order_by([a], desc: a.block_number, desc: a.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a single activity by ID.
  """
  @spec get_activity(integer()) :: ContractActivity.t() | nil
  def get_activity(id), do: Repo.get(ContractActivity, id)

  @doc """
  Counts activities matching the given filters.
  """
  @spec count_activities(keyword()) :: integer()
  def count_activities(opts \\ []) do
    ContractActivity
    |> apply_filters(opts)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets the latest block number for a given network and contract.
  """
  @spec get_latest_block(String.t(), String.t(), String.t()) :: integer() | nil
  def get_latest_block(network, contract_address, kind) do
    ContractActivity
    |> where([a], a.network == ^network)
    |> where([a], a.contract_address == ^contract_address)
    |> where([a], a.kind == ^kind)
    |> select([a], max(a.block_number))
    |> Repo.one()
  end

  # Private helpers

  defp apply_filters(query, opts) do
    query
    |> filter_by_network(opts[:network])
    |> filter_by_kind(opts[:kind])
    |> filter_by_contract(opts[:contract_address])
    |> filter_by_after_id(opts[:after_id])
  end

  defp filter_by_network(query, nil), do: query
  defp filter_by_network(query, network), do: where(query, [a], a.network == ^network)

  defp filter_by_kind(query, nil), do: query
  defp filter_by_kind(query, kind), do: where(query, [a], a.kind == ^kind)

  defp filter_by_contract(query, nil), do: query
  defp filter_by_contract(query, addr), do: where(query, [a], a.contract_address == ^addr)

  defp filter_by_after_id(query, nil), do: query

  defp filter_by_after_id(query, after_id) do
    # Get the reference activity for cursor-based pagination
    case Repo.get(ContractActivity, after_id) do
      nil ->
        query

      ref ->
        where(
          query,
          [a],
          a.block_number < ^ref.block_number or
            (a.block_number == ^ref.block_number and a.id < ^ref.id)
        )
    end
  end
end
