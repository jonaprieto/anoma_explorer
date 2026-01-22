defmodule AnomaExplorer.Paevm.Transaction do
  @moduledoc """
  Schema for PA-EVM transactions.

  Captures the TransactionExecuted event data and serves as the root
  for the transaction hierarchy: Transaction > Actions > Compliance Units.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AnomaExplorer.Paevm.{Action, Payload, ForwarderCall, Resource}

  schema "paevm_transactions" do
    field :network, :string
    field :contract_address, :string
    field :tx_hash, :string
    field :block_number, :integer
    field :log_index, :integer
    field :timestamp, :utc_datetime

    # From TransactionExecuted event
    field :tags, {:array, :string}, default: []
    field :logic_refs, {:array, :string}, default: []

    # Proofs
    field :delta_proof, :binary
    field :aggregation_proof, :binary

    # Computed metrics
    field :action_count, :integer, default: 0
    field :tag_count, :integer, default: 0
    field :compliance_unit_count, :integer, default: 0

    # Flexible JSONB storage
    field :raw_event, :map
    field :decoded_tx, :map

    has_many :actions, Action
    has_many :payloads, Payload
    has_many :forwarder_calls, ForwarderCall
    has_many :resources, Resource

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(network contract_address tx_hash block_number log_index)a
  @optional_fields ~w(timestamp tags logic_refs delta_proof aggregation_proof action_count tag_count compliance_unit_count raw_event decoded_tx)a

  @doc """
  Creates a changeset for a PA-EVM transaction.
  """
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:network, :contract_address, :tx_hash, :log_index])
  end
end
