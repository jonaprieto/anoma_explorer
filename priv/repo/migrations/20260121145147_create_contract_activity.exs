defmodule AnomaExplorer.Repo.Migrations.CreateContractActivity do
  use Ecto.Migration

  def change do
    create table(:contract_activity) do
      add :network, :string, null: false
      add :chain_id, :integer
      add :contract_address, :string, null: false
      add :kind, :string, null: false
      add :tx_hash, :string, null: false
      add :block_number, :bigint, null: false
      add :timestamp, :utc_datetime
      add :from, :string
      add :to, :string
      add :value_wei, :decimal
      add :tx_index, :integer
      add :log_index, :integer
      add :method_id, :string
      add :topic0, :string
      add :topics, :jsonb
      add :data, :text
      add :raw, :jsonb, null: false

      timestamps(type: :utc_datetime)
    end

    # Index for efficient queries
    create index(:contract_activity, [:network])
    create index(:contract_activity, [:contract_address])
    create index(:contract_activity, [:kind])
    create index(:contract_activity, [:block_number])
    create index(:contract_activity, [:tx_hash])

    # Unique index for tx/transfer kinds (log_index is NULL)
    create unique_index(
             :contract_activity,
             [:network, :contract_address, :kind, :tx_hash],
             where: "log_index IS NULL",
             name: :contract_activity_tx_transfer_unique_idx
           )

    # Unique index for log kind (includes log_index)
    create unique_index(
             :contract_activity,
             [:network, :contract_address, :kind, :tx_hash, :log_index],
             where: "log_index IS NOT NULL",
             name: :contract_activity_log_unique_idx
           )
  end
end
