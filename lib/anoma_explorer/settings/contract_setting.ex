defmodule AnomaExplorer.Settings.ContractSetting do
  @moduledoc """
  Schema for storing contract address settings by category and network.

  Categories represent different contract types (e.g., protocol_adapter, erc20_forwarder).
  Networks represent blockchain networks (e.g., eth-mainnet, base-sepolia).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @valid_categories ~w(protocol_adapter erc20_forwarder)

  schema "contract_settings" do
    field :category, :string
    field :network, :string
    field :address, :string
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(category network address)a
  @optional_fields ~w(active)a

  @doc """
  Creates a changeset for contract settings.
  """
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:category, @valid_categories)
    |> validate_ethereum_address(:address)
    |> unique_constraint([:category, :network],
      name: :contract_settings_category_network_unique_idx,
      message: "already exists for this category and network"
    )
  end

  @doc """
  Returns the list of valid categories.
  """
  def valid_categories, do: @valid_categories

  # Private: Validates Ethereum address format (0x + 40 hex chars)
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
