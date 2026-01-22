defmodule AnomaExplorer.Settings.Protocol do
  @moduledoc """
  Schema for protocols (e.g., Anoma).

  A protocol groups contract addresses by their purpose and version.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AnomaExplorer.Settings.ContractAddress

  schema "protocols" do
    field :name, :string
    field :description, :string
    field :github_url, :string
    field :active, :boolean, default: true

    has_many :contract_addresses, ContractAddress

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(name)a
  @optional_fields ~w(description github_url active)a

  def changeset(protocol, attrs) do
    protocol
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:name)
  end
end
