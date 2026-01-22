defmodule AnomaExplorer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AnomaExplorerWeb.Telemetry,
      AnomaExplorer.Repo,
      {DNSCluster, query: Application.get_env(:anoma_explorer, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AnomaExplorer.PubSub},
      # HTTP client pool
      {Finch, name: AnomaExplorer.Finch},
      # Rate limiter for API calls
      AnomaExplorer.RateLimiter,
      # Settings cache (must be after Repo)
      AnomaExplorer.Settings.Cache,
      # Background job processing
      {Oban, Application.fetch_env!(:anoma_explorer, Oban)},
      # Contract monitoring manager (auto-starts ingestion for active addresses)
      AnomaExplorer.Settings.MonitoringManager,
      # Start to serve requests, typically the last entry
      AnomaExplorerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AnomaExplorer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AnomaExplorerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
