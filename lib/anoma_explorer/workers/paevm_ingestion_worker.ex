defmodule AnomaExplorer.Workers.PaevmIngestionWorker do
  @moduledoc """
  Oban worker for ingesting PA-EVM specific events from the Protocol Adapter.

  Runs one ingestion cycle per network/contract, then schedules the next run
  after the configured poll interval.

  This worker handles:
  - TransactionExecuted events
  - ActionExecuted events
  - Payload events (Resource, Discovery, External, Application)
  - CommitmentTreeRootAdded events
  - ForwarderCallExecuted events
  """
  use Oban.Worker,
    queue: :paevm_ingestion,
    max_attempts: 3,
    unique: [period: 60, fields: [:args, :queue]]

  require Logger

  alias AnomaExplorer.Paevm.Sync

  @default_poll_interval 20
  @default_chunk_size 2000
  @default_backfill_blocks 50_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    network = args["network"]
    contract_address = args["contract_address"]
    api_key = args["api_key"]
    poll_interval = args["poll_interval"] || @default_poll_interval
    chunk_size = args["chunk_size"] || @default_chunk_size
    backfill_blocks = args["backfill_blocks"] || @default_backfill_blocks

    Logger.info("Starting PA-EVM ingestion for #{network}/#{contract_address}")

    opts = [
      chunk_size: chunk_size,
      backfill_blocks: backfill_blocks
    ]

    case Sync.sync_paevm_events(network, contract_address, api_key, opts) do
      {:ok, result} ->
        Logger.info(
          "PA-EVM ingestion complete for #{network}/#{contract_address}: " <>
            "#{result.transactions} transactions, #{result.inserted_count} events, " <>
            "last block #{result.last_block}"
        )

        schedule_next(args, poll_interval)
        :ok

      {:error, reason} ->
        Logger.error("PA-EVM ingestion failed for #{network}/#{contract_address}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Enqueues a PA-EVM ingestion job for a specific contract.
  """
  @spec enqueue_for_contract(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Oban.Job.t()} | {:error, Oban.Job.changeset()}
  def enqueue_for_contract(network, contract_address, api_key, opts \\ []) do
    args = %{
      "network" => network,
      "contract_address" => contract_address,
      "api_key" => api_key,
      "poll_interval" => Keyword.get(opts, :poll_interval, @default_poll_interval),
      "chunk_size" => Keyword.get(opts, :chunk_size, @default_chunk_size),
      "backfill_blocks" => Keyword.get(opts, :backfill_blocks, @default_backfill_blocks)
    }

    %{args: args}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Schedules PA-EVM ingestion jobs for multiple networks.
  """
  @spec schedule_for_networks([String.t()], String.t(), String.t(), keyword()) ::
          [{:ok, Oban.Job.t()} | {:error, term()}]
  def schedule_for_networks(networks, contract_address, api_key, opts \\ []) do
    Enum.map(networks, fn network ->
      enqueue_for_contract(network, contract_address, api_key, opts)
    end)
  end

  @doc """
  Cancels all scheduled PA-EVM ingestion jobs for a contract.
  """
  @spec cancel_for_contract(String.t(), String.t()) :: {:ok, integer()}
  def cancel_for_contract(network, contract_address) do
    import Ecto.Query

    # Find and cancel jobs matching this contract
    query =
      from j in Oban.Job,
        where: j.queue == "paevm_ingestion",
        where: j.state in ["available", "scheduled"],
        where:
          fragment("? ->> 'network' = ?", j.args, ^network) and
            fragment("? ->> 'contract_address' = ?", j.args, ^contract_address)

    {count, _} = AnomaExplorer.Repo.delete_all(query)
    {:ok, count}
  end

  # Private helpers

  defp schedule_next(args, poll_interval) do
    %{args: args}
    |> new(schedule_in: poll_interval)
    |> Oban.insert()
  end
end
