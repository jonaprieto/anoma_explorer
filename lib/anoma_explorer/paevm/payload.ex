defmodule AnomaExplorer.Paevm.Payload do
  @moduledoc """
  Schema for payload events (ResourcePayload, DiscoveryPayload, ExternalPayload, ApplicationPayload).

  Payloads are emitted as events and linked to resources via their tag.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AnomaExplorer.Paevm.{Transaction, Resource}

  @payload_types ~w(resource discovery external application)
  @deletion_criteria ~w(immediately never)

  schema "paevm_payloads" do
    belongs_to :transaction, Transaction
    belongs_to :resource, Resource

    field :payload_type, :string
    field :tag, :string
    field :payload_index, :integer
    field :deletion_criterion, :string

    # Blob data
    field :blob, :binary
    field :blob_decoded, :map

    field :log_index, :integer
    field :raw_event, :map

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(transaction_id payload_type tag payload_index blob)a
  @optional_fields ~w(resource_id deletion_criterion blob_decoded log_index raw_event)a

  @doc """
  Creates a changeset for a payload.
  """
  def changeset(payload, attrs) do
    payload
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:payload_type, @payload_types)
    |> validate_inclusion(:deletion_criterion, @deletion_criteria ++ [nil])
    |> foreign_key_constraint(:transaction_id)
    |> foreign_key_constraint(:resource_id)
    |> unique_constraint([:transaction_id, :payload_type, :tag, :payload_index])
  end

  @doc """
  Returns valid payload types.
  """
  def payload_types, do: @payload_types

  @doc """
  Returns valid deletion criteria.
  """
  def deletion_criteria, do: @deletion_criteria
end
