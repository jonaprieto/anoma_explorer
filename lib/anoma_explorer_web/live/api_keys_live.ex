defmodule AnomaExplorerWeb.ApiKeysLive do
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "API Keys")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/settings/api-keys">
      <div class="page-header">
        <div>
          <h1 class="page-title">API Keys</h1>
          <p class="text-sm text-base-content/70 mt-1">
            Manage API keys for external services
          </p>
        </div>
      </div>

      <div class="stat-card text-center py-12">
        <.icon name="hero-key" class="w-12 h-12 text-base-content/30 mx-auto mb-4" />
        <p class="text-base-content/70">API key management coming soon.</p>
      </div>
    </Layouts.app>
    """
  end
end
