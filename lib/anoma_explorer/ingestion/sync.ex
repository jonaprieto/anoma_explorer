defmodule AnomaExplorer.Ingestion.Sync do
  @moduledoc """
  Synchronization logic for ingesting blockchain data.

  Handles fetching logs and transfers from Alchemy and storing them
  in the database with atomic cursor updates.
  """
  require Logger

  alias AnomaExplorer.Alchemy
  alias AnomaExplorer.Activity.ContractActivity
  alias AnomaExplorer.Ingestion
  alias AnomaExplorer.Repo

  @default_chunk_size 2000
  @default_backfill_blocks 50_000

  @doc """
  Synchronizes logs for a contract on a specific network.

  Fetches logs from the last seen block (or backfill start) to the current block,
  inserts them into the database, and updates the ingestion state atomically.

  ## Options
    * `:chunk_size` - Number of blocks per getLogs request (default 2000)
    * `:backfill_blocks` - Blocks to go back when no state exists (default 50000)
    * `:start_block` - Explicit start block (overrides backfill)
  """
  @spec sync_logs(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def sync_logs(network, contract_address, api_key, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    backfill_blocks = Keyword.get(opts, :backfill_blocks, @default_backfill_blocks)
    start_block_opt = Keyword.get(opts, :start_block)

    with {:ok, current_block} <- Alchemy.get_block_number(network, api_key),
         {:ok, state} <- Ingestion.get_or_create_state(network, contract_address) do

      from_block = calculate_from_block(state, start_block_opt, current_block, backfill_blocks)
      to_block = current_block

      if from_block > to_block do
        Logger.info("No new blocks to sync for #{network}/#{contract_address}")
        {:ok, %{inserted_count: 0, last_block: current_block}}
      else
        sync_log_range(network, contract_address, api_key, from_block, to_block, chunk_size, state)
      end
    end
  end

  # Private helpers

  defp calculate_from_block(state, start_block_opt, current_block, backfill_blocks) do
    cond do
      # Explicit start block takes priority
      start_block_opt != nil ->
        start_block_opt

      # Resume from last seen block + 1
      state.last_seen_block_logs != nil ->
        state.last_seen_block_logs + 1

      # Backfill from current - backfill_blocks
      true ->
        max(0, current_block - backfill_blocks)
    end
  end

  defp sync_log_range(network, contract_address, api_key, from_block, to_block, _chunk_size, state) do
    # Note: chunk_size is available for future chunking implementation
    Logger.info("Syncing logs for #{network}/#{contract_address} from #{from_block} to #{to_block}")

    # For simplicity in MVP, fetch all in one chunk if range is small enough
    # In production, would chunk this
    case Alchemy.get_logs(network, api_key, contract_address, from_block, to_block) do
      {:ok, logs} ->
        inserted_count = upsert_logs_atomically(logs, state, to_block)
        {:ok, %{inserted_count: inserted_count, last_block: to_block}}

      {:error, reason} ->
        Logger.error("Failed to fetch logs: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp upsert_logs_atomically(logs, state, last_block) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Prepare activity records
    activities =
      Enum.map(logs, fn log ->
        %{
          network: log.network,
          contract_address: log.contract_address,
          kind: log.kind,
          tx_hash: log.tx_hash,
          block_number: log.block_number,
          log_index: log.log_index,
          tx_index: log.tx_index,
          topic0: log.topic0,
          topics: log.topics,
          data: log.data,
          raw: log.raw,
          inserted_at: now,
          updated_at: now
        }
      end)

    # Use Ecto.Multi for atomic operation
    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:upsert_logs, fn _repo, _changes ->
        if Enum.empty?(activities) do
          {:ok, 0}
        else
          {count, _} = Repo.insert_all(
            ContractActivity,
            activities,
            on_conflict: {:replace, [:updated_at]},
            conflict_target: {:unsafe_fragment, "(network, contract_address, kind, tx_hash, log_index) WHERE log_index IS NOT NULL"}
          )
          {:ok, count}
        end
      end)
      |> Ecto.Multi.run(:update_state, fn _repo, _changes ->
        Ingestion.update_state(state, %{last_seen_block_logs: last_block})
      end)

    case Repo.transaction(multi) do
      {:ok, %{upsert_logs: count}} ->
        count

      {:error, _step, reason, _changes} ->
        Logger.error("Failed to upsert logs atomically: #{inspect(reason)}")
        0
    end
  end

  @doc """
  Synchronizes asset transfers for a contract on a specific network.

  Similar to sync_logs but uses the Alchemy Asset Transfers API.
  """
  @spec sync_transfers(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def sync_transfers(network, contract_address, api_key, opts \\ []) do
    backfill_blocks = Keyword.get(opts, :backfill_blocks, @default_backfill_blocks)
    start_block_opt = Keyword.get(opts, :start_block)
    max_count = Keyword.get(opts, :max_count, 100)

    with {:ok, current_block} <- Alchemy.get_block_number(network, api_key),
         {:ok, state} <- Ingestion.get_or_create_state(network, contract_address) do

      from_block = calculate_from_block_tx(state, start_block_opt, current_block, backfill_blocks)
      to_block = current_block

      if from_block > to_block do
        Logger.info("No new blocks to sync transfers for #{network}/#{contract_address}")
        {:ok, %{inserted_count: 0, last_block: current_block}}
      else
        sync_transfer_range(network, contract_address, api_key, from_block, to_block, max_count, state)
      end
    end
  end

  defp calculate_from_block_tx(state, start_block_opt, current_block, backfill_blocks) do
    cond do
      start_block_opt != nil -> start_block_opt
      state.last_seen_block_tx != nil -> state.last_seen_block_tx + 1
      true -> max(0, current_block - backfill_blocks)
    end
  end

  defp sync_transfer_range(network, contract_address, api_key, from_block, to_block, max_count, state) do
    Logger.info("Syncing transfers for #{network}/#{contract_address} from #{from_block} to #{to_block}")

    case fetch_all_transfers(network, api_key, contract_address, from_block, to_block, max_count) do
      {:ok, transfers} ->
        inserted_count = upsert_transfers_atomically(transfers, state, to_block)
        {:ok, %{inserted_count: inserted_count, last_block: to_block}}

      {:error, reason} ->
        Logger.error("Failed to fetch transfers: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_all_transfers(network, api_key, contract_address, from_block, to_block, max_count) do
    fetch_transfers_page(network, api_key, contract_address, from_block, to_block, max_count, nil, [])
  end

  defp fetch_transfers_page(network, api_key, contract_address, from_block, to_block, max_count, page_key, acc) do
    opts = if page_key, do: [max_count: max_count, page_key: page_key], else: [max_count: max_count]

    case Alchemy.get_asset_transfers(network, api_key, contract_address, from_block, to_block, opts) do
      {:ok, transfers, nil} ->
        {:ok, acc ++ transfers}

      {:ok, transfers, next_page_key} ->
        fetch_transfers_page(network, api_key, contract_address, from_block, to_block, max_count, next_page_key, acc ++ transfers)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upsert_transfers_atomically(transfers, state, last_block) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    activities =
      Enum.map(transfers, fn transfer ->
        %{
          network: transfer.network,
          contract_address: transfer.contract_address,
          kind: transfer.kind,
          tx_hash: transfer.tx_hash,
          block_number: transfer.block_number,
          from: transfer.from,
          to: transfer.to,
          value_wei: transfer.value_wei,
          timestamp: transfer.timestamp,
          raw: transfer.raw,
          inserted_at: now,
          updated_at: now
        }
      end)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:upsert_transfers, fn _repo, _changes ->
        if Enum.empty?(activities) do
          {:ok, 0}
        else
          {count, _} = Repo.insert_all(
            ContractActivity,
            activities,
            on_conflict: {:replace, [:updated_at]},
            conflict_target: {:unsafe_fragment, "(network, contract_address, kind, tx_hash) WHERE log_index IS NULL"}
          )
          {:ok, count}
        end
      end)
      |> Ecto.Multi.run(:update_state, fn _repo, _changes ->
        Ingestion.update_state(state, %{last_seen_block_tx: last_block})
      end)

    case Repo.transaction(multi) do
      {:ok, %{upsert_transfers: count}} ->
        count

      {:error, _step, reason, _changes} ->
        Logger.error("Failed to upsert transfers atomically: #{inspect(reason)}")
        0
    end
  end
end
