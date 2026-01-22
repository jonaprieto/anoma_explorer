defmodule AnomaExplorer.Repo.Migrations.CreatePaevmTables do
  @moduledoc """
  Creates all PA-EVM related tables for storing transaction data from the Protocol Adapter.

  Tables created:
  - paevm_transactions: Root transaction data from TransactionExecuted events
  - paevm_actions: Actions within transactions from ActionExecuted events
  - paevm_compliance_units: Compliance units (consumed/created resource pairs)
  - paevm_logic_verifier_inputs: Logic verifier inputs per resource
  - paevm_resources: Decoded resource data
  - paevm_payloads: Payload events (resource, discovery, external, application)
  - paevm_commitment_tree_roots: Commitment tree state changes
  - paevm_forwarder_calls: External forwarder call data
  """
  use Ecto.Migration

  def change do
    # ============================================
    # paevm_transactions - Root transaction data
    # ============================================
    create table(:paevm_transactions) do
      add :network, :string, null: false
      add :contract_address, :string, null: false
      add :tx_hash, :string, null: false
      add :block_number, :bigint, null: false
      add :log_index, :integer, null: false
      add :timestamp, :utc_datetime

      # From TransactionExecuted event
      add :tags, {:array, :string}, default: []
      add :logic_refs, {:array, :string}, default: []

      # Proofs (stored as binary for full reconstruction)
      add :delta_proof, :binary
      add :aggregation_proof, :binary

      # Computed metrics
      add :action_count, :integer, default: 0
      add :tag_count, :integer, default: 0
      add :compliance_unit_count, :integer, default: 0

      # Raw event data + decoded transaction (JSONB for flexibility)
      add :raw_event, :map
      add :decoded_tx, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:paevm_transactions, [:network, :contract_address, :tx_hash, :log_index])
    create index(:paevm_transactions, [:network])
    create index(:paevm_transactions, [:contract_address])
    create index(:paevm_transactions, [:block_number])
    create index(:paevm_transactions, [:timestamp])
    create index(:paevm_transactions, [:tags], using: :gin)
    create index(:paevm_transactions, [:logic_refs], using: :gin)

    # ============================================
    # paevm_actions - Actions within transactions
    # ============================================
    create table(:paevm_actions) do
      add :transaction_id, references(:paevm_transactions, on_delete: :delete_all), null: false
      add :action_index, :integer, null: false

      # From ActionExecuted event
      add :action_tree_root, :string, null: false
      add :action_tag_count, :integer, null: false
      add :log_index, :integer

      # Decoded action data (JSONB for flexibility)
      add :decoded_action, :map
      add :raw_event, :map

      timestamps(type: :utc_datetime)
    end

    create index(:paevm_actions, [:transaction_id])
    create index(:paevm_actions, [:action_tree_root])
    create unique_index(:paevm_actions, [:transaction_id, :action_index])

    # ============================================
    # paevm_compliance_units - Consumed/created pairs
    # ============================================
    create table(:paevm_compliance_units) do
      add :action_id, references(:paevm_actions, on_delete: :delete_all), null: false
      add :unit_index, :integer, null: false

      # Consumed resource references
      add :consumed_nullifier, :string, null: false
      add :consumed_logic_ref, :string, null: false
      add :consumed_commitment_tree_root, :string, null: false

      # Created resource references
      add :created_commitment, :string, null: false
      add :created_logic_ref, :string, null: false

      # Unit delta (EC point coordinates)
      add :unit_delta_x, :string, null: false
      add :unit_delta_y, :string, null: false

      # Proof (optional if aggregated)
      add :proof, :binary

      # Full decoded instance (JSONB for flexibility)
      add :decoded_instance, :map

      timestamps(type: :utc_datetime)
    end

    create index(:paevm_compliance_units, [:action_id])
    create index(:paevm_compliance_units, [:consumed_nullifier])
    create index(:paevm_compliance_units, [:created_commitment])
    create index(:paevm_compliance_units, [:consumed_logic_ref])
    create index(:paevm_compliance_units, [:created_logic_ref])
    create unique_index(:paevm_compliance_units, [:action_id, :unit_index])

    # ============================================
    # paevm_logic_verifier_inputs - Logic inputs per resource
    # ============================================
    create table(:paevm_logic_verifier_inputs) do
      add :action_id, references(:paevm_actions, on_delete: :delete_all), null: false
      add :input_index, :integer, null: false

      # Core fields
      add :tag, :string, null: false
      add :verifying_key, :string, null: false
      add :is_consumed, :boolean

      # Proof
      add :proof, :binary

      # AppData stored as JSONB for flexibility
      add :app_data, :map

      # Decoded instance
      add :decoded_input, :map

      timestamps(type: :utc_datetime)
    end

    create index(:paevm_logic_verifier_inputs, [:action_id])
    create index(:paevm_logic_verifier_inputs, [:tag])
    create index(:paevm_logic_verifier_inputs, [:verifying_key])
    create unique_index(:paevm_logic_verifier_inputs, [:action_id, :input_index])

    # ============================================
    # paevm_resources - Decoded resource data
    # ============================================
    create table(:paevm_resources) do
      add :transaction_id, references(:paevm_transactions, on_delete: :delete_all)
      add :compliance_unit_id, references(:paevm_compliance_units, on_delete: :delete_all)

      # Resource identification
      add :tag, :string, null: false
      add :resource_type, :string, null: false

      # Full Resource struct fields
      add :logic_ref, :string
      add :label_ref, :string
      add :value_ref, :string
      add :nullifier_key_commitment, :string
      add :nonce, :string
      add :rand_seed, :string
      add :quantity, :decimal
      add :ephemeral, :boolean

      # For flexible storage of additional/decoded data
      add :decoded_resource, :map
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    create index(:paevm_resources, [:transaction_id])
    create index(:paevm_resources, [:compliance_unit_id])
    create index(:paevm_resources, [:logic_ref])
    create index(:paevm_resources, [:resource_type])
    create unique_index(:paevm_resources, [:tag])

    # ============================================
    # paevm_payloads - Payload events
    # ============================================
    create table(:paevm_payloads) do
      add :transaction_id, references(:paevm_transactions, on_delete: :delete_all), null: false
      add :resource_id, references(:paevm_resources, on_delete: :nilify_all)

      add :payload_type, :string, null: false
      add :tag, :string, null: false
      add :payload_index, :integer, null: false
      add :deletion_criterion, :string

      # Blob data
      add :blob, :binary, null: false
      add :blob_decoded, :map

      add :log_index, :integer
      add :raw_event, :map

      timestamps(type: :utc_datetime)
    end

    create index(:paevm_payloads, [:transaction_id])
    create index(:paevm_payloads, [:resource_id])
    create index(:paevm_payloads, [:tag])
    create index(:paevm_payloads, [:payload_type])
    create unique_index(:paevm_payloads, [:transaction_id, :payload_type, :tag, :payload_index])

    # ============================================
    # paevm_commitment_tree_roots - Tree state
    # ============================================
    create table(:paevm_commitment_tree_roots) do
      add :network, :string, null: false
      add :contract_address, :string, null: false
      add :tx_hash, :string
      add :block_number, :bigint, null: false
      add :log_index, :integer

      add :root, :string, null: false
      add :root_index, :integer

      add :raw_event, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:paevm_commitment_tree_roots, [:network, :contract_address, :root])
    create index(:paevm_commitment_tree_roots, [:network])
    create index(:paevm_commitment_tree_roots, [:block_number])
    create index(:paevm_commitment_tree_roots, [:root])

    # ============================================
    # paevm_forwarder_calls - External calls
    # ============================================
    create table(:paevm_forwarder_calls) do
      add :transaction_id, references(:paevm_transactions, on_delete: :delete_all), null: false

      add :forwarder_address, :string, null: false
      add :input, :binary, null: false
      add :output, :binary, null: false

      # Decoded call data
      add :input_decoded, :map
      add :output_decoded, :map

      add :log_index, :integer
      add :raw_event, :map

      timestamps(type: :utc_datetime)
    end

    create index(:paevm_forwarder_calls, [:transaction_id])
    create index(:paevm_forwarder_calls, [:forwarder_address])
  end
end
