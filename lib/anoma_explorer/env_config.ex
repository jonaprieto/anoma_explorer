defmodule AnomaExplorer.EnvConfig do
  @moduledoc """
  Defines and manages environment variables configuration for the application.

  This module serves as the single source of truth for all environment variables
  used by the application. It provides metadata for documentation and UI display.
  """

  @type env_var :: %{
          name: String.t(),
          description: String.t(),
          required: boolean(),
          env: :all | :prod | :dev | :test,
          category: atom(),
          default: String.t() | nil
        }

  @env_vars [
    # Alchemy API Configuration
    %{
      name: "ALCHEMY_API_KEY",
      description: "Alchemy API key for blockchain RPC access",
      required: true,
      env: :all,
      category: :alchemy,
      default: nil,
      secret: true
    },
    %{
      name: "ALCHEMY_NETWORKS",
      description: "Comma-separated list of networks (e.g., eth-mainnet,base-sepolia)",
      required: true,
      env: :all,
      category: :alchemy,
      default: nil,
      secret: false
    },
    %{
      name: "CONTRACT_ADDRESS",
      description: "Ethereum contract address to monitor (0x...)",
      required: true,
      env: :all,
      category: :alchemy,
      default: nil,
      secret: false
    },
    %{
      name: "POLL_INTERVAL_SECONDS",
      description: "Polling interval for blockchain data",
      required: false,
      env: :all,
      category: :alchemy,
      default: "20",
      secret: false
    },
    %{
      name: "START_BLOCK",
      description: "Starting block number for ingestion",
      required: false,
      env: :all,
      category: :alchemy,
      default: nil,
      secret: false
    },
    %{
      name: "BACKFILL_BLOCKS",
      description: "Number of blocks to backfill",
      required: false,
      env: :all,
      category: :alchemy,
      default: "50000",
      secret: false
    },
    %{
      name: "PAGE_SIZE",
      description: "Results per page for API requests",
      required: false,
      env: :all,
      category: :alchemy,
      default: "100",
      secret: false
    },
    %{
      name: "MAX_REQ_PER_SECOND",
      description: "Rate limit for Alchemy requests",
      required: false,
      env: :all,
      category: :alchemy,
      default: "5",
      secret: false
    },
    %{
      name: "LOG_CHUNK_BLOCKS",
      description: "Block chunk size for log queries",
      required: false,
      env: :all,
      category: :alchemy,
      default: "2000",
      secret: false
    },
    # Etherscan API
    %{
      name: "ETHERSCAN_API_KEY",
      description: "Etherscan V2 API key for contract verification",
      required: false,
      env: :all,
      category: :etherscan,
      default: nil,
      secret: true
    },
    # Phoenix Configuration
    %{
      name: "DATABASE_URL",
      description: "PostgreSQL database connection URL",
      required: true,
      env: :prod,
      category: :phoenix,
      default: nil,
      secret: true
    },
    %{
      name: "SECRET_KEY_BASE",
      description: "Secret key for signing/encrypting cookies and sessions",
      required: true,
      env: :prod,
      category: :phoenix,
      default: nil,
      secret: true
    },
    %{
      name: "PHX_HOST",
      description: "Hostname for the Phoenix application",
      required: false,
      env: :prod,
      category: :phoenix,
      default: "example.com",
      secret: false
    },
    %{
      name: "PORT",
      description: "HTTP port for the web server",
      required: false,
      env: :all,
      category: :phoenix,
      default: "4000",
      secret: false
    },
    %{
      name: "PHX_SERVER",
      description: "Enable the Phoenix server (set to true for releases)",
      required: false,
      env: :all,
      category: :phoenix,
      default: nil,
      secret: false
    },
    %{
      name: "POOL_SIZE",
      description: "Database connection pool size",
      required: false,
      env: :prod,
      category: :phoenix,
      default: "10",
      secret: false
    },
    %{
      name: "ECTO_IPV6",
      description: "Enable IPv6 for database connections",
      required: false,
      env: :prod,
      category: :phoenix,
      default: nil,
      secret: false
    },
    %{
      name: "DNS_CLUSTER_QUERY",
      description: "DNS query for cluster discovery",
      required: false,
      env: :prod,
      category: :phoenix,
      default: nil,
      secret: false
    }
  ]

  @categories %{
    alchemy: %{
      title: "Alchemy API",
      description: "Configuration for blockchain data ingestion via Alchemy",
      order: 1
    },
    etherscan: %{
      title: "Etherscan API",
      description: "Contract verification and chain explorer integration",
      order: 2
    },
    phoenix: %{
      title: "Phoenix Application",
      description: "Web server and database configuration",
      order: 3
    }
  }

  @doc """
  Returns all environment variable definitions.
  """
  @spec all() :: [env_var()]
  def all, do: @env_vars

  @doc """
  Returns environment variables grouped by category.
  """
  @spec grouped_by_category() :: %{atom() => [env_var()]}
  def grouped_by_category do
    Enum.group_by(@env_vars, & &1.category)
  end

  @doc """
  Returns category metadata.
  """
  @spec categories() :: map()
  def categories, do: @categories

  @doc """
  Returns category metadata for a specific category.
  """
  @spec category(atom()) :: map() | nil
  def category(name), do: Map.get(@categories, name)

  @doc """
  Returns all categories sorted by order.
  """
  @spec sorted_categories() :: [{atom(), map()}]
  def sorted_categories do
    @categories
    |> Enum.sort_by(fn {_key, meta} -> meta.order end)
  end

  @doc """
  Returns environment variables for a specific category.
  """
  @spec for_category(atom()) :: [env_var()]
  def for_category(category) do
    Enum.filter(@env_vars, &(&1.category == category))
  end

  @doc """
  Returns all required environment variables.
  """
  @spec required() :: [env_var()]
  def required do
    Enum.filter(@env_vars, & &1.required)
  end

  @doc """
  Returns all secret environment variables.
  """
  @spec secrets() :: [env_var()]
  def secrets do
    Enum.filter(@env_vars, & &1.secret)
  end

  @doc """
  Loads current values for all environment variables.
  Returns a list of maps with :value and :is_set fields added.
  """
  @spec load_with_values() :: [map()]
  def load_with_values do
    Enum.map(@env_vars, fn var ->
      value = System.get_env(var.name)

      Map.merge(var, %{
        value: value,
        is_set: not is_nil(value)
      })
    end)
  end

  @doc """
  Loads current values grouped by category.
  """
  @spec load_grouped_with_values() :: %{atom() => [map()]}
  def load_grouped_with_values do
    load_with_values()
    |> Enum.group_by(& &1.category)
  end

  @doc """
  Checks if all required environment variables are set.
  Returns {:ok, :valid} or {:error, missing_vars}.
  """
  @spec validate_required() :: {:ok, :valid} | {:error, [String.t()]}
  def validate_required do
    missing =
      required()
      |> Enum.filter(fn var ->
        value = System.get_env(var.name)
        is_nil(value) or value == ""
      end)
      |> Enum.map(& &1.name)

    if Enum.empty?(missing) do
      {:ok, :valid}
    else
      {:error, missing}
    end
  end
end
