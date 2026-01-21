defmodule AnomaExplorer.Workers.IngestionWorker do
  @moduledoc """
  Oban worker for ingesting blockchain data from Alchemy.

  Runs one ingestion cycle per network, then schedules the next run
  after the configured poll interval.
  """
  use Oban.Worker,
    queue: :ingestion,
    max_attempts: 3,
    unique: [period: 60, fields: [:args, :queue]]

  require Logger

  alias AnomaExplorer.Ingestion.Sync

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

    Logger.info("Starting ingestion for #{network}/#{contract_address}")

    opts = [
      chunk_size: chunk_size,
      backfill_blocks: backfill_blocks
    ]

    case Sync.sync_logs(network, contract_address, api_key, opts) do
      {:ok, result} ->
        Logger.info(
          "Ingestion complete for #{network}: #{result.inserted_count} logs, last block #{result.last_block}"
        )

        schedule_next(args, poll_interval)
        :ok

      {:error, reason} ->
        Logger.error("Ingestion failed for #{network}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Enqueues an ingestion job for a specific network.
  """
  @spec enqueue_for_network(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Oban.Job.t()} | {:error, Oban.Job.changeset()}
  def enqueue_for_network(network, contract_address, api_key, opts \\ []) do
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
  Schedules ingestion jobs for all configured networks.
  """
  @spec schedule_all_networks([String.t()], String.t(), String.t(), keyword()) ::
          [{:ok, Oban.Job.t()} | {:error, term()}]
  def schedule_all_networks(networks, contract_address, api_key, opts \\ []) do
    Enum.map(networks, fn network ->
      enqueue_for_network(network, contract_address, api_key, opts)
    end)
  end

  # Private helpers

  defp schedule_next(args, poll_interval) do
    # Schedule next job after poll_interval seconds
    %{args: args}
    |> new(schedule_in: poll_interval)
    |> Oban.insert()
  end
end
