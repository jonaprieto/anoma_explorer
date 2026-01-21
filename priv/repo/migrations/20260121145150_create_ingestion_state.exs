defmodule AnomaExplorer.Repo.Migrations.CreateIngestionState do
  use Ecto.Migration

  def change do
    create table(:ingestion_state) do
      add :network, :string, null: false
      add :contract_address, :string, null: false
      add :last_seen_block_tx, :bigint
      add :last_seen_block_logs, :bigint

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ingestion_state, [:network, :contract_address])
  end
end
