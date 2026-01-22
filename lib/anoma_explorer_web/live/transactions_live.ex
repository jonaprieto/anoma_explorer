defmodule AnomaExplorerWeb.TransactionsLive do
  @moduledoc """
  LiveView for listing transactions from the Envio indexer.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Client
  alias AnomaExplorer.Indexer.Networks

  @page_size 20

  @default_filters %{
    "tx_hash" => "",
    "chain_id" => "",
    "block_min" => "",
    "block_max" => "",
    "contract_address" => ""
  }

  @impl true
  def mount(params, _session, socket) do
    # Handle search query param from global search
    search_query = Map.get(params, "search", "")

    filters =
      if search_query != "" do
        Map.put(@default_filters, "tx_hash", search_query)
      else
        @default_filters
      end

    show_filters = search_query != ""

    if connected?(socket), do: send(self(), :load_data)

    {:ok,
     socket
     |> assign(:page_title, "Transactions")
     |> assign(:transactions, [])
     |> assign(:loading, true)
     |> assign(:error, nil)
     |> assign(:page, 0)
     |> assign(:has_more, false)
     |> assign(:configured, Client.configured?())
     |> assign(:show_filters, show_filters)
     |> assign(:filters, filters)
     |> assign(:chains, Networks.list_chains())}
  end

  @impl true
  def handle_info(:load_data, socket) do
    socket = load_transactions(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_filters", _params, socket) do
    {:noreply, assign(socket, :show_filters, !socket.assigns.show_filters)}
  end

  @impl true
  def handle_event("apply_filters", %{"filters" => filters}, socket) do
    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:page, 0)
      |> assign(:loading, true)
      |> load_transactions()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    socket =
      socket
      |> assign(:filters, @default_filters)
      |> assign(:page, 0)
      |> assign(:loading, true)
      |> load_transactions()

    {:noreply, socket}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    socket =
      socket
      |> assign(:page, socket.assigns.page + 1)
      |> assign(:loading, true)
      |> load_transactions()

    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    socket =
      socket
      |> assign(:page, max(0, socket.assigns.page - 1))
      |> assign(:loading, true)
      |> load_transactions()

    {:noreply, socket}
  end

  @impl true
  def handle_event("global_search", %{"query" => query}, socket) do
    query = String.trim(query)

    if query != "" do
      # Apply search as tx_hash filter
      filters = Map.put(@default_filters, "tx_hash", query)

      socket =
        socket
        |> assign(:filters, filters)
        |> assign(:show_filters, true)
        |> assign(:page, 0)
        |> assign(:loading, true)
        |> load_transactions()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp load_transactions(socket) do
    if not Client.configured?() do
      socket
      |> assign(:configured, false)
      |> assign(:loading, false)
    else
      offset = socket.assigns.page * @page_size
      filters = socket.assigns.filters

      opts =
        [limit: @page_size + 1, offset: offset]
        |> maybe_add_filter(:tx_hash, filters["tx_hash"])
        |> maybe_add_filter(:contract_address, filters["contract_address"])
        |> maybe_add_int_filter(:chain_id, filters["chain_id"])
        |> maybe_add_int_filter(:block_min, filters["block_min"])
        |> maybe_add_int_filter(:block_max, filters["block_max"])

      case GraphQL.list_transactions(opts) do
        {:ok, transactions} ->
          has_more = length(transactions) > @page_size
          display_txs = Enum.take(transactions, @page_size)

          socket
          |> assign(:transactions, display_txs)
          |> assign(:has_more, has_more)
          |> assign(:loading, false)
          |> assign(:error, nil)
          |> assign(:configured, true)

        {:error, reason} ->
          socket
          |> assign(:loading, false)
          |> assign(:error, format_error(reason))
      end
    end
  end

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, _key, ""), do: opts
  defp maybe_add_filter(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_add_int_filter(opts, _key, nil), do: opts
  defp maybe_add_int_filter(opts, _key, ""), do: opts

  defp maybe_add_int_filter(opts, key, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> Keyword.put(opts, key, int)
      :error -> opts
    end
  end

  defp maybe_add_int_filter(opts, key, value) when is_integer(value) do
    Keyword.put(opts, key, value)
  end

  defp format_error(:not_configured), do: "Indexer endpoint not configured"
  defp format_error({:connection_error, _}), do: "Failed to connect to indexer"
  defp format_error(reason), do: "Error: #{inspect(reason)}"

  defp active_filter_count(filters) do
    Enum.count(filters, fn {_k, v} -> v != "" and not is_nil(v) end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/transactions">
      <div class="page-header">
        <div>
          <h1 class="page-title">Transactions</h1>
          <p class="text-sm text-base-content/70 mt-1">
            All indexed Anoma transactions
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
          <.filter_form :if={@show_filters} filters={@filters} chains={@chains} />

          <%= if @loading and @transactions == [] do %>
            <.loading_skeleton />
          <% else %>
            <.transactions_table transactions={@transactions} />
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
    <form phx-submit="apply_filters" class="mb-6 p-4 bg-base-200/50 rounded-lg">
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
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
            Contract Address
          </label>
          <input
            type="text"
            name="filters[contract_address]"
            value={@filters["contract_address"]}
            placeholder="0x..."
            class="input input-bordered input-sm w-full"
          />
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
            Configure the Envio GraphQL endpoint to view transactions.
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

  defp transactions_table(assigns) do
    ~H"""
    <%= if @transactions == [] do %>
      <div class="text-center py-12 text-base-content/50">
        <.icon name="hero-inbox" class="w-12 h-12 mx-auto mb-2 opacity-50" />
        <p>No transactions found</p>
      </div>
    <% else %>
      <div class="overflow-x-auto">
        <table class="data-table w-full">
          <thead>
            <tr>
              <th>Tx Hash</th>
              <th>Network</th>
              <th>Block</th>
              <th>Resources</th>
              <th class="hidden lg:table-cell">Time</th>
            </tr>
          </thead>
          <tbody>
            <%= for tx <- @transactions do %>
              <% tags = tx["tags"] || [] %>
              <% consumed = div(length(tags), 2) %>
              <% created = length(tags) - consumed %>
              <tr class="hover:bg-base-200/50">
                <td>
                  <div class="flex items-center gap-1">
                    <a href={"/transactions/#{tx["id"]}"} class="hash-display hover:text-primary">
                      {truncate_hash(tx["txHash"])}
                    </a>
                    <.copy_button text={tx["txHash"]} tooltip="Copy tx hash" />
                  </div>
                </td>
                <td>
                  <span class="text-sm text-base-content/70" title={"Chain ID: #{tx["chainId"]}"}>
                    {Networks.short_name(tx["chainId"])}
                  </span>
                </td>
                <td>
                  <span class="font-mono text-sm">{tx["blockNumber"]}</span>
                </td>
                <td>
                  <span
                    class="badge badge-outline badge-sm text-error border-error/50"
                    title="Consumed"
                  >
                    {consumed}
                  </span>
                  <span
                    class="badge badge-outline badge-sm text-success border-success/50"
                    title="Created"
                  >
                    {created}
                  </span>
                </td>
                <td class="hidden lg:table-cell text-base-content/60 text-sm">
                  {format_timestamp(tx["timestamp"])}
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

  defp format_timestamp(nil), do: "-"

  defp format_timestamp(ts) when is_integer(ts) do
    case DateTime.from_unix(ts) do
      {:ok, dt} -> format_relative(dt)
      _ -> "-"
    end
  end

  defp format_relative(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
