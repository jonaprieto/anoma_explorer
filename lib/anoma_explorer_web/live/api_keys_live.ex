defmodule AnomaExplorerWeb.ApiKeysLive do
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.EnvConfig

  @impl true
  def mount(_params, _session, socket) do
    grouped_vars = EnvConfig.load_grouped_with_values()
    categories = EnvConfig.sorted_categories()

    {:ok,
     socket
     |> assign(:page_title, "Environment Variables")
     |> assign(:grouped_vars, grouped_vars)
     |> assign(:categories, categories)
     |> assign(:current_env, config_env())}
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
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/settings/api-keys">
      <div class="page-header">
        <div>
          <h1 class="page-title">Environment Variables</h1>
          <p class="text-sm text-base-content/70 mt-1">
            Configuration variables required to run the application
          </p>
        </div>
        <div class="badge badge-outline">
          {String.upcase(to_string(@current_env))}
        </div>
      </div>

      <div class="space-y-6">
        <%= for {category_key, category_meta} <- @categories do %>
          <.env_section
            title={category_meta.title}
            description={category_meta.description}
            vars={@grouped_vars[category_key] || []}
          />
        <% end %>
      </div>

      <div class="mt-6 stat-card">
        <h3 class="text-sm font-semibold mb-2">Usage Notes</h3>
        <ul class="text-sm text-base-content/70 space-y-1 list-disc list-inside">
          <li>
            <strong>Production</strong> variables are only required when running in production mode
          </li>
          <li><strong>All</strong> variables apply to all environments (dev, test, prod)</li>
          <li>Sensitive values like API keys and database URLs are partially hidden</li>
          <li>
            Generate a secret key with:
            <code class="bg-base-200 px-1 rounded">mix phx.gen.secret</code>
          </li>
          <li>
            Supported Alchemy networks: eth-mainnet, eth-sepolia, arb-mainnet, arb-sepolia, base-mainnet, base-sepolia, polygon-mainnet, polygon-amoy, optimism-mainnet, optimism-sepolia
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  defp env_section(assigns) do
    ~H"""
    <div class="stat-card">
      <div class="mb-4">
        <h2 class="text-lg font-semibold">{@title}</h2>
        <p class="text-sm text-base-content/60">{@description}</p>
      </div>
      <div class="overflow-x-auto">
        <table class="data-table w-full">
          <thead>
            <tr>
              <th>Variable</th>
              <th>Description</th>
              <th>Value</th>
              <th>Required</th>
              <th>Environment</th>
            </tr>
          </thead>
          <tbody>
            <%= for var <- @vars do %>
              <tr>
                <td>
                  <code class="text-sm font-mono bg-base-200 px-2 py-1 rounded">{var.name}</code>
                </td>
                <td class="text-sm text-base-content/70">
                  {var.description}
                  <%= if var.default do %>
                    <span class="text-base-content/40">(default: {var.default})</span>
                  <% end %>
                </td>
                <td>
                  <%= if var.value do %>
                    <div class="flex items-center gap-2">
                      <span
                        class="text-sm font-mono text-base-content/70"
                        title={if var.secret, do: "Value hidden for security", else: var.value}
                      >
                        {truncate_value(var.value, var.secret)}
                      </span>
                      <%= if var.secret do %>
                        <span class="badge badge-ghost badge-xs">hidden</span>
                      <% end %>
                    </div>
                  <% else %>
                    <span class="text-base-content/40 italic">not set</span>
                  <% end %>
                </td>
                <td>
                  <%= if var.required do %>
                    <span class="badge badge-error badge-sm">Required</span>
                  <% else %>
                    <span class="badge badge-ghost badge-sm">Optional</span>
                  <% end %>
                </td>
                <td>
                  <%= case var.env do %>
                    <% :prod -> %>
                      <span class="badge badge-warning badge-sm">Production</span>
                    <% :all -> %>
                      <span class="badge badge-info badge-sm">All</span>
                    <% _ -> %>
                      <span class="badge badge-ghost badge-sm">{var.env}</span>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp truncate_value(nil, _), do: nil

  defp truncate_value(value, true) when byte_size(value) > 8 do
    String.slice(value, 0, 4) <> "..." <> String.slice(value, -4, 4)
  end

  defp truncate_value(value, true), do: String.duplicate("*", String.length(value))

  defp truncate_value(value, false) when byte_size(value) > 40 do
    String.slice(value, 0, 37) <> "..."
  end

  defp truncate_value(value, false), do: value

  defp config_env do
    Application.get_env(:anoma_explorer, :env, :dev)
  end
end
