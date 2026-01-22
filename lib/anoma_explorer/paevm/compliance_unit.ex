defmodule AnomaExplorer.Paevm.ComplianceUnit do
  @moduledoc """
  Schema for compliance units within an action.

  Represents a consumed/created resource pair with their proofs.
  Each compliance unit contains:
  - Consumed resource refs (nullifier, logicRef, commitmentTreeRoot)
  - Created resource refs (commitment, logicRef)
  - Unit delta (EC point x, y)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AnomaExplorer.Paevm.{Action, Resource}

  schema "paevm_compliance_units" do
    belongs_to :action, Action

    field :unit_index, :integer

    # Consumed resource references
    field :consumed_nullifier, :string
    field :consumed_logic_ref, :string
    field :consumed_commitment_tree_root, :string

    # Created resource references
    field :created_commitment, :string
    field :created_logic_ref, :string

    # Unit delta (EC point)
    field :unit_delta_x, :string
    field :unit_delta_y, :string

    # Proof (optional if aggregated)
    field :proof, :binary

    # Flexible JSONB storage
    field :decoded_instance, :map

    has_many :resources, Resource

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(
    action_id unit_index
    consumed_nullifier consumed_logic_ref consumed_commitment_tree_root
    created_commitment created_logic_ref
    unit_delta_x unit_delta_y
  )a
  @optional_fields ~w(proof decoded_instance)a

  @doc """
  Creates a changeset for a compliance unit.
  """
  def changeset(unit, attrs) do
    unit
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:action_id)
    |> unique_constraint([:action_id, :unit_index])
  end
end
