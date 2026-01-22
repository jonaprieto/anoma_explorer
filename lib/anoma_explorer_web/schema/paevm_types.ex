defmodule AnomaExplorerWeb.Schema.PaevmTypes do
  @moduledoc """
  GraphQL type definitions for PA-EVM data.

  Defines types for transactions, actions, compliance units, resources,
  payloads, and related entities.
  """
  use Absinthe.Schema.Notation

  alias AnomaExplorerWeb.Resolvers.PaevmResolver

  # ============================================
  # Object Types
  # ============================================

  @desc "A PA-EVM transaction from the Protocol Adapter"
  object :paevm_transaction do
    field :id, non_null(:id)
    field :network, non_null(:string)
    field :contract_address, non_null(:string)
    field :tx_hash, non_null(:string)
    field :block_number, non_null(:integer)
    field :timestamp, :datetime
    field :tags, non_null(list_of(non_null(:string)))
    field :logic_refs, non_null(list_of(non_null(:string)))
    field :action_count, non_null(:integer)
    field :tag_count, non_null(:integer)
    field :compliance_unit_count, non_null(:integer)
    field :inserted_at, non_null(:datetime)

    field :actions, non_null(list_of(non_null(:paevm_action))) do
      resolve &PaevmResolver.actions_for_transaction/3
    end

    field :payloads, non_null(list_of(non_null(:paevm_payload))) do
      resolve &PaevmResolver.payloads_for_transaction/3
    end

    field :forwarder_calls, non_null(list_of(non_null(:paevm_forwarder_call))) do
      resolve &PaevmResolver.forwarder_calls_for_transaction/3
    end

    field :resources, non_null(list_of(non_null(:paevm_resource))) do
      resolve &PaevmResolver.resources_for_transaction/3
    end
  end

  @desc "An action within a PA-EVM transaction"
  object :paevm_action do
    field :id, non_null(:id)
    field :action_tree_root, non_null(:string)
    field :action_tag_count, non_null(:integer)
    field :action_index, non_null(:integer)
    field :inserted_at, non_null(:datetime)

    field :compliance_units, non_null(list_of(non_null(:paevm_compliance_unit))) do
      resolve &PaevmResolver.compliance_units_for_action/3
    end

    field :logic_verifier_inputs, non_null(list_of(non_null(:paevm_logic_verifier_input))) do
      resolve &PaevmResolver.logic_inputs_for_action/3
    end

    field :transaction, non_null(:paevm_transaction) do
      resolve &PaevmResolver.transaction_for_action/3
    end
  end

  @desc "A compliance unit representing a consumed/created resource pair"
  object :paevm_compliance_unit do
    field :id, non_null(:id)
    field :unit_index, non_null(:integer)

    # Consumed resource
    field :consumed_nullifier, non_null(:string)
    field :consumed_logic_ref, non_null(:string)
    field :consumed_commitment_tree_root, non_null(:string)

    # Created resource
    field :created_commitment, non_null(:string)
    field :created_logic_ref, non_null(:string)

    # Delta
    field :unit_delta_x, non_null(:string)
    field :unit_delta_y, non_null(:string)

    field :inserted_at, non_null(:datetime)

    field :action, non_null(:paevm_action) do
      resolve &PaevmResolver.action_for_compliance_unit/3
    end

    field :resources, non_null(list_of(non_null(:paevm_resource))) do
      resolve &PaevmResolver.resources_for_compliance_unit/3
    end
  end

  @desc "A logic verifier input for a resource"
  object :paevm_logic_verifier_input do
    field :id, non_null(:id)
    field :input_index, non_null(:integer)
    field :tag, non_null(:string)
    field :verifying_key, non_null(:string)
    field :is_consumed, :boolean
    field :app_data, :json
    field :inserted_at, non_null(:datetime)

    field :action, non_null(:paevm_action) do
      resolve &PaevmResolver.action_for_logic_input/3
    end
  end

  @desc "A resource in the Anoma protocol"
  object :paevm_resource do
    field :id, non_null(:id)
    field :tag, non_null(:string)
    field :resource_type, non_null(:string)
    field :logic_ref, :string
    field :label_ref, :string
    field :value_ref, :string
    field :nullifier_key_commitment, :string
    field :nonce, :string
    field :rand_seed, :string
    field :quantity, :decimal
    field :ephemeral, :boolean
    field :decoded_resource, :json
    field :metadata, :json
    field :inserted_at, non_null(:datetime)

    field :payloads, non_null(list_of(non_null(:paevm_payload))) do
      resolve &PaevmResolver.payloads_for_resource/3
    end
  end

  @desc "A payload associated with a resource"
  object :paevm_payload do
    field :id, non_null(:id)
    field :payload_type, non_null(:string)
    field :tag, non_null(:string)
    field :payload_index, non_null(:integer)
    field :deletion_criterion, :string
    field :blob, non_null(:string), description: "Base64 encoded blob data"
    field :blob_decoded, :json
    field :inserted_at, non_null(:datetime)
  end

  @desc "A commitment tree root state change"
  object :paevm_commitment_tree_root do
    field :id, non_null(:id)
    field :network, non_null(:string)
    field :contract_address, non_null(:string)
    field :tx_hash, :string
    field :block_number, non_null(:integer)
    field :root, non_null(:string)
    field :root_index, :integer
    field :inserted_at, non_null(:datetime)
  end

  @desc "A forwarder call to an external contract"
  object :paevm_forwarder_call do
    field :id, non_null(:id)
    field :forwarder_address, non_null(:string)
    field :input, non_null(:string), description: "Hex encoded input data"
    field :output, non_null(:string), description: "Hex encoded output data"
    field :input_decoded, :json
    field :output_decoded, :json
    field :inserted_at, non_null(:datetime)
  end

  # ============================================
  # Input Types
  # ============================================

  @desc "Filters for querying transactions"
  input_object :transaction_filter do
    field :network, :string
    field :contract_address, :string
    field :after_block, :integer
  end

  @desc "Filters for querying resources"
  input_object :resource_filter do
    field :resource_type, :string
    field :logic_ref, :string
  end

  # ============================================
  # Scalar Types
  # ============================================

  scalar :json, name: "JSON" do
    description "Arbitrary JSON data"
    serialize &Jason.encode!/1
    parse &parse_json/1
  end

  scalar :decimal, name: "Decimal" do
    description "A decimal number"
    serialize &Decimal.to_string/1
    parse &parse_decimal/1
  end

  scalar :datetime, name: "DateTime" do
    description "An ISO 8601 encoded datetime"
    serialize &DateTime.to_iso8601/1
    parse &parse_datetime/1
  end

  defp parse_json(%Absinthe.Blueprint.Input.String{value: value}) do
    case Jason.decode(value) do
      {:ok, result} -> {:ok, result}
      _ -> :error
    end
  end

  defp parse_json(%Absinthe.Blueprint.Input.Null{}), do: {:ok, nil}
  defp parse_json(_), do: :error

  defp parse_decimal(%Absinthe.Blueprint.Input.String{value: value}) do
    {:ok, Decimal.new(value)}
  rescue
    _ -> :error
  end

  defp parse_decimal(%Absinthe.Blueprint.Input.Integer{value: value}) do
    {:ok, Decimal.new(value)}
  end

  defp parse_decimal(%Absinthe.Blueprint.Input.Float{value: value}) do
    {:ok, Decimal.from_float(value)}
  end

  defp parse_decimal(%Absinthe.Blueprint.Input.Null{}), do: {:ok, nil}
  defp parse_decimal(_), do: :error

  defp parse_datetime(%Absinthe.Blueprint.Input.String{value: value}) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> {:ok, datetime}
      _ -> :error
    end
  end

  defp parse_datetime(%Absinthe.Blueprint.Input.Null{}), do: {:ok, nil}
  defp parse_datetime(_), do: :error

  # ============================================
  # Queries
  # ============================================

  object :paevm_queries do
    @desc "Get a PA-EVM transaction by ID"
    field :paevm_transaction, :paevm_transaction do
      arg :id, non_null(:id)
      resolve &PaevmResolver.get_transaction/3
    end

    @desc "Get a PA-EVM transaction by hash"
    field :paevm_transaction_by_hash, :paevm_transaction do
      arg :network, non_null(:string)
      arg :contract_address, non_null(:string)
      arg :tx_hash, non_null(:string)
      resolve &PaevmResolver.get_transaction_by_hash/3
    end

    @desc "List PA-EVM transactions"
    field :paevm_transactions, non_null(list_of(non_null(:paevm_transaction))) do
      arg :filter, :transaction_filter
      arg :limit, :integer, default_value: 50
      resolve &PaevmResolver.list_transactions/3
    end

    @desc "Get an action by ID"
    field :paevm_action, :paevm_action do
      arg :id, non_null(:id)
      resolve &PaevmResolver.get_action/3
    end

    @desc "Find compliance units by logic reference"
    field :compliance_units_by_logic_ref, non_null(list_of(non_null(:paevm_compliance_unit))) do
      arg :logic_ref, non_null(:string)
      arg :limit, :integer, default_value: 100
      resolve &PaevmResolver.find_by_logic_ref/3
    end

    @desc "Find compliance unit by nullifier"
    field :compliance_unit_by_nullifier, :paevm_compliance_unit do
      arg :nullifier, non_null(:string)
      resolve &PaevmResolver.find_by_nullifier/3
    end

    @desc "Find compliance unit by commitment"
    field :compliance_unit_by_commitment, :paevm_compliance_unit do
      arg :commitment, non_null(:string)
      resolve &PaevmResolver.find_by_commitment/3
    end

    @desc "Get a resource by tag"
    field :resource_by_tag, :paevm_resource do
      arg :tag, non_null(:string)
      resolve &PaevmResolver.get_resource_by_tag/3
    end

    @desc "List resources"
    field :resources, non_null(list_of(non_null(:paevm_resource))) do
      arg :filter, :resource_filter
      arg :limit, :integer, default_value: 50
      resolve &PaevmResolver.list_resources/3
    end

    @desc "List commitment tree roots"
    field :commitment_tree_roots, non_null(list_of(non_null(:paevm_commitment_tree_root))) do
      arg :network, non_null(:string)
      arg :contract_address, non_null(:string)
      arg :limit, :integer, default_value: 100
      resolve &PaevmResolver.list_commitment_tree_roots/3
    end

    @desc "Get payloads by tag"
    field :payloads_by_tag, non_null(list_of(non_null(:paevm_payload))) do
      arg :tag, non_null(:string)
      resolve &PaevmResolver.payloads_by_tag/3
    end

    @desc "Find logic verifier inputs by verifying key"
    field :logic_inputs_by_verifying_key, non_null(list_of(non_null(:paevm_logic_verifier_input))) do
      arg :verifying_key, non_null(:string)
      arg :limit, :integer, default_value: 100
      resolve &PaevmResolver.find_by_verifying_key/3
    end
  end
end
