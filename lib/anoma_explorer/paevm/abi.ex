defmodule AnomaExplorer.Paevm.ABI do
  @moduledoc """
  ABI definitions and event signatures for PA-EVM ProtocolAdapter.

  Event signatures (topic0) are computed as keccak256 of the event signature.
  These are used to identify and decode PA-EVM specific events from Ethereum logs.
  """

  # Event signatures (keccak256 hashes)
  # Computed using: cast sig-event "EventName(types)"

  @transaction_executed_sig "0x10dd528db2c49add6545679b976df90d24c035d6a75b17f41b700e8c18ca5364"
  @action_executed_sig "0x1cc9a0755dd734c1ebfe98b68ece200037e363eb366d0dee04e420e2f23cc010"
  @forwarder_call_executed_sig "0xcddb327adb31fe5437df2a8c68301bb13a6baae432a804838caaf682506aadf1"
  @resource_payload_sig "0x3a134d01c07803003c63301717ddc4612e6c47ae408eeea3222cded532d02ae6"
  @discovery_payload_sig "0x48243873b4752ddcb45e0d7b11c4c266583e5e099a0b798fdd9c1af7d49324f3"
  @external_payload_sig "0x9c61b290f631097f56273cf4daf40df1ff9ccc33f101d464837da1f5ae18bd59"
  @application_payload_sig "0xa494dac4b7184843583f972e06783e2c3bb47f4f0137b8df52a860df07219f8c"
  @commitment_tree_root_added_sig "0x0a2dc548ed950accb40d5d78541f3954c5e182a8ecf19e581a4f2263f61f59d2"

  @doc """
  Returns a map of event names to their topic0 signatures.
  """
  def event_signatures do
    %{
      transaction_executed: @transaction_executed_sig,
      action_executed: @action_executed_sig,
      forwarder_call_executed: @forwarder_call_executed_sig,
      resource_payload: @resource_payload_sig,
      discovery_payload: @discovery_payload_sig,
      external_payload: @external_payload_sig,
      application_payload: @application_payload_sig,
      commitment_tree_root_added: @commitment_tree_root_added_sig
    }
  end

  @doc """
  Identifies an event type from its topic0 signature.
  Returns the event type atom or :unknown.
  """
  def identify_event(nil), do: :unknown

  def identify_event(topic0) do
    normalized = String.downcase(topic0)

    cond do
      normalized == String.downcase(@transaction_executed_sig) -> :transaction_executed
      normalized == String.downcase(@action_executed_sig) -> :action_executed
      normalized == String.downcase(@forwarder_call_executed_sig) -> :forwarder_call_executed
      normalized == String.downcase(@resource_payload_sig) -> :resource_payload
      normalized == String.downcase(@discovery_payload_sig) -> :discovery_payload
      normalized == String.downcase(@external_payload_sig) -> :external_payload
      normalized == String.downcase(@application_payload_sig) -> :application_payload
      normalized == String.downcase(@commitment_tree_root_added_sig) -> :commitment_tree_root_added
      true -> :unknown
    end
  end

  @doc """
  Returns all PA-EVM event topic signatures as a list.
  """
  def all_event_topics do
    [
      @transaction_executed_sig,
      @action_executed_sig,
      @forwarder_call_executed_sig,
      @resource_payload_sig,
      @discovery_payload_sig,
      @external_payload_sig,
      @application_payload_sig,
      @commitment_tree_root_added_sig
    ]
  end

  @doc """
  Returns all payload event topic signatures.
  """
  def payload_event_topics do
    [
      @resource_payload_sig,
      @discovery_payload_sig,
      @external_payload_sig,
      @application_payload_sig
    ]
  end

  @doc """
  Checks if a topic0 is a PA-EVM event.
  """
  def is_paevm_event?(nil), do: false

  def is_paevm_event?(topic0) do
    normalized = String.downcase(topic0)
    Enum.any?(all_event_topics(), fn sig -> String.downcase(sig) == normalized end)
  end

  @doc """
  Checks if a topic0 is a payload event.
  """
  def is_payload_event?(nil), do: false

  def is_payload_event?(topic0) do
    normalized = String.downcase(topic0)
    Enum.any?(payload_event_topics(), fn sig -> String.downcase(sig) == normalized end)
  end

  # Individual signature accessors
  def transaction_executed_sig, do: @transaction_executed_sig
  def action_executed_sig, do: @action_executed_sig
  def forwarder_call_executed_sig, do: @forwarder_call_executed_sig
  def resource_payload_sig, do: @resource_payload_sig
  def discovery_payload_sig, do: @discovery_payload_sig
  def external_payload_sig, do: @external_payload_sig
  def application_payload_sig, do: @application_payload_sig
  def commitment_tree_root_added_sig, do: @commitment_tree_root_added_sig
end
