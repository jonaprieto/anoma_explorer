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

    get "/", PageController, :home

    # Settings routes
    get "/settings", PageController, :settings_redirect
    live "/settings/contracts", SettingsLive, :index
    live "/settings/networks", NetworksLive, :index
    live "/settings/api-keys", ApiKeysLive, :index
  end
end
