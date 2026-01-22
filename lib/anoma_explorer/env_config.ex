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
    # Database Configuration
    %{
      name: "DATABASE_URL",
      description: "PostgreSQL database connection URL (postgresql://user:password@host:port/database)",
      required: true,
      env: :prod,
      category: :database,
      default: nil,
      secret: true
    },
    %{
      name: "POOL_SIZE",
      description: "Database connection pool size",
      required: false,
      env: :prod,
      category: :database,
      default: "10",
      secret: false
    },
    %{
      name: "ECTO_IPV6",
      description: "Enable IPv6 for database connections (set to 'true' or '1' to enable)",
      required: false,
      env: :prod,
      category: :database,
      default: nil,
      secret: false
    },
    # Phoenix Configuration
    %{
      name: "SECRET_KEY_BASE",
      description: "Secret key for signing/encrypting cookies and sessions (generate with: mix phx.gen.secret)",
      required: true,
      env: :prod,
      category: :phoenix,
      default: nil,
      secret: true
    },
    %{
      name: "PHX_HOST",
      description: "Hostname where the application will be accessible",
      required: false,
      env: :prod,
      category: :phoenix,
      default: nil,
      secret: false
    },
    %{
      name: "PHX_SERVER",
      description: "Enable the Phoenix server (set to true for releases)",
      required: false,
      env: :all,
      category: :phoenix,
      default: "true",
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
      name: "DNS_CLUSTER_QUERY",
      description: "DNS query for cluster discovery (optional, for production clustering)",
      required: false,
      env: :prod,
      category: :phoenix,
      default: nil,
      secret: false
    },
    # External Services
    %{
      name: "ENVIO_GRAPHQL_URL",
      description: "Envio Hyperindex GraphQL endpoint for indexed blockchain data",
      required: false,
      env: :all,
      category: :services,
      default: nil,
      secret: false
    },
    %{
      name: "ETHERSCAN_API_KEY",
      description: "Etherscan V2 API key for contract verification (single key works for all supported chains)",
      required: false,
      env: :all,
      category: :services,
      default: nil,
      secret: true
    },
    # Admin Configuration
    %{
      name: "ADMIN_SECRET_KEY",
      description: "Secret key for admin access to edit/delete settings in production",
      required: false,
      env: :prod,
      category: :admin,
      default: nil,
      secret: true
    },
    %{
      name: "ADMIN_TIMEOUT_MINUTES",
      description: "Admin session timeout in minutes",
      required: false,
      env: :prod,
      category: :admin,
      default: "30",
      secret: false
    }
  ]

  @categories %{
    database: %{
      title: "Database",
      description: "PostgreSQL database connection settings",
      order: 1
    },
    phoenix: %{
      title: "Phoenix Application",
      description: "Web server configuration",
      order: 2
    },
    services: %{
      title: "External Services",
      description: "Third-party API integrations",
      order: 3
    },
    admin: %{
      title: "Admin Access",
      description: "Production admin authorization settings",
      order: 4
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
