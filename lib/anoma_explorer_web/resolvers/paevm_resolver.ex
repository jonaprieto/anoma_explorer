defmodule AnomaExplorerWeb.Resolvers.PaevmResolver do
  @moduledoc """
  GraphQL resolvers for PA-EVM data.
  """

  alias AnomaExplorer.Paevm
  alias AnomaExplorer.Repo

  # ============================================
  # Transaction Resolvers
  # ============================================

  def get_transaction(_parent, %{id: id}, _resolution) do
    case Paevm.get_transaction(id) do
      nil -> {:error, "Transaction not found"}
      tx -> {:ok, tx}
    end
  end

  def get_transaction_by_hash(_parent, %{network: network, contract_address: addr, tx_hash: hash}, _resolution) do
    case Paevm.get_transaction_by_hash(network, addr, hash) do
      nil -> {:error, "Transaction not found"}
      tx -> {:ok, tx}
    end
  end

  def list_transactions(_parent, args, _resolution) do
    opts = build_transaction_opts(args)
    {:ok, Paevm.list_transactions(opts)}
  end

  # ============================================
  # Action Resolvers
  # ============================================

  def get_action(_parent, %{id: id}, _resolution) do
    case Paevm.get_action(id) do
      nil -> {:error, "Action not found"}
      action -> {:ok, action}
    end
  end

  def actions_for_transaction(transaction, _args, _resolution) do
    actions = Paevm.list_actions_for_transaction(transaction.id)
    {:ok, actions}
  end

  def transaction_for_action(action, _args, _resolution) do
    tx = Paevm.get_transaction(action.transaction_id)
    {:ok, tx}
  end

  # ============================================
  # Compliance Unit Resolvers
  # ============================================

  def find_by_logic_ref(_parent, %{logic_ref: ref, limit: limit}, _resolution) do
    {:ok, Paevm.find_by_logic_ref(ref, limit: limit)}
  end

  def find_by_nullifier(_parent, %{nullifier: nullifier}, _resolution) do
    {:ok, Paevm.find_by_nullifier(nullifier)}
  end

  def find_by_commitment(_parent, %{commitment: commitment}, _resolution) do
    {:ok, Paevm.find_by_commitment(commitment)}
  end

  def compliance_units_for_action(action, _args, _resolution) do
    action = Repo.preload(action, :compliance_units)
    {:ok, action.compliance_units}
  end

  def action_for_compliance_unit(cu, _args, _resolution) do
    action = Paevm.get_action(cu.action_id)
    {:ok, action}
  end

  def resources_for_compliance_unit(cu, _args, _resolution) do
    cu = Repo.preload(cu, :resources)
    {:ok, cu.resources}
  end

  # ============================================
  # Logic Verifier Input Resolvers
  # ============================================

  def find_by_verifying_key(_parent, %{verifying_key: key, limit: limit}, _resolution) do
    {:ok, Paevm.find_by_verifying_key(key, limit: limit)}
  end

  def logic_inputs_for_action(action, _args, _resolution) do
    action = Repo.preload(action, :logic_verifier_inputs)
    {:ok, action.logic_verifier_inputs}
  end

  def action_for_logic_input(input, _args, _resolution) do
    action = Paevm.get_action(input.action_id)
    {:ok, action}
  end

  # ============================================
  # Resource Resolvers
  # ============================================

  def get_resource_by_tag(_parent, %{tag: tag}, _resolution) do
    {:ok, Paevm.get_resource_by_tag(tag)}
  end

  def list_resources(_parent, args, _resolution) do
    opts = build_resource_opts(args)
    {:ok, Paevm.list_resources(opts)}
  end

  def resources_for_transaction(transaction, _args, _resolution) do
    transaction = Repo.preload(transaction, :resources)
    {:ok, transaction.resources}
  end

  def payloads_for_resource(resource, _args, _resolution) do
    resource = Repo.preload(resource, :payloads)
    {:ok, resource.payloads}
  end

  # ============================================
  # Payload Resolvers
  # ============================================

  def payloads_by_tag(_parent, %{tag: tag}, _resolution) do
    payloads =
      Paevm.list_payloads_for_tag(tag)
      |> Enum.map(&encode_payload_blob/1)

    {:ok, payloads}
  end

  def payloads_for_transaction(transaction, _args, _resolution) do
    transaction = Repo.preload(transaction, :payloads)

    payloads =
      transaction.payloads
      |> Enum.map(&encode_payload_blob/1)

    {:ok, payloads}
  end

  # ============================================
  # Commitment Tree Root Resolvers
  # ============================================

  def list_commitment_tree_roots(_parent, %{network: network, contract_address: addr, limit: limit}, _resolution) do
    {:ok, Paevm.list_commitment_tree_roots(network, addr, limit: limit)}
  end

  # ============================================
  # Forwarder Call Resolvers
  # ============================================

  def forwarder_calls_for_transaction(transaction, _args, _resolution) do
    transaction = Repo.preload(transaction, :forwarder_calls)

    calls =
      transaction.forwarder_calls
      |> Enum.map(&encode_forwarder_call/1)

    {:ok, calls}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp build_transaction_opts(%{filter: filter, limit: limit}) when not is_nil(filter) do
    filter
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Keyword.new()
    |> Keyword.put(:limit, limit)
  end

  defp build_transaction_opts(%{limit: limit}), do: [limit: limit]
  defp build_transaction_opts(_), do: []

  defp build_resource_opts(%{filter: filter, limit: limit}) when not is_nil(filter) do
    filter
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Keyword.new()
    |> Keyword.put(:limit, limit)
  end

  defp build_resource_opts(%{limit: limit}), do: [limit: limit]
  defp build_resource_opts(_), do: []

  # Encode binary blob as base64 for GraphQL
  defp encode_payload_blob(payload) do
    Map.update(payload, :blob, "", fn
      nil -> ""
      blob when is_binary(blob) -> Base.encode64(blob)
      other -> to_string(other)
    end)
  end

  # Encode binary input/output as hex for GraphQL
  defp encode_forwarder_call(call) do
    call
    |> Map.update(:input, "", &encode_binary_as_hex/1)
    |> Map.update(:output, "", &encode_binary_as_hex/1)
  end

  defp encode_binary_as_hex(nil), do: ""
  defp encode_binary_as_hex(binary) when is_binary(binary), do: "0x" <> Base.encode16(binary, case: :lower)
  defp encode_binary_as_hex(other), do: to_string(other)
end
