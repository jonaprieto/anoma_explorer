defmodule AnomaExplorerWeb.Router do
  use AnomaExplorerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AnomaExplorerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", AnomaExplorerWeb do
    pipe_through :browser

    live "/", HomeLive, :index

    # Transaction routes
    live "/transactions", TransactionsLive, :index
    live "/transactions/:id", TransactionLive, :show

    # Resource routes
    live "/resources", ResourcesLive, :index
    live "/resources/:id", ResourceLive, :show

    # Action routes
    live "/actions", ActionsLive, :index
    live "/actions/:id", ActionLive, :show

    # Compliance routes
    live "/compliances", CompliancesLive, :index
    live "/compliances/:id", ComplianceLive, :show

    # Logic routes
    live "/logics", LogicsLive, :index
    live "/logics/:id", LogicLive, :show

    # Commitment routes
    live "/commitments", CommitmentsLive, :index

    # Nullifier routes
    live "/nullifiers", NullifiersLive, :index

    # GraphQL Playground
    live "/playground", PlaygroundLive, :index

    # Settings routes
    get "/settings", PageController, :settings_redirect
    live "/settings/contracts", SettingsLive, :index
    live "/settings/networks", NetworksLive, :index
    live "/settings/indexer", IndexerLive, :index
  end

  # Environment/API Keys page - only available in dev/test
  if Application.compile_env(:anoma_explorer, :env) != :prod do
    scope "/settings", AnomaExplorerWeb do
      pipe_through :browser

      live "/api-keys", ApiKeysLive, :index
    end
  end
end
