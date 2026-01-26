defmodule AnomaExplorerWeb.IndexerLive do
  @moduledoc """
  LiveView for configuring the Envio Hyperindex GraphQL endpoint.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.AdminAuth
  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.Indexer.Client
  alias AnomaExplorer.Settings

  on_mount {AdminAuth, :load_admin_state}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Settings.subscribe()

    url = Settings.get_envio_url() || ""

    {:ok,
     socket
     |> assign(:page_title, "Indexer Settings")
     |> assign(:url, url)
     |> assign(:url_input, url)
     |> assign(:status, nil)
     |> assign(:saving, false)
     |> assign(:auto_test_timer, nil)
     |> assign(:auto_testing, false)}
  end

  # Admin authorization events
  @impl true
  def handle_event(event, params, socket)
      when event in ~w(admin_show_unlock_modal admin_close_unlock_modal admin_verify_secret admin_logout) do
    case AdminAuth.handle_event(event, params, socket) do
      {:handled, socket} -> {:noreply, socket}
      :not_handled -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_url", %{"url" => url}, socket) do
    # Cancel any pending auto-test timer
    if socket.assigns.auto_test_timer do
      Process.cancel_timer(socket.assigns.auto_test_timer)
    end

    # Schedule auto-test after 2 seconds of inactivity
    timer =
      if url != "" do
        Process.send_after(self(), {:auto_test_connection, url}, 2000)
      else
        nil
      end

    {:noreply,
     socket
     |> assign(:url_input, url)
     |> assign(:status, nil)
     |> assign(:auto_test_timer, timer)
     |> assign(:auto_testing, url != "")}
  end

  @impl true
  def handle_event("save_url", %{"url" => url}, socket) do
    AdminAuth.require_admin(socket, fn ->
      socket = assign(socket, :saving, true)

      case Settings.set_envio_url(url) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:url, url)
           |> assign(:saving, false)
           |> put_flash(:info, "Indexer endpoint saved successfully")}

        {:error, _} ->
          {:noreply,
           socket
           |> assign(:saving, false)
           |> put_flash(:error, "Failed to save endpoint")}
      end
    end)
  end

  @impl true
  def handle_event("global_search", %{"query" => query}, socket) do
    query = String.trim(query)

    if query != "" do
      {:noreply, push_navigate(socket, to: "/transactions?search=#{URI.encode_www_form(query)}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:auto_test_connection, url}, socket) do
    # Only auto-test if the URL hasn't changed since the timer was set
    if socket.assigns.url_input == url do
      status = Client.test_connection(url)

      {:noreply,
       socket
       |> assign(:status, status)
       |> assign(:auto_test_timer, nil)
       |> assign(:auto_testing, false)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:settings_changed, {:app_setting_updated, _}}, socket) do
    url = Settings.get_envio_url() || ""
    # Update both @url and @url_input to avoid race condition where
    # the input field shows stale data after external updates
    {:noreply, socket |> assign(:url, url) |> assign(:url_input, url)}
  end

  @impl true
  def handle_info({:settings_changed, _}, socket), do: {:noreply, socket}

  # Admin authorization info messages
  def handle_info(:admin_check_expiration, socket) do
    case AdminAuth.handle_info(:admin_check_expiration, socket) do
      {:handled, socket} -> {:noreply, socket}
      :not_handled -> {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/settings/indexer">
      <div class="mb-8">
        <div class="flex items-center gap-3 mb-2">
          <div class="p-2.5 bg-primary/10 rounded-xl">
            <.icon name="hero-server-stack" class="w-6 h-6 text-primary" />
          </div>
          <div>
            <h1 class="text-2xl font-bold text-base-content">Indexer Settings</h1>
          </div>
        </div>
        <p class="text-sm text-base-content/60 ml-[52px]">
          Configure the
          <a
            href="https://envio.dev"
            target="_blank"
            rel="noopener"
            class="link link-primary hover:link-primary/80"
          >
            Envio Hyperindex
          </a>
          GraphQL endpoint for indexed blockchain data
        </p>
      </div>

      <div class="stat-card">
        <h2 class="text-lg font-semibold mb-4">GraphQL Endpoint</h2>

        <form phx-submit="save_url" phx-change="update_url" class="space-y-4">
          <div class="form-control">
            <label class="label">
              <span class="label-text">Envio GraphQL URL</span>
            </label>
            <div class="flex gap-2 items-center">
              <div class="relative flex-1">
                <input
                  type="url"
                  id="envio-url-input"
                  name="url"
                  value={@url_input}
                  placeholder="https://indexer.dev.hyperindex.xyz/xxx/v1/graphql"
                  class="input input-bordered w-full font-mono text-sm pr-8"
                />
                <div class="absolute right-2 top-1/2 -translate-y-1/2">
                  <%= if @auto_testing do %>
                    <span class="loading loading-spinner loading-xs text-base-content/50"></span>
                  <% else %>
                    <%= if @status do %>
                      <div class={[
                        "w-3 h-3 rounded-full",
                        if(elem(@status, 0) == :ok, do: "bg-success", else: "bg-error")
                      ]} title={elem(@status, 1)}>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>
              <.protected_button
                authorized={@admin_authorized}
                type="submit"
                disabled={@saving}
                class="btn btn-primary"
              >
                <%= if @saving do %>
                  <span class="loading loading-spinner loading-sm"></span> Saving...
                <% else %>
                  Save
                <% end %>
              </.protected_button>
            </div>
            <label class="label">
              <span class="label-text-alt text-base-content/50">
                The GraphQL endpoint URL from your Envio Hyperindex deployment
              </span>
            </label>
          </div>
        </form>

        <%= if @status do %>
          <div class={[
            "alert mt-4",
            if(elem(@status, 0) == :ok, do: "alert-success", else: "alert-error")
          ]}>
            <.icon
              name={if elem(@status, 0) == :ok, do: "hero-check-circle", else: "hero-x-circle"}
              class="h-5 w-5"
            />
            <span>{elem(@status, 1)}</span>
          </div>
        <% end %>

        <%= if @url != "" do %>
          <div class="mt-6 pt-4 border-t border-base-300">
            <h3 class="text-sm font-semibold mb-2">Current Configuration</h3>
            <div class="flex items-center gap-2">
              <code class="text-sm font-mono bg-base-200 px-2 py-1 rounded flex-1 overflow-x-auto">
                {@url}
              </code>
              <.copy_button text={@url} tooltip="Copy URL" size="sm" />
            </div>
          </div>
        <% end %>
      </div>

      <div class="stat-card mt-6">
        <h3 class="text-sm font-semibold mb-2">Usage Notes</h3>
        <ul class="text-sm text-base-content/70 space-y-1 list-disc list-inside">
          <li>The URL is stored in the database and persists across restarts</li>
          <li>
            Falls back to <code class="bg-base-200 px-1 rounded">ENVIO_GRAPHQL_URL</code>
            environment variable if not set
          </li>
          <li>Use "Test Connection" to verify the endpoint is accessible</li>
          <li>Changes take effect immediately for new dashboard queries</li>
        </ul>
      </div>

      <.unlock_modal show={@admin_show_unlock_modal} error={@admin_error} />
    </Layouts.app>
    """
  end
end
