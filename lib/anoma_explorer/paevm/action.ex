defmodule AnomaExplorer.Paevm.Action do
  @moduledoc """
  Schema for PA-EVM actions within a transaction.

  Captures the ActionExecuted event data. Each action contains
  compliance units and logic verifier inputs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AnomaExplorer.Paevm.{Transaction, ComplianceUnit, LogicVerifierInput}

  schema "paevm_actions" do
    belongs_to :transaction, Transaction

    field :action_index, :integer
    field :action_tree_root, :string
    field :action_tag_count, :integer
    field :log_index, :integer

    # Flexible JSONB storage
    field :decoded_action, :map
    field :raw_event, :map

    has_many :compliance_units, ComplianceUnit
    has_many :logic_verifier_inputs, LogicVerifierInput

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(transaction_id action_index action_tree_root action_tag_count)a
  @optional_fields ~w(log_index decoded_action raw_event)a

  @doc """
  Creates a changeset for a PA-EVM action.
  """
  def changeset(action, attrs) do
    action
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:transaction_id)
    |> unique_constraint([:transaction_id, :action_index])
  end
end
