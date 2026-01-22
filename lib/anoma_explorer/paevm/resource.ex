defmodule AnomaExplorer.Paevm.Resource do
  @moduledoc """
  Schema for decoded resource data.

  The Resource is the atomic unit of state in the Anoma protocol.
  Contains all fields from the Resource struct when decoded from payloads.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AnomaExplorer.Paevm.{Transaction, ComplianceUnit, Payload}

  @resource_types ~w(consumed created)

  schema "paevm_resources" do
    belongs_to :transaction, Transaction
    belongs_to :compliance_unit, ComplianceUnit

    # Resource identification
    field :tag, :string
    field :resource_type, :string

    # Full Resource struct fields
    field :logic_ref, :string
    field :label_ref, :string
    field :value_ref, :string
    field :nullifier_key_commitment, :string
    field :nonce, :string
    field :rand_seed, :string
    field :quantity, :decimal
    field :ephemeral, :boolean

    # Flexible JSONB storage
    field :decoded_resource, :map
    field :metadata, :map

    has_many :payloads, Payload

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(tag resource_type)a
  @optional_fields ~w(
    transaction_id compliance_unit_id
    logic_ref label_ref value_ref nullifier_key_commitment
    nonce rand_seed quantity ephemeral
    decoded_resource metadata
  )a

  @doc """
  Creates a changeset for a resource.
  """
  def changeset(resource, attrs) do
    resource
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:resource_type, @resource_types)
    |> foreign_key_constraint(:transaction_id)
    |> foreign_key_constraint(:compliance_unit_id)
    |> unique_constraint(:tag)
  end

  @doc """
  Returns valid resource types.
  """
  def resource_types, do: @resource_types
end
