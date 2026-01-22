defmodule AnomaExplorer.Paevm.Sync do
  @moduledoc """
  Synchronization logic for ingesting PA-EVM events.

  Fetches PA-EVM specific events via Alchemy API, decodes them,
  and stores them in the database with atomic cursor updates.
  """
  require Logger

  alias AnomaExplorer.Alchemy
  alias AnomaExplorer.Ingestion
  alias AnomaExplorer.Paevm
  alias AnomaExplorer.Paevm.{ABI, Decoder}

  @default_chunk_size 2000
  @default_backfill_blocks 50_000

  @doc """
  Synchronizes PA-EVM events for a contract on a specific network.

  Fetches PA-EVM logs (TransactionExecuted, ActionExecuted, payloads, etc.)
  from the last seen block to the current block, decodes them, and stores
  them in the database.

  ## Options
    * `:chunk_size` - Number of blocks per getLogs request (default 2000)
    * `:backfill_blocks` - Blocks to go back when no state exists (default 50000)
    * `:start_block` - Explicit start block (overrides backfill)
  """
  @spec sync_paevm_events(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def sync_paevm_events(network, contract_address, api_key, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    backfill_blocks = Keyword.get(opts, :backfill_blocks, @default_backfill_blocks)
    start_block_opt = Keyword.get(opts, :start_block)

    with {:ok, current_block} <- Alchemy.get_block_number(network, api_key),
         {:ok, state} <- Ingestion.get_or_create_state(network, contract_address) do
      from_block = calculate_from_block(state, start_block_opt, current_block, backfill_blocks)
      to_block = current_block

      if from_block > to_block do
        Logger.info("No new blocks to sync PA-EVM for #{network}/#{contract_address}")
        {:ok, %{inserted_count: 0, last_block: current_block, transactions: 0}}
      else
        sync_paevm_range(
          network,
          contract_address,
          api_key,
          from_block,
          to_block,
          chunk_size,
          state
        )
      end
    end
  end

  @doc """
  Fetches PA-EVM logs for a block range without storing them.

  Useful for testing or one-off data retrieval.
  """
  @spec fetch_paevm_logs(String.t(), String.t(), String.t(), integer(), integer()) ::
          {:ok, [map()]} | {:error, term()}
  def fetch_paevm_logs(network, api_key, contract_address, from_block, to_block) do
    case Alchemy.get_logs(network, api_key, contract_address, from_block, to_block) do
      {:ok, logs} ->
        # Filter to only PA-EVM events
        paevm_logs = filter_paevm_logs(logs)
        {:ok, paevm_logs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Decodes a list of raw logs into PA-EVM events.
  """
  @spec decode_logs([map()]) :: [tuple()]
  def decode_logs(logs) do
    Enum.map(logs, &Decoder.decode_log/1)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp calculate_from_block(state, start_block_opt, current_block, backfill_blocks) do
    cond do
      start_block_opt != nil -> start_block_opt
      state.last_seen_block_logs != nil -> state.last_seen_block_logs + 1
      true -> max(0, current_block - backfill_blocks)
    end
  end

  defp sync_paevm_range(
         network,
         contract_address,
         api_key,
         from_block,
         to_block,
         _chunk_size,
         state
       ) do
    Logger.info(
      "Syncing PA-EVM events for #{network}/#{contract_address} from #{from_block} to #{to_block}"
    )

    case fetch_paevm_logs(network, api_key, contract_address, from_block, to_block) do
      {:ok, logs} when logs == [] ->
        # No PA-EVM events, still update state
        Ingestion.update_state(state, %{last_seen_block_logs: to_block})
        {:ok, %{inserted_count: 0, last_block: to_block, transactions: 0}}

      {:ok, logs} ->
        # Decode all logs
        decoded_events = decode_logs(logs)

        # Process and store
        case Paevm.process_event_batch(decoded_events, network, contract_address) do
          {:ok, result} ->
            # Update ingestion state
            Ingestion.update_state(state, %{last_seen_block_logs: to_block})

            Logger.info(
              "PA-EVM sync complete: #{result.processed_transactions} transactions, " <>
                "#{length(decoded_events)} events, last block #{to_block}"
            )

            {:ok,
             %{
               inserted_count: length(decoded_events),
               last_block: to_block,
               transactions: result.processed_transactions
             }}

          {:error, reason} ->
            Logger.error("Failed to process PA-EVM events: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch PA-EVM logs: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp filter_paevm_logs(logs) do
    Enum.filter(logs, fn log ->
      topic0 = Map.get(log, :topic0) || get_in(log, [:raw, "topics"]) |> List.first()
      ABI.is_paevm_event?(topic0)
    end)
  end
end
