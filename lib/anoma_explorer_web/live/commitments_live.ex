defmodule AnomaExplorerWeb.CommitmentsLive do
  @moduledoc """
  LiveView for listing and filtering commitment tree roots.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Client
  alias AnomaExplorer.Indexer.Networks
  alias AnomaExplorer.Utils.Formatting

  alias AnomaExplorerWeb.Live.Helpers.SharedHandlers
  import AnomaExplorerWeb.Live.Helpers.FilterHelpers

  @default_filters %{
    "root" => "",
    "tx_hash" => "",
    "chain_id" => "",
    "block_min" => "",
    "block_max" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Commitment Tree Roots")
      |> assign(:commitments, [])
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:page, 0)
      |> assign(:has_more, true)
      |> assign(:configured, Client.configured?())
      |> assign(:filters, @default_filters)
      |> assign(:filter_version, 0)
      |> assign(:show_filters, false)
      |> assign(:chains, Networks.list_chains())
      |> assign(:selected_chain, nil)

    if connected?(socket) and Client.configured?() do
      send(self(), :load_commitments)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_commitments, socket) do
    {:noreply, load_commitments(socket)}
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
      |> load_commitments()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    # Increment filter_version to force form re-render and clear input values
    version = Map.get(socket.assigns, :filter_version, 0) + 1

    socket =
      socket
      |> assign(:filters, @default_filters)
      |> assign(:filter_version, version)
      |> assign(:page, 0)
      |> assign(:loading, true)
      |> load_commitments()

    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    if socket.assigns.page > 0 do
      socket =
        socket
        |> assign(:page, socket.assigns.page - 1)
        |> assign(:loading, true)
        |> load_commitments()

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
        |> load_commitments()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("global_search", %{"query" => query}, socket) do
    case SharedHandlers.handle_global_search(query) do
      {:navigate, path} -> {:noreply, push_navigate(socket, to: path)}
      :noop -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_chain_info", %{"chain-id" => chain_id}, socket) do
    {:noreply, SharedHandlers.handle_show_chain_info(socket, chain_id)}
  end

  @impl true
  def handle_event("close_chain_modal", _params, socket) do
    {:noreply, SharedHandlers.handle_close_chain_modal(socket)}
  end

  defp load_commitments(socket) do
    page_size = 20
    filters = socket.assigns.filters

    opts =
      [limit: page_size + 1, offset: socket.assigns.page * page_size]
      |> maybe_add_filter(:root, filters["root"])
      |> maybe_add_filter(:tx_hash, filters["tx_hash"])
      |> maybe_add_int_filter(:chain_id, filters["chain_id"])
      |> maybe_add_int_filter(:block_min, filters["block_min"])
      |> maybe_add_int_filter(:block_max, filters["block_max"])

    case GraphQL.list_commitment_roots(opts) do
      {:ok, commitments} ->
        has_more = length(commitments) > page_size

        socket
        |> assign(:commitments, Enum.take(commitments, page_size))
        |> assign(:has_more, has_more)
        |> assign(:loading, false)
        |> assign(:error, nil)

      {:error, :not_configured} ->
        socket
        |> assign(:commitments, [])
        |> assign(:loading, false)
        |> assign(:error, "Indexer endpoint not configured")

      {:error, reason} ->
        socket
        |> assign(:commitments, [])
        |> assign(:loading, false)
        |> assign(:error, "Failed to load commitment tree roots: #{inspect(reason)}")
    end
  end


  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/commitments">
      <div class="page-header">
        <div>
          <h1 class="page-title flex items-center gap-2">
            Commitment Tree Roots
            <a
              href="https://specs.anoma.net/v1.0.0/arch/system/state/resource_machine/index.html"
              target="_blank"
              rel="noopener noreferrer"
              class="tooltip tooltip-right"
              data-tip="Commitments are added to the global commitment tree when resources are created"
            >
              <.icon
                name="hero-question-mark-circle"
                class="w-5 h-5 text-base-content/40 hover:text-primary"
              />
            </a>
          </h1>
          <p class="text-sm text-base-content/70 mt-1">
            All indexed commitment tree roots from the blockchain
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
          <.filter_form
            :if={@show_filters}
            filters={@filters}
            chains={@chains}
            filter_version={@filter_version}
          />

          <%= if @loading and @commitments == [] do %>
            <.loading_skeleton />
          <% else %>
            <.commitments_table commitments={@commitments} />
          <% end %>

          <.pagination page={@page} has_more={@has_more} loading={@loading} />
        </div>

        <.chain_info_modal chain={@selected_chain} />
      <% end %>
    </Layouts.app>
    """
  end

  defp filter_toggle(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-4">
      <button phx-click="toggle_filters" class="btn btn-ghost btn-sm gap-2">
        <.icon name="hero-funnel" class="w-4 h-4" /> Advanced Search
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
    <form
      id={"filter-form-#{@filter_version}"}
      phx-submit="apply_filters"
      class="mb-6 p-4 bg-base-200/50 rounded-lg"
    >
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wide mb-1 block">Root</label>
          <input
            type="text"
            name="filters[root]"
            value={@filters["root"]}
            placeholder="0x..."
            class="input input-bordered input-sm w-full"
          />
        </div>

        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wide mb-1 block">
            Tx Hash
          </label>
          <input
            type="text"
            name="filters[tx_hash]"
            value={@filters["tx_hash"]}
            placeholder="0x..."
            class="input input-bordered input-sm w-full"
          />
        </div>

        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wide mb-1 block">
            Network
          </label>
          <select name="filters[chain_id]" class="select select-bordered select-sm w-full">
            <option value="">All Networks</option>
            <%= for {chain_id, name} <- @chains do %>
              <option value={chain_id} selected={to_string(chain_id) == @filters["chain_id"]}>
                {name}
              </option>
            <% end %>
          </select>
        </div>

        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wide mb-1 block">
            Block Min
          </label>
          <input
            type="number"
            name="filters[block_min]"
            value={@filters["block_min"]}
            placeholder="Min block"
            min="0"
            max={if @filters["block_max"] != "", do: @filters["block_max"], else: nil}
            class="input input-bordered input-sm w-full"
          />
        </div>

        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wide mb-1 block">
            Block Max
          </label>
          <input
            type="number"
            name="filters[block_max]"
            value={@filters["block_max"]}
            placeholder="Max block"
            min={if @filters["block_min"] != "", do: @filters["block_min"], else: "0"}
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
            Configure the Envio GraphQL endpoint in settings to view commitment tree roots.
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

  defp commitments_table(assigns) do
    ~H"""
    <%= if @commitments == [] do %>
      <div class="text-center py-8 text-base-content/50">
        <.icon name="hero-finger-print" class="w-12 h-12 mx-auto mb-2 opacity-50" />
        <p>No commitment tree roots found</p>
      </div>
    <% else %>
      <div class="overflow-x-auto">
        <table class="data-table w-full">
          <thead>
            <tr>
              <th>Root</th>
              <th>Network</th>
              <th>Block</th>
              <th class="hidden lg:table-cell">Time</th>
              <th>Transaction</th>
            </tr>
          </thead>
          <tbody>
            <%= for commitment <- @commitments do %>
              <tr class="hover:bg-base-200/50">
                <td>
                  <div class="flex items-center gap-1">
                    <code class="hash-display text-xs">{Formatting.truncate_hash(commitment["root"])}</code>
                    <.copy_button
                      :if={commitment["root"]}
                      text={commitment["root"]}
                      tooltip="Copy root"
                    />
                  </div>
                </td>
                <td>
                  <.network_button chain_id={commitment["chainId"]} />
                </td>
                <td>
                  <div class="flex items-center gap-1">
                    <span class="font-mono text-sm">{commitment["blockNumber"]}</span>
                    <.copy_button
                      text={to_string(commitment["blockNumber"])}
                      tooltip="Copy block number"
                    />
                  </div>
                </td>
                <td class="hidden lg:table-cell text-base-content/60 text-sm">
                  {Formatting.format_timestamp_full(commitment["timestamp"])}
                </td>
                <td>
                  <%= if commitment["txHash"] do %>
                    <div class="flex items-center gap-1">
                      <code class="hash-display text-xs">{Formatting.truncate_hash(commitment["txHash"])}</code>
                      <.copy_button text={commitment["txHash"]} tooltip="Copy tx hash" />
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

end
