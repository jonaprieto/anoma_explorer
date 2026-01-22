defmodule AnomaExplorer.Repo.Migrations.AddProtocolAndVersionToContractSettings do
  use Ecto.Migration

  def up do
    # 1. Insert default "Anoma" protocol
    execute """
    INSERT INTO protocols (name, description, active, inserted_at, updated_at)
    VALUES ('Anoma', 'Anoma Protocol contracts', true, NOW(), NOW())
    """

    # 2. Add protocol_id and version columns (nullable initially)
    alter table(:contract_settings) do
      add :protocol_id, references(:protocols, on_delete: :restrict)
      add :version, :string
    end

    # 3. Migrate existing data - link to Anoma protocol, set version to "v1.0"
    execute """
    UPDATE contract_settings
    SET protocol_id = (SELECT id FROM protocols WHERE name = 'Anoma'),
        version = 'v1.0'
    """

    # 4. Make protocol_id and version required
    alter table(:contract_settings) do
      modify :protocol_id, :bigint, null: false
      modify :version, :string, null: false
    end

    # 5. Drop old unique constraint
    drop unique_index(:contract_settings, [:category, :network],
      name: :contract_settings_category_network_unique_idx
    )

    # 6. Rename table to contract_addresses
    rename table(:contract_settings), to: table(:contract_addresses)

    # 7. Create new unique constraint with protocol_id and version
    create unique_index(:contract_addresses, [:protocol_id, :category, :version, :network],
      name: :contract_addresses_unique_idx
    )

    # 8. Add index on protocol_id
    create index(:contract_addresses, [:protocol_id])
    create index(:contract_addresses, [:version])
  end

  def down do
    # Reverse the migration
    drop index(:contract_addresses, [:version])
    drop index(:contract_addresses, [:protocol_id])
    drop unique_index(:contract_addresses, [:protocol_id, :category, :version, :network],
      name: :contract_addresses_unique_idx
    )

    rename table(:contract_addresses), to: table(:contract_settings)

    create unique_index(:contract_settings, [:category, :network],
      name: :contract_settings_category_network_unique_idx
    )

    alter table(:contract_settings) do
      remove :protocol_id
      remove :version
    end

    execute "DELETE FROM protocols WHERE name = 'Anoma'"
  end
end
