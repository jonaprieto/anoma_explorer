defmodule AnomaExplorer.Paevm do
  @moduledoc """
  Context module for PA-EVM transaction data.

  Provides functions for creating, querying, and managing PA-EVM
  transactions, actions, compliance units, resources, and related data.
  """
  import Ecto.Query

  alias AnomaExplorer.Repo

  alias AnomaExplorer.Paevm.{
    Transaction,
    Action,
    ComplianceUnit,
    LogicVerifierInput,
    Resource,
    Payload,
    CommitmentTreeRoot,
    ForwarderCall,
    Decoder
  }

  # ============================================
  # Transaction Operations
  # ============================================

  @doc """
  Creates a PA-EVM transaction.
  """
  def create_transaction(attrs) do
    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:network, :contract_address, :tx_hash, :log_index],
      returning: true
    )
  end

  @doc """
  Gets a transaction by ID with optional preloads.
  """
  def get_transaction(id, preloads \\ []) do
    Transaction
    |> Repo.get(id)
    |> maybe_preload(preloads)
  end

  @doc """
  Gets a transaction by tx_hash with full hierarchy.
  """
  def get_transaction_by_hash(network, contract_address, tx_hash) do
    Transaction
    |> where([t], t.network == ^network)
    |> where([t], t.contract_address == ^contract_address)
    |> where([t], t.tx_hash == ^tx_hash)
    |> preload(actions: [compliance_units: [], logic_verifier_inputs: []])
    |> preload([:payloads, :forwarder_calls, :resources])
    |> Repo.one()
  end

  @doc """
  Lists transactions with filters and pagination.

  Options:
  - :network - filter by network
  - :contract_address - filter by contract address
  - :after_block - filter for blocks after this number
  - :limit - max results (default 50)
  - :preloads - associations to preload
  """
  def list_transactions(opts \\ []) do
    Transaction
    |> apply_transaction_filters(opts)
    |> order_by([t], desc: t.block_number, desc: t.log_index)
    |> limit(^Keyword.get(opts, :limit, 50))
    |> Repo.all()
    |> maybe_preload(Keyword.get(opts, :preloads, []))
  end

  @doc """
  Counts transactions matching the given filters.
  """
  def count_transactions(opts \\ []) do
    Transaction
    |> apply_transaction_filters(opts)
    |> Repo.aggregate(:count)
  end

  # ============================================
  # Action Operations
  # ============================================

  @doc """
  Creates an action.
  """
  def create_action(attrs) do
    %Action{}
    |> Action.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets an action by ID.
  """
  def get_action(id, preloads \\ []) do
    Action
    |> Repo.get(id)
    |> maybe_preload(preloads)
  end

  @doc """
  Lists actions for a transaction.
  """
  def list_actions_for_transaction(transaction_id) do
    Action
    |> where([a], a.transaction_id == ^transaction_id)
    |> order_by([a], asc: a.action_index)
    |> preload([:compliance_units, :logic_verifier_inputs])
    |> Repo.all()
  end

  # ============================================
  # Compliance Unit Operations
  # ============================================

  @doc """
  Creates a compliance unit.
  """
  def create_compliance_unit(attrs) do
    %ComplianceUnit{}
    |> ComplianceUnit.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a compliance unit by ID.
  """
  def get_compliance_unit(id, preloads \\ []) do
    ComplianceUnit
    |> Repo.get(id)
    |> maybe_preload(preloads)
  end

  @doc """
  Finds compliance units by logic reference.
  """
  def find_by_logic_ref(logic_ref, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    ComplianceUnit
    |> where([cu], cu.consumed_logic_ref == ^logic_ref or cu.created_logic_ref == ^logic_ref)
    |> order_by([cu], desc: cu.inserted_at)
    |> limit(^limit)
    |> preload(action: :transaction)
    |> Repo.all()
  end

  @doc """
  Finds a compliance unit by nullifier.
  """
  def find_by_nullifier(nullifier) do
    ComplianceUnit
    |> where([cu], cu.consumed_nullifier == ^nullifier)
    |> preload(action: :transaction)
    |> Repo.one()
  end

  @doc """
  Finds a compliance unit by commitment.
  """
  def find_by_commitment(commitment) do
    ComplianceUnit
    |> where([cu], cu.created_commitment == ^commitment)
    |> preload(action: :transaction)
    |> Repo.one()
  end

  # ============================================
  # Logic Verifier Input Operations
  # ============================================

  @doc """
  Creates a logic verifier input.
  """
  def create_logic_verifier_input(attrs) do
    %LogicVerifierInput{}
    |> LogicVerifierInput.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Finds logic verifier inputs by verifying key.
  """
  def find_by_verifying_key(verifying_key, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    LogicVerifierInput
    |> where([lvi], lvi.verifying_key == ^verifying_key)
    |> order_by([lvi], desc: lvi.inserted_at)
    |> limit(^limit)
    |> preload(action: :transaction)
    |> Repo.all()
  end

  @doc """
  Finds a logic verifier input by tag.
  """
  def find_logic_input_by_tag(tag) do
    LogicVerifierInput
    |> where([lvi], lvi.tag == ^tag)
    |> preload(action: :transaction)
    |> Repo.one()
  end

  # ============================================
  # Resource Operations
  # ============================================

  @doc """
  Creates a resource.
  """
  def create_resource(attrs) do
    %Resource{}
    |> Resource.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:tag],
      returning: true
    )
  end

  @doc """
  Gets a resource by tag.
  """
  def get_resource_by_tag(tag) do
    Resource
    |> where([r], r.tag == ^tag)
    |> preload([:payloads, :transaction, :compliance_unit])
    |> Repo.one()
  end

  @doc """
  Lists resources with filters.
  """
  def list_resources(opts \\ []) do
    Resource
    |> apply_resource_filters(opts)
    |> order_by([r], desc: r.inserted_at)
    |> limit(^Keyword.get(opts, :limit, 50))
    |> Repo.all()
  end

  # ============================================
  # Payload Operations
  # ============================================

  @doc """
  Creates a payload.
  """
  def create_payload(attrs) do
    %Payload{}
    |> Payload.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:transaction_id, :payload_type, :tag, :payload_index]
    )
  end

  @doc """
  Lists payloads for a tag.
  """
  def list_payloads_for_tag(tag) do
    Payload
    |> where([p], p.tag == ^tag)
    |> order_by([p], asc: p.payload_index)
    |> Repo.all()
  end

  @doc """
  Lists payloads by type.
  """
  def list_payloads_by_type(payload_type, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Payload
    |> where([p], p.payload_type == ^payload_type)
    |> order_by([p], desc: p.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # ============================================
  # Commitment Tree Root Operations
  # ============================================

  @doc """
  Creates a commitment tree root.
  """
  def create_commitment_tree_root(attrs) do
    %CommitmentTreeRoot{}
    |> CommitmentTreeRoot.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:network, :contract_address, :root]
    )
  end

  @doc """
  Lists commitment tree roots.
  """
  def list_commitment_tree_roots(network, contract_address, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    CommitmentTreeRoot
    |> where([r], r.network == ^network and r.contract_address == ^contract_address)
    |> order_by([r], desc: r.block_number)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a commitment tree root by its root hash.
  """
  def get_commitment_tree_root(network, contract_address, root) do
    CommitmentTreeRoot
    |> where([r], r.network == ^network)
    |> where([r], r.contract_address == ^contract_address)
    |> where([r], r.root == ^root)
    |> Repo.one()
  end

  # ============================================
  # Forwarder Call Operations
  # ============================================

  @doc """
  Creates a forwarder call.
  """
  def create_forwarder_call(attrs) do
    %ForwarderCall{}
    |> ForwarderCall.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists forwarder calls by address.
  """
  def list_forwarder_calls_by_address(forwarder_address, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    ForwarderCall
    |> where([fc], fc.forwarder_address == ^forwarder_address)
    |> order_by([fc], desc: fc.inserted_at)
    |> limit(^limit)
    |> preload(:transaction)
    |> Repo.all()
  end

  # ============================================
  # Batch Processing
  # ============================================

  @doc """
  Processes and stores a batch of decoded events atomically.

  Events should be pre-decoded using the Decoder module.
  """
  def process_event_batch(events, network, contract_address) do
    Repo.transaction(fn ->
      # Group events by transaction
      events_by_tx = Enum.group_by(events, fn
        {_type, data} when is_map(data) -> Map.get(data, :tx_hash)
        _ -> nil
      end)

      results =
        for {tx_hash, tx_events} <- events_by_tx, tx_hash != nil do
          process_transaction_events(tx_events, network, contract_address, tx_hash)
        end

      %{
        processed_transactions: length(results),
        results: results
      }
    end)
  end

  @doc """
  Processes a list of raw logs and stores them.
  """
  def process_raw_logs(logs, network, contract_address) do
    decoded_events = Enum.map(logs, &Decoder.decode_log/1)
    process_event_batch(decoded_events, network, contract_address)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp process_transaction_events(events, network, contract_address, tx_hash) do
    # Find TransactionExecuted event first
    tx_event = Enum.find(events, fn
      {:transaction_executed, _} -> true
      _ -> false
    end)

    case tx_event do
      {:transaction_executed, data} ->
        # Create the transaction
        {:ok, transaction} =
          create_transaction(%{
            network: network,
            contract_address: contract_address,
            tx_hash: tx_hash,
            block_number: data.block_number,
            log_index: data.log_index,
            tags: data.tags,
            logic_refs: data.logic_refs,
            tag_count: length(data.tags),
            raw_event: data.raw
          })

        # Process actions
        action_events =
          events
          |> Enum.filter(fn
            {:action_executed, _} -> true
            _ -> false
          end)
          |> Enum.sort_by(fn {:action_executed, d} -> d.log_index end)

        actions =
          for {{:action_executed, data}, idx} <- Enum.with_index(action_events) do
            {:ok, action} =
              create_action(%{
                transaction_id: transaction.id,
                action_tree_root: data.action_tree_root,
                action_tag_count: data.action_tag_count,
                action_index: idx,
                log_index: data.log_index,
                raw_event: data.raw
              })

            action
          end

        # Update transaction with action count
        Repo.update!(
          Transaction.changeset(transaction, %{action_count: length(actions)})
        )

        # Process payloads
        payload_events =
          Enum.filter(events, fn
            {:payload, _} -> true
            _ -> false
          end)

        for {:payload, data} <- payload_events do
          create_payload(%{
            transaction_id: transaction.id,
            payload_type: data.payload_type,
            tag: data.tag,
            payload_index: data.index,
            blob: data.blob,
            log_index: data.log_index,
            raw_event: data.raw
          })
        end

        # Process forwarder calls
        forwarder_events =
          Enum.filter(events, fn
            {:forwarder_call_executed, _} -> true
            _ -> false
          end)

        for {:forwarder_call_executed, data} <- forwarder_events do
          create_forwarder_call(%{
            transaction_id: transaction.id,
            forwarder_address: data.forwarder_address,
            input: data.input,
            output: data.output,
            log_index: data.log_index,
            raw_event: data.raw
          })
        end

        {:ok, transaction}

      nil ->
        # Handle commitment tree root events without transaction context
        for event <- events do
          case event do
            {:commitment_tree_root_added, data} ->
              create_commitment_tree_root(%{
                network: network,
                contract_address: contract_address,
                tx_hash: tx_hash,
                block_number: data.block_number,
                log_index: data.log_index,
                root: data.root,
                raw_event: data.raw
              })

            _ ->
              nil
          end
        end

        {:ok, :commitment_roots_only}
    end
  end

  defp apply_transaction_filters(query, opts) do
    query
    |> filter_by_field(:network, Keyword.get(opts, :network))
    |> filter_by_field(:contract_address, Keyword.get(opts, :contract_address))
    |> filter_after_block(Keyword.get(opts, :after_block))
  end

  defp apply_resource_filters(query, opts) do
    query
    |> filter_by_field(:resource_type, Keyword.get(opts, :resource_type))
    |> filter_by_field(:logic_ref, Keyword.get(opts, :logic_ref))
  end

  defp filter_by_field(query, _field, nil), do: query
  defp filter_by_field(query, field, value), do: where(query, [t], field(t, ^field) == ^value)

  defp filter_after_block(query, nil), do: query
  defp filter_after_block(query, block), do: where(query, [t], t.block_number > ^block)

  defp maybe_preload(nil, _), do: nil
  defp maybe_preload(record, []), do: record
  defp maybe_preload(record, preloads), do: Repo.preload(record, preloads)
end
