defmodule AnomaExplorer.Ingestion.IngestionState do
  @moduledoc """
  Schema for tracking ingestion progress per network/contract pair.

  Stores the last processed block numbers for both transaction and log ingestion.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "ingestion_state" do
    field :network, :string
    field :contract_address, :string
    field :last_seen_block_tx, :integer
    field :last_seen_block_logs, :integer

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(network contract_address)a
  @optional_fields ~w(last_seen_block_tx last_seen_block_logs)a

  @doc """
  Creates a changeset for ingestion state.
  """
  def changeset(state, attrs) do
    state
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:network, :contract_address])
  end
end
