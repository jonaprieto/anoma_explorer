defmodule AnomaExplorerWeb.NullifiersLive do
  @moduledoc """
  LiveView for listing and filtering nullifiers.
  Nullifiers are extracted from compliance units' consumedNullifier field.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Client
  alias AnomaExplorer.Indexer.Networks

  @default_filters %{
    "nullifier" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Nullifiers")
      |> assign(:nullifiers, [])
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:page, 0)
      |> assign(:has_more, true)
      |> assign(:configured, Client.configured?())
      |> assign(:filters, @default_filters)
      |> assign(:show_filters, false)

    if connected?(socket) and Client.configured?() do
      send(self(), :load_nullifiers)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_nullifiers, socket) do
    {:noreply, load_nullifiers(socket)}
  end

  @impl true
  def handle_event("toggle_filters", _params, socket) do
    {:noreply, assign(socket, :show_filters, !socket.assigns.show_filters)}
  end

  @impl true
  def handle_event("apply_filters", %{"filters" => filters}, socket) do
    socket =
      socket
      |> assign(:filters, Map.merge(@default_filters, filters))
      |> assign(:page, 0)
      |> assign(:loading, true)
      |> load_nullifiers()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    socket =
      socket
      |> assign(:filters, @default_filters)
      |> assign(:page, 0)
      |> assign(:loading, true)
      |> load_nullifiers()

    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    if socket.assigns.page > 0 do
      socket =
        socket
        |> assign(:page, socket.assigns.page - 1)
        |> assign(:loading, true)
        |> load_nullifiers()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    if socket.assigns.has_more do
      socket =
        socket
        |> assign(:page, socket.assigns.page + 1)
        |> assign(:loading, true)
        |> load_nullifiers()

      {:noreply, socket}
    else
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

  defp load_nullifiers(socket) do
    page_size = 20
    filters = socket.assigns.filters

    opts =
      [limit: page_size + 1, offset: socket.assigns.page * page_size]
      |> maybe_add_filter(:nullifier, filters["nullifier"])

    case GraphQL.list_nullifiers(opts) do
      {:ok, nullifiers} ->
        has_more = length(nullifiers) > page_size

        socket
        |> assign(:nullifiers, Enum.take(nullifiers, page_size))
        |> assign(:has_more, has_more)
        |> assign(:loading, false)
        |> assign(:error, nil)

      {:error, :not_configured} ->
        socket
        |> assign(:nullifiers, [])
        |> assign(:loading, false)
        |> assign(:error, "Indexer endpoint not configured")

      {:error, reason} ->
        socket
        |> assign(:nullifiers, [])
        |> assign(:loading, false)
        |> assign(:error, "Failed to load nullifiers: #{inspect(reason)}")
    end
  end

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, _key, ""), do: opts
  defp maybe_add_filter(opts, key, value), do: Keyword.put(opts, key, value)

  defp active_filter_count(filters) do
    filters
    |> Map.values()
    |> Enum.count(&(&1 != "" and &1 != nil))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/nullifiers">
      <div class="page-header">
        <div>
          <h1 class="page-title">Nullifiers</h1>
          <p class="text-sm text-base-content/70 mt-1">
            All consumed nullifiers from compliance units
          </p>
        </div>
      </div>

      <%= if not @configured do %>
        <.not_configured_message />
      <% else %>
        <%= if @error do %>
          <div class="alert alert-error mb-6">
            <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
            <span>{@error}</span>
          </div>
        <% end %>

        <div class="stat-card">
          <.filter_toggle show_filters={@show_filters} filter_count={active_filter_count(@filters)} />
          <.filter_form :if={@show_filters} filters={@filters} />

          <%= if @loading and @nullifiers == [] do %>
            <.loading_skeleton />
          <% else %>
            <.nullifiers_table nullifiers={@nullifiers} />
          <% end %>

          <.pagination page={@page} has_more={@has_more} loading={@loading} />
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp filter_toggle(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-4">
      <button phx-click="toggle_filters" class="btn btn-ghost btn-sm gap-2">
        <.icon name="hero-funnel" class="w-4 h-4" /> Search
        <%= if @filter_count > 0 do %>
          <span class="badge badge-primary badge-sm">{@filter_count}</span>
        <% end %>
        <.icon
          name={if @show_filters, do: "hero-chevron-up", else: "hero-chevron-down"}
          class="w-4 h-4"
        />
      </button>
    </div>
    """
  end

  defp filter_form(assigns) do
    ~H"""
    <form phx-submit="apply_filters" class="mb-6 p-4 bg-base-200/50 rounded-lg">
      <div class="grid grid-cols-1 gap-4">
        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wide mb-1 block">
            Nullifier
          </label>
          <input
            type="text"
            name="filters[nullifier]"
            value={@filters["nullifier"]}
            placeholder="0x..."
            class="input input-bordered input-sm w-full"
          />
        </div>
      </div>

      <div class="flex justify-end gap-2 mt-4">
        <button type="button" phx-click="clear_filters" class="btn btn-ghost btn-sm">
          Clear Filters
        </button>
        <button type="submit" class="btn btn-primary btn-sm">
          <.icon name="hero-magnifying-glass" class="w-4 h-4" /> Apply Filters
        </button>
      </div>
    </form>
    """
  end

  defp not_configured_message(assigns) do
    ~H"""
    <div class="stat-card">
      <div class="flex items-center gap-4">
        <div class="w-14 h-14 rounded-xl bg-warning/10 flex items-center justify-center">
          <.icon name="hero-exclamation-triangle" class="w-7 h-7 text-warning" />
        </div>
        <div class="flex-1">
          <h2 class="text-lg font-semibold text-base-content">Indexer Not Configured</h2>
          <p class="text-sm text-base-content/70">
            Configure the Envio GraphQL endpoint in settings to view nullifiers.
          </p>
          <a href="/settings/indexer" class="btn btn-primary btn-sm mt-3">
            Configure Indexer
          </a>
        </div>
      </div>
    </div>
    """
  end

  defp loading_skeleton(assigns) do
    ~H"""
    <div class="animate-pulse space-y-3">
      <%= for _ <- 1..5 do %>
        <div class="h-12 bg-base-300 rounded"></div>
      <% end %>
    </div>
    """
  end

  defp nullifiers_table(assigns) do
    ~H"""
    <%= if @nullifiers == [] do %>
      <div class="text-center py-8 text-base-content/50">
        <.icon name="hero-no-symbol" class="w-12 h-12 mx-auto mb-2 opacity-50" />
        <p>No nullifiers found</p>
      </div>
    <% else %>
      <div class="overflow-x-auto">
        <table class="data-table w-full">
          <thead>
            <tr>
              <th>Nullifier</th>
              <th>Logic Ref</th>
              <th>Consumed Resource</th>
              <th>Network</th>
              <th>Block</th>
              <th>Transaction</th>
            </tr>
          </thead>
          <tbody>
            <%= for unit <- @nullifiers do %>
              <tr class="hover:bg-base-200/50">
                <td>
                  <div class="flex items-center gap-1">
                    <a
                      href={"/compliances/#{unit["id"]}"}
                      class="hash-display text-xs hover:text-primary"
                    >
                      {truncate_hash(unit["consumedNullifier"])}
                    </a>
                    <.copy_button
                      :if={unit["consumedNullifier"]}
                      text={unit["consumedNullifier"]}
                      tooltip="Copy nullifier"
                    />
                  </div>
                </td>
                <td>
                  <div class="flex items-center gap-1">
                    <code class="hash-display text-xs">{truncate_hash(unit["consumedLogicRef"])}</code>
                    <.copy_button
                      :if={unit["consumedLogicRef"]}
                      text={unit["consumedLogicRef"]}
                      tooltip="Copy logic ref"
                    />
                  </div>
                </td>
                <td>
                  <%= if unit["consumedResource"] do %>
                    <div class="flex items-center gap-1">
                      <a
                        href={"/resources/#{unit["consumedResource"]["id"]}"}
                        class="hash-display text-xs hover:text-primary"
                      >
                        {truncate_hash(unit["consumedResource"]["tag"])}
                      </a>
                      <.copy_button
                        :if={unit["consumedResource"]["tag"]}
                        text={unit["consumedResource"]["tag"]}
                        tooltip="Copy tag"
                      />
                    </div>
                  <% else %>
                    -
                  <% end %>
                </td>
                <td>
                  <%= if unit["action"] do %>
                    <span
                      class="text-sm text-base-content/70"
                      title={"Chain ID: #{unit["action"]["chainId"]}"}
                    >
                      {Networks.short_name(unit["action"]["chainId"])}
                    </span>
                  <% else %>
                    -
                  <% end %>
                </td>
                <td>
                  <%= if unit["action"] do %>
                    <span class="font-mono text-sm">{unit["action"]["blockNumber"]}</span>
                  <% else %>
                    -
                  <% end %>
                </td>
                <td>
                  <%= if unit["action"] && unit["action"]["transaction"] do %>
                    <div class="flex items-center gap-1">
                      <a
                        href={"/transactions/#{unit["action"]["transaction"]["id"]}"}
                        class="hash-display text-xs hover:text-primary"
                      >
                        {truncate_hash(unit["action"]["transaction"]["txHash"])}
                      </a>
                      <.copy_button
                        text={unit["action"]["transaction"]["txHash"]}
                        tooltip="Copy tx hash"
                      />
                    </div>
                  <% else %>
                    -
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    <% end %>
    """
  end

  defp pagination(assigns) do
    ~H"""
    <div class="flex items-center justify-between mt-4 pt-4 border-t border-base-300">
      <button phx-click="prev_page" disabled={@page == 0 || @loading} class="btn btn-ghost btn-sm">
        <.icon name="hero-chevron-left" class="w-4 h-4" /> Previous
      </button>
      <span class="text-sm text-base-content/60">
        Page {@page + 1}
      </span>
      <button phx-click="next_page" disabled={not @has_more || @loading} class="btn btn-ghost btn-sm">
        Next <.icon name="hero-chevron-right" class="w-4 h-4" />
      </button>
    </div>
    """
  end

  defp truncate_hash(nil), do: "-"

  defp truncate_hash(hash) when byte_size(hash) > 16 do
    String.slice(hash, 0, 10) <> "..." <> String.slice(hash, -6, 6)
  end

  defp truncate_hash(hash), do: hash
end
