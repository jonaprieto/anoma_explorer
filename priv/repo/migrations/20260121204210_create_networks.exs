defmodule AnomaExplorer.Repo.Migrations.CreateNetworks do
  use Ecto.Migration

  def change do
    create table(:networks) do
      add :name, :string, null: false
      add :display_name, :string, null: false
      add :chain_id, :integer
      add :explorer_url, :string
      add :rpc_url, :string
      add :is_testnet, :boolean, default: false, null: false
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:networks, [:name])
    create index(:networks, [:active])
    create index(:networks, [:is_testnet])
  end
end
