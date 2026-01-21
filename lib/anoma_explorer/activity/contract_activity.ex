defmodule AnomaExplorer.Activity.ContractActivity do
  @moduledoc """
  Schema for contract activity records.

  Stores transactions, logs, and transfers related to a tracked contract.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @valid_kinds ~w(tx log transfer)

  schema "contract_activity" do
    field :network, :string
    field :chain_id, :integer
    field :contract_address, :string
    field :kind, :string
    field :tx_hash, :string
    field :block_number, :integer
    field :timestamp, :utc_datetime
    field :from, :string
    field :to, :string
    field :value_wei, :decimal
    field :tx_index, :integer
    field :log_index, :integer
    field :method_id, :string
    field :topic0, :string
    field :topics, {:array, :string}
    field :data, :string
    field :raw, :map

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(network contract_address kind tx_hash block_number raw)a
  @optional_fields ~w(chain_id timestamp from to value_wei tx_index log_index method_id topic0 topics data)a

  @doc """
  Creates a changeset for contract activity.
  """
  def changeset(activity, attrs) do
    activity
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:kind, @valid_kinds)
    |> unique_constraint(:tx_hash,
      name: :contract_activity_tx_transfer_unique_idx,
      message: "has already been taken"
    )
    |> unique_constraint(:log_index,
      name: :contract_activity_log_unique_idx,
      message: "has already been taken"
    )
  end
end
