defmodule AnomaExplorerWeb.Schema do
  @moduledoc """
  GraphQL schema for the Anoma Explorer API.

  Provides queries for PA-EVM transactions, actions, compliance units,
  resources, and related data.
  """
  use Absinthe.Schema

  import_types AnomaExplorerWeb.Schema.PaevmTypes

  query do
    import_fields :paevm_queries
  end

  # Uncomment to enable subscriptions
  # subscription do
  #   import_fields :paevm_subscriptions
  # end
end
