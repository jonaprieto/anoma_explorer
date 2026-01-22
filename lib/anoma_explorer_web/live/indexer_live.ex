defmodule AnomaExplorerWeb.IndexerLive do
  @moduledoc """
  LiveView for configuring the Envio Hyperindex GraphQL endpoint.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.AdminAuth
  alias AnomaExplorerWeb.Layouts
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
     |> assign(:testing, false)
     |> assign(:saving, false)}
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

  def handle_event("update_url", %{"url" => url}, socket) do
    {:noreply, assign(socket, :url_input, url)}
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
  def handle_event("test_connection", _params, socket) do
    url = socket.assigns.url_input

    if url == "" do
      {:noreply, assign(socket, :status, {:error, "No URL configured"})}
    else
      socket = assign(socket, :testing, true)
      send(self(), {:test_connection, url})
      {:noreply, socket}
    end
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
  def handle_info({:test_connection, url}, socket) do
    status = test_graphql_endpoint(url)

    {:noreply,
     socket
     |> assign(:testing, false)
     |> assign(:status, status)}
  end

  @impl true
  def handle_info({:settings_changed, {:app_setting_updated, _}}, socket) do
    url = Settings.get_envio_url() || ""
    {:noreply, assign(socket, :url, url)}
  end

  @impl true
  def handle_info({:settings_changed, _}, socket), do: {:noreply, socket}

  def handle_info(:admin_check_expiration, socket) do
    case AdminAuth.handle_info(:admin_check_expiration, socket) do
      {:handled, socket} -> {:noreply, socket}
      :not_handled -> {:noreply, socket}
    end
  end

  defp test_graphql_endpoint(url) do
    query = """
    {
      Transaction(limit: 1) { id }
    }
    """

    body = Jason.encode!(%{query: query})

    request =
      Finch.build(:post, url, [{"content-type", "application/json"}], body)

    case Finch.request(request, AnomaExplorer.Finch, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => _}} -> {:ok, "Connected successfully"}
          {:ok, %{"errors" => errors}} -> {:error, "GraphQL error: #{inspect(errors)}"}
          _ -> {:error, "Invalid response format"}
        end

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, "Connection failed: #{inspect(reason)}"}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/settings/indexer">
      <div class="page-header">
        <div>
          <h1 class="page-title">Indexer Settings</h1>
          <p class="text-sm text-base-content/70 mt-1">
            Configure the
            <a
              href="https://envio.dev"
              target="_blank"
              rel="noopener"
              class="link link-primary"
            >Envio Hyperindex</a>
            GraphQL endpoint for indexed blockchain data
          </p>
        </div>
        <.admin_status
          authorized={@admin_authorized}
          authorized_at={@admin_authorized_at}
          timeout_ms={@admin_timeout_ms}
        />
      </div>

      <div class="stat-card">
        <h2 class="text-lg font-semibold mb-4">GraphQL Endpoint</h2>

        <form phx-submit="save_url" phx-change="update_url" class="space-y-4">
          <div class="form-control">
            <label class="label">
              <span class="label-text">Envio GraphQL URL</span>
            </label>
            <div class="flex gap-2">
              <input
                type="url"
                name="url"
                value={@url_input}
                placeholder="https://indexer.dev.hyperindex.xyz/xxx/v1/graphql"
                class="input input-bordered flex-1 font-mono text-sm"
              />
              <button
                type="button"
                phx-click="test_connection"
                disabled={@testing}
                class="btn btn-outline"
              >
                <%= if @testing do %>
                  <span class="loading loading-spinner loading-sm"></span> Testing...
                <% else %>
                  Test Connection
                <% end %>
              </button>
              <.protected_button
                authorized={@admin_authorized}
                type="submit"
                disabled={@saving || @url_input == @url}
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
              <button
                type="button"
                phx-click={JS.dispatch("phx:copy", to: "#url-copy", detail: %{text: @url})}
                class="btn btn-ghost btn-sm"
                title="Copy URL"
              >
                <.icon name="hero-clipboard-document" class="h-4 w-4" />
              </button>
              <span id="url-copy"></span>
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
