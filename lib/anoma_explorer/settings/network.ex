defmodule AnomaExplorer.Settings.Network do
  @moduledoc """
  Schema for storing blockchain network configurations.

  Networks represent blockchain networks (e.g., eth-mainnet, base-sepolia).
  Each network has a unique name, display name, optional chain ID, and explorer URL.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "networks" do
    field :name, :string
    field :display_name, :string
    field :chain_id, :integer
    field :explorer_url, :string
    field :rpc_url, :string
    field :is_testnet, :boolean, default: false
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(name display_name)a
  @optional_fields ~w(chain_id explorer_url rpc_url is_testnet active)a

  def changeset(network, attrs) do
    network
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:display_name, min: 1, max: 100)
    |> validate_format(:name, ~r/^[a-z0-9-]+$/,
      message: "must contain only lowercase letters, numbers, and hyphens"
    )
    |> unique_constraint(:name)
  end
end
