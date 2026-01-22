defmodule AnomaExplorer.Paevm.CommitmentTreeRoot do
  @moduledoc """
  Schema for commitment tree root events.

  Tracks CommitmentTreeRootAdded events which represent state changes
  to the commitment tree.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "paevm_commitment_tree_roots" do
    field :network, :string
    field :contract_address, :string
    field :tx_hash, :string
    field :block_number, :integer
    field :log_index, :integer

    field :root, :string
    field :root_index, :integer

    field :raw_event, :map

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(network contract_address block_number root)a
  @optional_fields ~w(tx_hash log_index root_index raw_event)a

  @doc """
  Creates a changeset for a commitment tree root.
  """
  def changeset(root, attrs) do
    root
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:network, :contract_address, :root])
  end
end
