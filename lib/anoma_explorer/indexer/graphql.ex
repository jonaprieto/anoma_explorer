defmodule AnomaExplorer.Indexer.GraphQL do
  @moduledoc """
  GraphQL client for querying the Envio Hyperindex endpoint.

  Provides functions for fetching transactions, resources, actions,
  and aggregate statistics from the indexed blockchain data.
  """

  require Logger

  alias AnomaExplorer.Settings
  alias AnomaExplorer.Indexer.Cache

  # Default timeout values
  @default_timeout 15_000
  @default_connect_timeout 10_000
  @raw_timeout 30_000

  # Cache TTL for stats (10 seconds)
  @stats_cache_ttl 10_000

  # Behaviour for HTTP client (allows mocking in tests)
  @callback post_graphql(String.t(), String.t(), integer(), integer()) ::
              {:ok, map()} | {:error, term()}
  @callback post_graphql_raw(String.t(), String.t(), integer(), integer()) ::
              {:ok, map()} | {:error, term()}

  @type transaction :: %{
          id: String.t(),
          txHash: String.t(),
          blockNumber: integer(),
          timestamp: integer(),
          chainId: integer(),
          tags: [String.t()],
          logicRefs: [String.t()]
        }

  @type resource :: %{
          id: String.t(),
          tag: String.t(),
          isConsumed: boolean(),
          blockNumber: integer(),
          chainId: integer(),
          logicRef: String.t() | nil,
          quantity: integer() | nil,
          decodingStatus: String.t(),
          transaction: %{txHash: String.t()} | nil
        }

  @type action :: %{
          id: String.t(),
          actionTreeRoot: String.t(),
          tagCount: integer(),
          blockNumber: integer(),
          timestamp: integer()
        }

  @type stats :: %{
          transactions: integer(),
          resources: integer(),
          consumed: integer(),
          created: integer(),
          actions: integer(),
          compliances: integer(),
          logics: integer()
        }

  @doc """
  Gets aggregate statistics for the dashboard.

  Results are cached for 10 seconds to reduce API calls.
  Use `get_stats(skip_cache: true)` to bypass the cache.
  """
  @spec get_stats(keyword()) :: {:ok, stats()} | {:error, term()}
  def get_stats(opts \\ []) do
    skip_cache = Keyword.get(opts, :skip_cache, false)

    if skip_cache do
      fetch_stats()
    else
      Cache.get_or_compute(:dashboard_stats, @stats_cache_ttl, &fetch_stats/0)
    end
  end

  defp fetch_stats do
    query = """
    query {
      transactions: Transaction(limit: 1000) { id }
      resources: Resource(limit: 1000) { id isConsumed }
      actions: Action(limit: 1000) { id }
      compliances: ComplianceUnit(limit: 1000) { id }
      logics: LogicInput(limit: 1000) { id }
    }
    """

    case execute(query) do
      {:ok, data} ->
        resources = data["resources"] || []
        consumed = Enum.count(resources, & &1["isConsumed"])

        {:ok,
         %{
           transactions: length(data["transactions"] || []),
           resources: length(resources),
           consumed: consumed,
           created: length(resources) - consumed,
           actions: length(data["actions"] || []),
           compliances: length(data["compliances"] || []),
           logics: length(data["logics"] || [])
         }}

      error ->
        error
    end
  end

  @doc """
  Lists transactions with pagination and filtering.

  ## Options
    * `:limit` - Number of transactions to return (default: 20)
    * `:offset` - Number of transactions to skip (default: 0)
    * `:tx_hash` - Filter by transaction hash (partial match)
    * `:chain_id` - Filter by chain ID
    * `:block_min` - Minimum block number
    * `:block_max` - Maximum block number
    * `:contract_address` - Filter by contract address (partial match)
  """
  @spec list_transactions(keyword()) :: {:ok, [transaction()]} | {:error, term()}
  def list_transactions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    where_conditions = build_transaction_where(opts)
    where_clause = if where_conditions == "", do: "", else: ", where: {#{where_conditions}}"

    query = """
    query {
      Transaction(limit: #{limit}, offset: #{offset}, order_by: {blockNumber: desc}#{where_clause}) {
        id
        txHash
        blockNumber
        timestamp
        chainId
        tags
        logicRefs
      }
    }
    """

    case execute(query) do
      {:ok, %{"Transaction" => transactions}} ->
        {:ok, transactions}

      {:ok, _} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp build_transaction_where(opts) do
    conditions = []

    conditions =
      case Keyword.get(opts, :tx_hash) do
        nil -> conditions
        "" -> conditions
        hash -> conditions ++ ["txHash: {_ilike: \"%#{escape_string(hash)}%\"}"]
      end

    conditions =
      case Keyword.get(opts, :chain_id) do
        nil -> conditions
        "" -> conditions
        id when is_integer(id) -> conditions ++ ["chainId: {_eq: #{id}}"]
        id -> conditions ++ ["chainId: {_eq: #{id}}"]
      end

    conditions =
      case Keyword.get(opts, :block_min) do
        nil -> conditions
        "" -> conditions
        min when is_integer(min) -> conditions ++ ["blockNumber: {_gte: #{min}}"]
        min -> conditions ++ ["blockNumber: {_gte: #{min}}"]
      end

    conditions =
      case Keyword.get(opts, :block_max) do
        nil -> conditions
        "" -> conditions
        max when is_integer(max) -> conditions ++ ["blockNumber: {_lte: #{max}}"]
        max -> conditions ++ ["blockNumber: {_lte: #{max}}"]
      end

    conditions =
      case Keyword.get(opts, :contract_address) do
        nil -> conditions
        "" -> conditions
        addr -> conditions ++ ["contractAddress: {_ilike: \"%#{escape_string(addr)}%\"}"]
      end

    Enum.join(conditions, ", ")
  end

  @doc """
  Gets a single transaction by ID with related data.
  """
  @spec get_transaction(String.t()) :: {:ok, map()} | {:error, term()}
  def get_transaction(id) do
    query = """
    query {
      Transaction(where: {id: {_eq: "#{id}"}}) {
        id
        txHash
        blockNumber
        timestamp
        chainId
        contractAddress
        tags
        logicRefs
        resources {
          id
          tag
          isConsumed
          logicRef
          quantity
          decodingStatus
        }
        actions {
          id
          actionTreeRoot
          tagCount
        }
      }
    }
    """

    case execute(query) do
      {:ok, %{"Transaction" => [transaction | _]}} ->
        {:ok, transaction}

      {:ok, %{"Transaction" => []}} ->
        {:error, :not_found}

      {:ok, _} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  Lists resources with pagination and filtering.

  ## Options
    * `:limit` - Number of resources to return (default: 20)
    * `:offset` - Number of resources to skip (default: 0)
    * `:is_consumed` - Filter by consumed status (nil for all)
    * `:tag` - Filter by tag (partial match)
    * `:logic_ref` - Filter by logic ref (partial match)
    * `:chain_id` - Filter by chain ID
    * `:decoding_status` - Filter by decoding status (success/failed/pending)
    * `:block_min` - Minimum block number
    * `:block_max` - Maximum block number
  """
  @spec list_resources(keyword()) :: {:ok, [resource()]} | {:error, term()}
  def list_resources(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    where_conditions = build_resource_where(opts)
    where_clause = if where_conditions == "", do: "", else: ", where: {#{where_conditions}}"

    query = """
    query {
      Resource(limit: #{limit}, offset: #{offset}, order_by: {blockNumber: desc}#{where_clause}) {
        id
        tag
        isConsumed
        blockNumber
        chainId
        logicRef
        quantity
        decodingStatus
        transaction {
          id
          txHash
        }
      }
    }
    """

    case execute(query) do
      {:ok, %{"Resource" => resources}} ->
        {:ok, resources}

      {:ok, _} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp build_resource_where(opts) do
    conditions = []

    conditions =
      case Keyword.get(opts, :is_consumed) do
        nil -> conditions
        true -> conditions ++ ["isConsumed: {_eq: true}"]
        false -> conditions ++ ["isConsumed: {_eq: false}"]
      end

    conditions =
      case Keyword.get(opts, :tag) do
        nil -> conditions
        "" -> conditions
        tag -> conditions ++ ["tag: {_ilike: \"%#{escape_string(tag)}%\"}"]
      end

    conditions =
      case Keyword.get(opts, :logic_ref) do
        nil -> conditions
        "" -> conditions
        ref -> conditions ++ ["logicRef: {_ilike: \"%#{escape_string(ref)}%\"}"]
      end

    conditions =
      case Keyword.get(opts, :chain_id) do
        nil -> conditions
        "" -> conditions
        id when is_integer(id) -> conditions ++ ["chainId: {_eq: #{id}}"]
        id -> conditions ++ ["chainId: {_eq: #{id}}"]
      end

    conditions =
      case Keyword.get(opts, :decoding_status) do
        nil -> conditions
        "" -> conditions
        status -> conditions ++ ["decodingStatus: {_eq: \"#{escape_string(status)}\"}"]
      end

    conditions =
      case Keyword.get(opts, :block_min) do
        nil -> conditions
        "" -> conditions
        min when is_integer(min) -> conditions ++ ["blockNumber: {_gte: #{min}}"]
        min -> conditions ++ ["blockNumber: {_gte: #{min}}"]
      end

    conditions =
      case Keyword.get(opts, :block_max) do
        nil -> conditions
        "" -> conditions
        max when is_integer(max) -> conditions ++ ["blockNumber: {_lte: #{max}}"]
        max -> conditions ++ ["blockNumber: {_lte: #{max}}"]
      end

    Enum.join(conditions, ", ")
  end

  @doc """
  Gets a single resource by ID with full details.
  """
  @spec get_resource(String.t()) :: {:ok, map()} | {:error, term()}
  def get_resource(id) do
    query = """
    query {
      Resource(where: {id: {_eq: "#{id}"}}) {
        id
        tag
        index
        isConsumed
        blockNumber
        chainId
        logicRef
        labelRef
        valueRef
        nullifierKeyCommitment
        nonce
        randSeed
        quantity
        ephemeral
        rawBlob
        decodingStatus
        decodingError
        transaction {
          id
          txHash
          blockNumber
        }
      }
    }
    """

    case execute(query) do
      {:ok, %{"Resource" => [resource | _]}} ->
        {:ok, resource}

      {:ok, %{"Resource" => []}} ->
        {:error, :not_found}

      {:ok, _} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  Lists actions with pagination and filtering.

  ## Options
    * `:limit` - Number of actions to return (default: 20)
    * `:offset` - Number of actions to skip (default: 0)
    * `:action_tree_root` - Filter by action tree root (partial match)
    * `:chain_id` - Filter by chain ID
    * `:block_min` - Minimum block number
    * `:block_max` - Maximum block number
  """
  @spec list_actions(keyword()) :: {:ok, [action()]} | {:error, term()}
  def list_actions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    where_conditions = build_action_where(opts)
    where_clause = if where_conditions == "", do: "", else: ", where: {#{where_conditions}}"

    query = """
    query {
      Action(limit: #{limit}, offset: #{offset}, order_by: {blockNumber: desc}#{where_clause}) {
        id
        actionTreeRoot
        tagCount
        blockNumber
        chainId
        timestamp
        transaction {
          id
          txHash
        }
      }
    }
    """

    case execute(query) do
      {:ok, %{"Action" => actions}} ->
        {:ok, actions}

      {:ok, _} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp build_action_where(opts) do
    conditions = []

    conditions =
      case Keyword.get(opts, :action_tree_root) do
        nil -> conditions
        "" -> conditions
        root -> conditions ++ ["actionTreeRoot: {_ilike: \"%#{escape_string(root)}%\"}"]
      end

    conditions =
      case Keyword.get(opts, :chain_id) do
        nil -> conditions
        "" -> conditions
        id when is_integer(id) -> conditions ++ ["chainId: {_eq: #{id}}"]
        id -> conditions ++ ["chainId: {_eq: #{id}}"]
      end

    conditions =
      case Keyword.get(opts, :block_min) do
        nil -> conditions
        "" -> conditions
        min when is_integer(min) -> conditions ++ ["blockNumber: {_gte: #{min}}"]
        min -> conditions ++ ["blockNumber: {_gte: #{min}}"]
      end

    conditions =
      case Keyword.get(opts, :block_max) do
        nil -> conditions
        "" -> conditions
        max when is_integer(max) -> conditions ++ ["blockNumber: {_lte: #{max}}"]
        max -> conditions ++ ["blockNumber: {_lte: #{max}}"]
      end

    Enum.join(conditions, ", ")
  end

  @doc """
  Gets a single action by ID with related data.
  """
  @spec get_action(String.t()) :: {:ok, map()} | {:error, term()}
  def get_action(id) do
    query = """
    query {
      Action(where: {id: {_eq: "#{id}"}}) {
        id
        actionTreeRoot
        tagCount
        index
        blockNumber
        chainId
        timestamp
        transaction {
          id
          txHash
          blockNumber
        }
        complianceUnits {
          id
          consumedNullifier
          createdCommitment
          consumedLogicRef
          createdLogicRef
          unitDeltaX
          unitDeltaY
        }
        logicInputs {
          id
          tag
          isConsumed
          verifyingKey
        }
      }
    }
    """

    case execute(query) do
      {:ok, %{"Action" => [action | _]}} ->
        {:ok, action}

      {:ok, %{"Action" => []}} ->
        {:error, :not_found}

      {:ok, _} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  Lists compliance units with pagination and filtering.

  ## Options
    * `:limit` - Number of compliance units to return (default: 20)
    * `:offset` - Number of compliance units to skip (default: 0)
    * `:nullifier` - Filter by consumed nullifier (partial match)
    * `:commitment` - Filter by created commitment (partial match)
    * `:logic_ref` - Filter by consumed or created logic ref (partial match)
  """
  @spec list_compliance_units(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_compliance_units(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    where_conditions = build_compliance_where(opts)
    where_clause = if where_conditions == "", do: "", else: ", where: {#{where_conditions}}"

    query = """
    query {
      ComplianceUnit(limit: #{limit}, offset: #{offset}#{where_clause}) {
        id
        index
        consumedNullifier
        createdCommitment
        consumedLogicRef
        createdLogicRef
        consumedCommitmentTreeRoot
        unitDeltaX
        unitDeltaY
        action {
          id
          blockNumber
          chainId
          timestamp
          transaction {
            id
            txHash
          }
        }
      }
    }
    """

    case execute(query) do
      {:ok, %{"ComplianceUnit" => units}} ->
        {:ok, units}

      {:ok, _} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp build_compliance_where(opts) do
    conditions = []

    conditions =
      case Keyword.get(opts, :nullifier) do
        nil -> conditions
        "" -> conditions
        nf -> conditions ++ ["consumedNullifier: {_ilike: \"%#{escape_string(nf)}%\"}"]
      end

    conditions =
      case Keyword.get(opts, :commitment) do
        nil -> conditions
        "" -> conditions
        cm -> conditions ++ ["createdCommitment: {_ilike: \"%#{escape_string(cm)}%\"}"]
      end

    conditions =
      case Keyword.get(opts, :logic_ref) do
        nil ->
          conditions

        "" ->
          conditions

        ref ->
          conditions ++
            [
              "_or: [{consumedLogicRef: {_ilike: \"%#{escape_string(ref)}%\"}}, {createdLogicRef: {_ilike: \"%#{escape_string(ref)}%\"}}]"
            ]
      end

    Enum.join(conditions, ", ")
  end

  @doc """
  Gets a single compliance unit by ID with related data.
  """
  @spec get_compliance_unit(String.t()) :: {:ok, map()} | {:error, term()}
  def get_compliance_unit(id) do
    query = """
    query {
      ComplianceUnit(where: {id: {_eq: "#{id}"}}) {
        id
        index
        consumedNullifier
        createdCommitment
        consumedLogicRef
        createdLogicRef
        consumedCommitmentTreeRoot
        unitDeltaX
        unitDeltaY
        proof
        consumedResource {
          id
          tag
          logicRef
        }
        createdResource {
          id
          tag
          logicRef
        }
        action {
          id
          actionTreeRoot
          blockNumber
          chainId
          timestamp
          transaction {
            id
            txHash
          }
        }
      }
    }
    """

    case execute(query) do
      {:ok, %{"ComplianceUnit" => [unit | _]}} ->
        {:ok, unit}

      {:ok, %{"ComplianceUnit" => []}} ->
        {:error, :not_found}

      {:ok, _} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  Lists logic inputs with pagination and filtering.

  ## Options
    * `:limit` - Number of logic inputs to return (default: 20)
    * `:offset` - Number of logic inputs to skip (default: 0)
    * `:tag` - Filter by tag (partial match)
    * `:is_consumed` - Filter by consumed status
    * `:verifying_key` - Filter by verifying key (partial match)
  """
  @spec list_logic_inputs(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_logic_inputs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    where_conditions = build_logic_input_where(opts)
    where_clause = if where_conditions == "", do: "", else: ", where: {#{where_conditions}}"

    query = """
    query {
      LogicInput(limit: #{limit}, offset: #{offset}#{where_clause}) {
        id
        index
        tag
        isConsumed
        verifyingKey
        applicationPayloadCount
        discoveryPayloadCount
        externalPayloadCount
        resourcePayloadCount
        action {
          id
          blockNumber
          chainId
          timestamp
          transaction {
            id
            txHash
          }
        }
        resource {
          id
          tag
        }
      }
    }
    """

    case execute(query) do
      {:ok, %{"LogicInput" => inputs}} ->
        {:ok, inputs}

      {:ok, _} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp build_logic_input_where(opts) do
    conditions = []

    conditions =
      case Keyword.get(opts, :tag) do
        nil -> conditions
        "" -> conditions
        tag -> conditions ++ ["tag: {_ilike: \"%#{escape_string(tag)}%\"}"]
      end

    conditions =
      case Keyword.get(opts, :is_consumed) do
        nil -> conditions
        true -> conditions ++ ["isConsumed: {_eq: true}"]
        false -> conditions ++ ["isConsumed: {_eq: false}"]
      end

    conditions =
      case Keyword.get(opts, :verifying_key) do
        nil -> conditions
        "" -> conditions
        key -> conditions ++ ["verifyingKey: {_ilike: \"%#{escape_string(key)}%\"}"]
      end

    Enum.join(conditions, ", ")
  end

  @doc """
  Gets a single logic input by ID with related data.
  """
  @spec get_logic_input(String.t()) :: {:ok, map()} | {:error, term()}
  def get_logic_input(id) do
    query = """
    query {
      LogicInput(where: {id: {_eq: "#{id}"}}) {
        id
        index
        tag
        isConsumed
        verifyingKey
        proof
        applicationPayloadCount
        discoveryPayloadCount
        externalPayloadCount
        resourcePayloadCount
        action {
          id
          actionTreeRoot
          blockNumber
          chainId
          timestamp
          transaction {
            id
            txHash
          }
        }
        resource {
          id
          tag
          logicRef
          isConsumed
        }
      }
    }
    """

    case execute(query) do
      {:ok, %{"LogicInput" => [input | _]}} ->
        {:ok, input}

      {:ok, %{"LogicInput" => []}} ->
        {:error, :not_found}

      {:ok, _} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  Lists commitment tree roots with pagination and filtering.

  ## Options
    * `:limit` - Number of roots to return (default: 20)
    * `:offset` - Number of roots to skip (default: 0)
    * `:root` - Filter by root hash (partial match)
    * `:tx_hash` - Filter by transaction hash (partial match)
    * `:chain_id` - Filter by chain ID
    * `:block_min` - Minimum block number
    * `:block_max` - Maximum block number
  """
  @spec list_commitment_roots(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_commitment_roots(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    where_conditions = build_commitment_root_where(opts)
    where_clause = if where_conditions == "", do: "", else: ", where: {#{where_conditions}}"

    query = """
    query {
      CommitmentTreeRoot(limit: #{limit}, offset: #{offset}, order_by: {blockNumber: desc}#{where_clause}) {
        id
        root
        index
        blockNumber
        chainId
        timestamp
        txHash
      }
    }
    """

    case execute(query) do
      {:ok, %{"CommitmentTreeRoot" => roots}} ->
        {:ok, roots}

      {:ok, _} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp build_commitment_root_where(opts) do
    conditions = []

    conditions =
      case Keyword.get(opts, :root) do
        nil -> conditions
        "" -> conditions
        root -> conditions ++ ["root: {_ilike: \"%#{escape_string(root)}%\"}"]
      end

    conditions =
      case Keyword.get(opts, :tx_hash) do
        nil -> conditions
        "" -> conditions
        hash -> conditions ++ ["txHash: {_ilike: \"%#{escape_string(hash)}%\"}"]
      end

    conditions =
      case Keyword.get(opts, :chain_id) do
        nil -> conditions
        "" -> conditions
        id when is_integer(id) -> conditions ++ ["chainId: {_eq: #{id}}"]
        id -> conditions ++ ["chainId: {_eq: #{id}}"]
      end

    conditions =
      case Keyword.get(opts, :block_min) do
        nil -> conditions
        "" -> conditions
        min when is_integer(min) -> conditions ++ ["blockNumber: {_gte: #{min}}"]
        min -> conditions ++ ["blockNumber: {_gte: #{min}}"]
      end

    conditions =
      case Keyword.get(opts, :block_max) do
        nil -> conditions
        "" -> conditions
        max when is_integer(max) -> conditions ++ ["blockNumber: {_lte: #{max}}"]
        max -> conditions ++ ["blockNumber: {_lte: #{max}}"]
      end

    Enum.join(conditions, ", ")
  end

  @doc """
  Gets a single commitment tree root by ID.
  """
  @spec get_commitment_root(String.t()) :: {:ok, map()} | {:error, term()}
  def get_commitment_root(id) do
    query = """
    query {
      CommitmentTreeRoot(where: {id: {_eq: "#{id}"}}) {
        id
        root
        index
        blockNumber
        chainId
        timestamp
        txHash
      }
    }
    """

    case execute(query) do
      {:ok, %{"CommitmentTreeRoot" => [root | _]}} ->
        {:ok, root}

      {:ok, %{"CommitmentTreeRoot" => []}} ->
        {:error, :not_found}

      {:ok, _} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  Lists nullifiers from compliance units with pagination and filtering.
  Nullifiers are extracted from compliance units' consumedNullifier field.

  ## Options
    * `:limit` - Number of nullifiers to return (default: 20)
    * `:offset` - Number of nullifiers to skip (default: 0)
    * `:nullifier` - Filter by nullifier hash (partial match)
  """
  @spec list_nullifiers(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_nullifiers(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    where_conditions = build_nullifier_where(opts)
    additional_where = if where_conditions == "", do: "", else: ", " <> where_conditions

    query = """
    query {
      ComplianceUnit(limit: #{limit}, offset: #{offset}, where: {consumedNullifier: {_is_null: false}#{additional_where}}) {
        id
        consumedNullifier
        consumedLogicRef
        consumedCommitmentTreeRoot
        consumedResource {
          id
          tag
        }
        action {
          id
          blockNumber
          chainId
          timestamp
          transaction {
            id
            txHash
          }
        }
      }
    }
    """

    case execute(query) do
      {:ok, %{"ComplianceUnit" => units}} ->
        {:ok, units}

      {:ok, _} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp build_nullifier_where(opts) do
    conditions = []

    conditions =
      case Keyword.get(opts, :nullifier) do
        nil -> conditions
        "" -> conditions
        nf -> conditions ++ ["consumedNullifier: {_ilike: \"%#{escape_string(nf)}%\"}"]
      end

    Enum.join(conditions, ", ")
  end

  @doc """
  Lists commitments from compliance units with pagination and filtering.
  Commitments are extracted from compliance units' createdCommitment field.

  ## Options
    * `:limit` - Number of commitments to return (default: 20)
    * `:offset` - Number of commitments to skip (default: 0)
    * `:commitment` - Filter by commitment hash (partial match)
  """
  @spec list_commitments(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_commitments(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    where_conditions = build_commitment_where(opts)
    additional_where = if where_conditions == "", do: "", else: ", " <> where_conditions

    query = """
    query {
      ComplianceUnit(limit: #{limit}, offset: #{offset}, where: {createdCommitment: {_is_null: false}#{additional_where}}) {
        id
        createdCommitment
        createdLogicRef
        createdResource {
          id
          tag
        }
        action {
          id
          blockNumber
          chainId
          timestamp
          transaction {
            id
            txHash
          }
        }
      }
    }
    """

    case execute(query) do
      {:ok, %{"ComplianceUnit" => units}} ->
        {:ok, units}

      {:ok, _} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp build_commitment_where(opts) do
    conditions = []

    conditions =
      case Keyword.get(opts, :commitment) do
        nil -> conditions
        "" -> conditions
        cm -> conditions ++ ["createdCommitment: {_ilike: \"%#{escape_string(cm)}%\"}"]
      end

    Enum.join(conditions, ", ")
  end

  @doc """
  Executes a raw GraphQL query for the playground.
  Returns the full response including data and errors.
  """
  @spec execute_raw(String.t()) :: {:ok, map()} | {:error, term()}
  def execute_raw(query) do
    case get_url() do
      nil ->
        {:error, :not_configured}

      "" ->
        {:error, :not_configured}

      url ->
        do_raw_request(url, query)
    end
  end

  defp do_raw_request(url, query) do
    http_client().post_graphql_raw(url, query, @raw_timeout, @default_connect_timeout)
  end

  # ============================================
  # Private Helpers
  # ============================================

  # Escapes a string for safe inclusion in GraphQL queries.
  # Handles backslashes, quotes, newlines, tabs, and SQL LIKE wildcards.
  defp escape_string(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp escape_string(other), do: escape_string(to_string(other))

  defp execute(query) do
    case get_url() do
      nil ->
        {:error, :not_configured}

      "" ->
        {:error, :not_configured}

      url ->
        do_request(url, query)
    end
  end

  defp get_url do
    Settings.get_envio_url()
  end

  defp do_request(url, query) do
    http_client().post_graphql(url, query, @default_timeout, @default_connect_timeout)
  end

  # Returns the HTTP client module to use (allows mocking in tests)
  defp http_client do
    Application.get_env(:anoma_explorer, :graphql_http_client, __MODULE__)
  end

  @doc false
  # Default HTTP client implementation using :httpc
  # Note: SSL options simplified for OTP 28 compatibility
  def post_graphql(url, query, timeout, connect_timeout) do
    :inets.start()
    :ssl.start()

    body = Jason.encode!(%{query: query})
    request = {to_charlist(url), [{~c"content-type", ~c"application/json"}], ~c"application/json", body}

    # Simplified SSL options for OTP 28
    http_options = [
      timeout: timeout,
      connect_timeout: connect_timeout,
      ssl: [verify: :verify_none]
    ]

    case :httpc.request(:post, request, http_options, [body_format: :binary]) do
      {:ok, {{_http_version, 200, _reason}, _headers, response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => data}} ->
            {:ok, data}

          {:ok, %{"errors" => errors}} ->
            Logger.warning("GraphQL query returned errors", errors: errors)
            {:error, {:graphql_error, errors}}

          {:error, reason} ->
            Logger.error("Failed to decode GraphQL response", reason: inspect(reason))
            {:error, {:decode_error, reason}}
        end

      {:ok, {{_http_version, status, _reason}, _headers, response_body}} ->
        Logger.error("GraphQL HTTP error",
          status: status,
          body: String.slice(to_string(response_body), 0, 500)
        )

        {:error, {:http_error, status, response_body}}

      {:error, reason} ->
        Logger.error("GraphQL connection error", reason: inspect(reason))
        {:error, {:connection_error, reason}}
    end
  end

  @doc false
  # Raw request for playground - returns full response without extracting data
  def post_graphql_raw(url, query, timeout, connect_timeout) do
    :inets.start()
    :ssl.start()

    body = Jason.encode!(%{query: query})
    request = {to_charlist(url), [{~c"content-type", ~c"application/json"}], ~c"application/json", body}

    # Simplified SSL options for OTP 28
    http_options = [
      timeout: timeout,
      connect_timeout: connect_timeout,
      ssl: [verify: :verify_none]
    ]

    case :httpc.request(:post, request, http_options, [body_format: :binary]) do
      {:ok, {{_http_version, 200, _reason}, _headers, response_body}} ->
        case Jason.decode(response_body) do
          {:ok, response} ->
            {:ok, response}

          {:error, reason} ->
            {:error, {:decode_error, reason}}
        end

      {:ok, {{_http_version, status, _reason}, _headers, response_body}} ->
        {:error, {:http_error, status, response_body}}

      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  end
end
