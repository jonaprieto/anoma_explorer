defmodule AnomaExplorer.Paevm.LogicVerifierInput do
  @moduledoc """
  Schema for logic verifier inputs within an action.

  Each logic verifier input corresponds to a resource (consumed or created)
  and contains:
  - tag (nullifier or commitment)
  - verifying_key (logic function hash)
  - app_data (payloads)
  - proof
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AnomaExplorer.Paevm.Action

  schema "paevm_logic_verifier_inputs" do
    belongs_to :action, Action

    field :input_index, :integer
    field :tag, :string
    field :verifying_key, :string
    field :is_consumed, :boolean

    # Proof
    field :proof, :binary

    # AppData stored as JSONB for flexibility
    # Contains: resourcePayload, discoveryPayload, externalPayload, applicationPayload
    field :app_data, :map

    # Decoded instance
    field :decoded_input, :map

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(action_id input_index tag verifying_key)a
  @optional_fields ~w(is_consumed proof app_data decoded_input)a

  @doc """
  Creates a changeset for a logic verifier input.
  """
  def changeset(input, attrs) do
    input
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:action_id)
    |> unique_constraint([:action_id, :input_index])
  end
end
