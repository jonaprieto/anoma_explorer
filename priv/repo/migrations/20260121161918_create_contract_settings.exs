defmodule AnomaExplorer.Repo.Migrations.CreateContractSettings do
  use Ecto.Migration

  def change do
    create table(:contract_settings) do
      add :category, :string, null: false
      add :network, :string, null: false
      add :address, :string, null: false
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    # Indexes for efficient queries
    create index(:contract_settings, [:category])
    create index(:contract_settings, [:network])
    create index(:contract_settings, [:active])

    # Unique constraint: one address per category/network combination
    create unique_index(:contract_settings, [:category, :network],
             name: :contract_settings_category_network_unique_idx
           )
  end
end
