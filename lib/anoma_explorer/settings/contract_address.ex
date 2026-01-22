defmodule AnomaExplorer.Settings.ContractAddress do
  @moduledoc """
  Schema for storing contract addresses by protocol, category, version, and network.

  Categories represent different contract types (e.g., pa-evm, protocol_adapter).
  Versions track contract iterations (e.g., v1.0, 2.1.3, latest).
  Networks represent blockchain networks (e.g., eth-mainnet, base-sepolia).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AnomaExplorer.Settings.Protocol

  schema "contract_addresses" do
    # For example: pa-evm
    field :category, :string
    field :version, :string
    field :network, :string
    field :address, :string
    field :active, :boolean, default: true

    belongs_to :protocol, Protocol

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(protocol_id category version network address)a
  @optional_fields ~w(active)a

  def changeset(contract_address, attrs) do
    contract_address
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:category, min: 1, max: 100)
    |> validate_length(:version, min: 1, max: 50)
    |> validate_ethereum_address(:address)
    |> foreign_key_constraint(:protocol_id)
    |> unique_constraint([:protocol_id, :category, :version, :network],
      name: :contract_addresses_unique_idx,
      message: "already exists for this protocol, category, version, and network"
    )
  end

  # Validates Ethereum address format (0x + 40 hex chars)
  defp validate_ethereum_address(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      downcased = String.downcase(value)

      cond do
        not String.starts_with?(downcased, "0x") ->
          [{field, "must start with 0x"}]

        String.length(downcased) != 42 ->
          [{field, "must have exactly 40 hex characters after 0x"}]

        not Regex.match?(~r/^0x[0-9a-f]{40}$/, downcased) ->
          [{field, "contains invalid hex characters"}]

        true ->
          []
      end
    end)
  end
end
