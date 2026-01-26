defmodule AnomaExplorerWeb.IndexerSetupComponents do
  @moduledoc """
  Reusable components for indexer configuration setup.

  Used across all views that require a working GraphQL endpoint.
  Provides setup forms and error displays.
  """
  use Phoenix.Component

  import AnomaExplorerWeb.CoreComponents

  @doc """
  Renders a configuration required card with embedded setup form.

  Shows when the indexer is not configured or not working.
  Includes URL input, auto-test indicator, and save button.

  ## Attributes

    * `url_input` - The current URL in the input field
    * `status` - Connection status: {:ok, msg} | {:error, msg} | nil
    * `auto_testing` - Whether auto-test is in progress
    * `saving` - Whether save is in progress
    * `title` - Card title (optional)
    * `description` - Card description (optional)
    * `show_link_to_settings` - Whether to show link to settings page (optional)
  """
  attr :url_input, :string, required: true
  attr :status, :any, default: nil
  attr :auto_testing, :boolean, default: false
  attr :saving, :boolean, default: false
  attr :title, :string, default: "Indexer Configuration Required"
  attr :description, :string, default: "Configure the Envio GraphQL endpoint to view indexed data."
  attr :show_link_to_settings, :boolean, default: true

  def setup_required(assigns) do
    ~H"""
    <div class="stat-card">
      <div class="flex items-start gap-4">
        <div class="w-14 h-14 rounded-xl bg-warning/10 flex items-center justify-center shrink-0">
          <.icon name="hero-server-stack" class="w-7 h-7 text-warning" />
        </div>
        <div class="flex-1 min-w-0">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <p class="text-sm text-base-content/70 mt-1">{@description}</p>

          <form phx-submit="setup_save_url" phx-change="setup_update_url" class="mt-4 space-y-3">
            <div class="form-control">
              <label class="label py-1">
                <span class="label-text text-sm">Envio GraphQL URL</span>
              </label>
              <div class="flex gap-2 items-center">
                <div class="relative flex-1">
                  <input
                    type="url"
                    name="url"
                    value={@url_input}
                    placeholder="https://indexer.dev.hyperindex.xyz/xxx/v1/graphql"
                    class="input input-bordered input-sm w-full font-mono text-sm pr-8"
                    required
                  />
                  <div class="absolute right-2 top-1/2 -translate-y-1/2">
                    <%= if @auto_testing do %>
                      <span class="loading loading-spinner loading-xs text-base-content/50"></span>
                    <% else %>
                      <%= if @status do %>
                        <div
                          class={[
                            "w-3 h-3 rounded-full",
                            if(elem(@status, 0) == :ok, do: "bg-success", else: "bg-error")
                          ]}
                          title={elem(@status, 1)}
                        >
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                </div>
                <button
                  type="submit"
                  disabled={@saving || @status == nil || elem(@status, 0) != :ok}
                  class="btn btn-primary btn-sm"
                >
                  <%= if @saving do %>
                    <span class="loading loading-spinner loading-sm"></span>
                  <% else %>
                    Save & Continue
                  <% end %>
                </button>
              </div>
            </div>
          </form>

          <%= if @status && elem(@status, 0) == :error do %>
            <div class="alert alert-error mt-3 py-2">
              <.icon name="hero-x-circle" class="h-4 w-4" />
              <span class="text-sm">{elem(@status, 1)}</span>
            </div>
          <% end %>

          <%= if @show_link_to_settings do %>
            <p class="text-xs text-base-content/50 mt-3">
              Or configure in <a href="/settings/indexer" class="link link-primary">Indexer Settings</a>
            </p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a connection error card with option to reconfigure.

  Shows when the configured endpoint is returning errors.

  ## Attributes

    * `error` - The error message to display
    * `url` - The current configured URL (optional)
    * `show_retry` - Whether to show retry button (optional)
    * `show_reconfigure` - Whether to show reconfigure link (optional)
  """
  attr :error, :string, required: true
  attr :url, :string, default: nil
  attr :show_retry, :boolean, default: true
  attr :show_reconfigure, :boolean, default: true

  def connection_error(assigns) do
    ~H"""
    <div class="stat-card border-error/30">
      <div class="flex items-start gap-4">
        <div class="w-14 h-14 rounded-xl bg-error/10 flex items-center justify-center shrink-0">
          <.icon name="hero-exclamation-triangle" class="w-7 h-7 text-error" />
        </div>
        <div class="flex-1 min-w-0">
          <h2 class="text-lg font-semibold text-base-content">Connection Error</h2>
          <p class="text-sm text-error/80 mt-1">{@error}</p>

          <%= if @url do %>
            <div class="mt-2 p-2 bg-base-200 rounded text-xs font-mono truncate">
              {@url}
            </div>
          <% end %>

          <div class="flex gap-2 mt-3">
            <%= if @show_retry do %>
              <button phx-click="retry_connection" class="btn btn-ghost btn-sm">
                <.icon name="hero-arrow-path" class="w-4 h-4" /> Retry
              </button>
            <% end %>
            <%= if @show_reconfigure do %>
              <a href="/settings/indexer" class="btn btn-primary btn-sm">
                <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> Reconfigure
              </a>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
