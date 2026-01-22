defmodule AnomaExplorer.Paevm.ForwarderCall do
  @moduledoc """
  Schema for forwarder call events.

  Captures ForwarderCallExecuted events which represent external EVM calls
  made through the protocol adapter.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AnomaExplorer.Paevm.Transaction

  schema "paevm_forwarder_calls" do
    belongs_to :transaction, Transaction

    field :forwarder_address, :string
    field :input, :binary
    field :output, :binary

    # Decoded call data
    field :input_decoded, :map
    field :output_decoded, :map

    field :log_index, :integer
    field :raw_event, :map

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(transaction_id forwarder_address input output)a
  @optional_fields ~w(input_decoded output_decoded log_index raw_event)a

  @doc """
  Creates a changeset for a forwarder call.
  """
  def changeset(call, attrs) do
    call
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:transaction_id)
  end
end
