defmodule AnomaExplorerWeb.HomeLive do
  @moduledoc """
  Dashboard LiveView showing stats and recent transactions from the Envio indexer.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorerWeb.IndexerSetupComponents
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Client
  alias AnomaExplorer.Indexer.Networks
  alias AnomaExplorer.Settings
  alias AnomaExplorer.Utils.Formatting

  alias AnomaExplorerWeb.Live.Helpers.SharedHandlers
  alias AnomaExplorerWeb.Live.Helpers.SetupHandlers

  @refresh_interval 30_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      send(self(), :check_connection)
      :timer.send_interval(@refresh_interval, self(), :refresh)
    end

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:stats, nil)
     |> assign(:transactions, [])
     |> assign(:loading, true)
     |> assign(:error, nil)
     |> assign(:configured, Client.configured?())
     |> assign(:connection_status, nil)
     |> assign(:last_updated, nil)
     |> assign(:selected_chain, nil)
     |> assign(:selected_resources, nil)
     |> SetupHandlers.init_setup_assigns()}
  end

  @impl true
  def handle_info(:check_connection, socket) do
    if Client.configured?() do
      # Test actual connection before loading data
      case Client.test_connection() do
        {:ok, _} ->
          socket = load_dashboard_data(socket)
          {:noreply, assign(socket, :connection_status, :ok)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:connection_status, {:error, reason})
           |> assign(:loading, false)}
      end
    else
      {:noreply,
       socket
       |> assign(:configured, false)
       |> assign(:loading, false)}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    if socket.assigns.configured and socket.assigns.connection_status == :ok do
      socket = load_dashboard_data(socket)
      {:noreply, socket}
    else
      # Re-check connection on refresh if not working
      send(self(), :check_connection)
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:setup_auto_test_connection, url}, socket) do
    {:noreply, SetupHandlers.handle_auto_test(socket, url)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> load_dashboard_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("retry_connection", _params, socket) do
    send(self(), :check_connection)
    {:noreply, assign(socket, :loading, true)}
  end

  @impl true
  def handle_event("setup_update_url", %{"url" => url}, socket) do
    {:noreply, SetupHandlers.handle_update_url(socket, url)}
  end

  @impl true
  def handle_event("setup_save_url", %{"url" => url}, socket) do
    case SetupHandlers.handle_save_url(socket, url) do
      {:ok, socket} ->
        # Re-check connection after save
        send(self(), :check_connection)

        {:noreply,
         socket
         |> assign(:configured, true)
         |> assign(:loading, true)}

      {:error, socket} ->
        {:noreply, socket}
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

  @impl true
  def handle_event(
        "show_resources",
        %{"tx-id" => tx_id, "tags" => tags_json, "logic-refs" => logic_refs_json},
        socket
      ) do
    {:noreply, SharedHandlers.handle_show_resources(socket, tx_id, tags_json, logic_refs_json)}
  end

  @impl true
  def handle_event("close_resources_modal", _params, socket) do
    {:noreply, SharedHandlers.handle_close_resources_modal(socket)}
  end

  @impl true
  def handle_event("global_search", %{"query" => query}, socket) do
    case SharedHandlers.handle_global_search(query) do
      {:navigate, path} -> {:noreply, push_navigate(socket, to: path)}
      :noop -> {:noreply, socket}
    end
  end

  defp load_dashboard_data(socket) do
    if not Client.configured?() do
      socket
      |> assign(:configured, false)
      |> assign(:loading, false)
    else
      # Run stats and transactions queries in parallel for faster loading
      stats_task = Task.async(fn -> GraphQL.get_stats() end)
      txs_task = Task.async(fn -> GraphQL.list_transactions(limit: 10) end)

      # Await both results (15 second timeout to match GraphQL timeout)
      stats_result = Task.await(stats_task, 15_000)
      txs_result = Task.await(txs_task, 15_000)

      case {stats_result, txs_result} do
        {{:ok, stats}, {:ok, transactions}} ->
          socket
          |> assign(:stats, stats)
          |> assign(:transactions, transactions)
          |> assign(:loading, false)
          |> assign(:error, nil)
          |> assign(:configured, true)
          |> assign(:last_updated, DateTime.utc_now())

        {{:error, reason}, _} ->
          socket
          |> assign(:loading, false)
          |> assign(:error, format_error(reason))

        {_, {:error, reason}} ->
          socket
          |> assign(:loading, false)
          |> assign(:error, format_error(reason))
      end
    end
  end

  defp format_error(reason), do: Formatting.format_error(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/">
      <div class="page-header">
        <div>
          <h1 class="page-title">Dashboard</h1>
          <p class="text-sm text-base-content/70 mt-1">
            Anoma Protocol Activity Overview
          </p>
        </div>
        <div class="flex items-center gap-2">
          <%= if @last_updated do %>
            <span class="text-xs text-base-content/50">
              Updated {Formatting.format_time(@last_updated)}
            </span>
          <% end %>
          <button phx-click="refresh" class="btn btn-ghost btn-sm" disabled={@loading}>
            <.icon name="hero-arrow-path" class={["w-4 h-4", @loading && "animate-spin"]} />
          </button>
        </div>
      </div>

      <%= cond do %>
        <% not @configured -> %>
          <IndexerSetupComponents.setup_required
            url_input={@setup_url_input}
            status={@setup_status}
            auto_testing={@setup_auto_testing}
            saving={@setup_saving}
          />
        <% match?({:error, _}, @connection_status) -> %>
          <IndexerSetupComponents.connection_error
            error={elem(@connection_status, 1)}
            url={Settings.get_envio_url()}
          />
        <% true -> %>
          <%= if @error do %>
            <div class="alert alert-error mb-6">
              <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
              <span>{@error}</span>
            </div>
          <% end %>

          <%= if @loading and is_nil(@stats) do %>
            <.loading_skeleton />
          <% else %>
            <%= if @stats do %>
              <.stats_grid stats={@stats} />
              <.recent_transactions transactions={@transactions} loading={@loading} />
            <% end %>
          <% end %>

          <.chain_info_modal chain={@selected_chain} />
          <.resources_modal resources={@selected_resources} />
      <% end %>
    </Layouts.app>
    """
  end

  defp loading_skeleton(assigns) do
    ~H"""
    <.loading_blocks message="Loading dashboard data..." />
    <.table_skeleton rows={5} columns={8} />
    """
  end

  defp stats_grid(assigns) do
    ~H"""
    <div class="mb-4">
      <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-7 gap-3">
        <.stat_card
          label="Transactions"
          value={@stats.transactions}
          icon="hero-document-text"
          color="primary"
          href="/transactions"
          tooltip="Total transactions processed by the Anoma protocol"
        />
        <.stat_card
          label="Actions"
          value={@stats.actions}
          icon="hero-bolt"
          color="warning"
          href="/actions"
          tooltip="Actions executed within transactions"
        />
        <.stat_card
          label="Compliances"
          value={@stats.compliances}
          icon="hero-shield-check"
          color="info"
          href="/compliances"
          tooltip="Compliance units ensuring transaction validity"
        />
        <.stat_card
          label="Resources"
          value={@stats.resources}
          icon="hero-cube"
          color="secondary"
          href="/resources"
          tooltip="Total resources (consumed + created)"
        />
        <.stat_card
          label="Commitments"
          value={@stats.created}
          icon="hero-finger-print"
          color="success"
          href="/commitments"
          tooltip="Created resource commitments"
        />
        <.stat_card
          label="Nullifiers"
          value={@stats.consumed}
          icon="hero-no-symbol"
          color="error"
          href="/nullifiers"
          tooltip="Consumed resource nullifiers"
        />
        <.stat_card
          label="Logics"
          value={@stats.logics}
          icon="hero-cpu-chip"
          color="accent"
          href="/logics"
          tooltip="Logic inputs for resource validation"
        />
      </div>
    </div>
    <.stats_warning stats={@stats} />
    """
  end

  defp stat_card(assigns) do
    assigns =
      assigns
      |> assign_new(:href, fn -> nil end)
      |> assign_new(:tooltip, fn -> nil end)

    ~H"""
    <%= if @href do %>
      <a
        href={@href}
        class="stat-card block hover:ring-2 hover:ring-primary/50 transition-all"
        title={@tooltip}
      >
        <div class="flex items-center gap-1.5 mb-1">
          <.icon name={@icon} class={"w-3.5 h-3.5 text-#{@color}"} />
          <span class="text-[10px] text-base-content/60 uppercase tracking-wide truncate">
            {@label}
          </span>
        </div>
        <div class="text-xl font-bold text-base-content">
          {Formatting.format_number(@value)}
        </div>
      </a>
    <% else %>
      <div class="stat-card" title={@tooltip}>
        <div class="flex items-center gap-1.5 mb-1">
          <.icon name={@icon} class={"w-3.5 h-3.5 text-#{@color}"} />
          <span class="text-[10px] text-base-content/60 uppercase tracking-wide truncate">
            {@label}
          </span>
        </div>
        <div class="text-xl font-bold text-base-content">
          {Formatting.format_number(@value)}
        </div>
      </div>
    <% end %>
    """
  end

  defp stats_warning(assigns) do
    has_capped_value =
      assigns.stats.transactions >= 1000 or
        assigns.stats.resources >= 1000 or
        assigns.stats.actions >= 1000 or
        (assigns.stats[:compliances] || 0) >= 1000 or
        (assigns.stats[:logics] || 0) >= 1000

    assigns = assign(assigns, :show_warning, has_capped_value)

    ~H"""
    <%= if @show_warning do %>
      <div class="flex items-center gap-2 text-xs text-base-content/50 mb-6">
        <.icon name="hero-information-circle" class="w-4 h-4" />
        <span>
          Stats showing 1,000 may be limited by the <a
            href="/settings/indexer"
            class="link link-primary"
          >indexer API</a>. Actual counts could be higher.
        </span>
      </div>
    <% end %>
    """
  end

  defp recent_transactions(assigns) do
    ~H"""
    <div class="stat-card">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Recent Transactions</h2>
        <a href="/transactions" class="btn btn-ghost btn-sm">
          View All <.icon name="hero-arrow-right" class="w-4 h-4" />
        </a>
      </div>

      <%= if @transactions == [] do %>
        <div class="text-center py-8 text-base-content/50">
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
                <th class="hidden md:table-cell">From</th>
                <th class="hidden md:table-cell">Value</th>
                <th class="hidden lg:table-cell">Gas Price</th>
                <th class="hidden lg:table-cell">Tx Fee</th>
                <th>Resources</th>
                <th class="hidden xl:table-cell">Time</th>
              </tr>
            </thead>
            <tbody>
              <%= for tx <- @transactions do %>
                <% tags = tx["tags"] || [] %>
                <% consumed = div(length(tags), 2) %>
                <% created = length(tags) - consumed %>
                <tr>
                  <td>
                    <div class="flex items-center gap-1">
                      <a href={"/transactions/#{tx["id"]}"} class="hash-display hover:text-primary">
                        {Formatting.truncate_hash(tx["txHash"])}
                      </a>
                      <.copy_button text={tx["txHash"]} tooltip="Copy full hash" />
                    </div>
                  </td>
                  <td>
                    <.network_button chain_id={tx["chainId"]} />
                  </td>
                  <td>
                    <div class="flex items-center gap-1">
                      <%= if block_url = Networks.block_url(tx["chainId"], tx["blockNumber"]) do %>
                        <a
                          href={block_url}
                          target="_blank"
                          rel="noopener"
                          class="font-mono text-sm link link-hover"
                        >
                          {tx["blockNumber"]}
                        </a>
                      <% else %>
                        <span class="font-mono text-sm">{tx["blockNumber"]}</span>
                      <% end %>
                      <.copy_button text={to_string(tx["blockNumber"])} tooltip="Copy block number" />
                    </div>
                  </td>
                  <td class="hidden md:table-cell">
                    <div class="flex items-center gap-1">
                      <span class="hash-display text-sm">{Formatting.truncate_hash(tx["from"])}</span>
                      <.copy_button :if={tx["from"]} text={tx["from"]} tooltip="Copy address" />
                    </div>
                  </td>
                  <td class="hidden md:table-cell text-sm">
                    {Formatting.format_eth(tx["value"])}
                  </td>
                  <td class="hidden lg:table-cell text-sm">
                    {Formatting.format_gwei(tx["gasPrice"])}
                  </td>
                  <td class="hidden lg:table-cell text-sm">
                    {Formatting.format_tx_fee(tx["gasUsed"], tx["gasPrice"])}
                  </td>
                  <td>
                    <button
                      phx-click="show_resources"
                      phx-value-tx-id={tx["id"]}
                      phx-value-tags={Jason.encode!(tx["tags"] || [])}
                      phx-value-logic-refs={Jason.encode!(tx["logicRefs"] || [])}
                      class="flex items-center gap-1.5 cursor-pointer hover:text-primary"
                      title="View resources"
                    >
                      <span class="badge badge-outline badge-sm text-error border-error/50">
                        {consumed}
                      </span>
                      <span class="badge badge-outline badge-sm text-success border-success/50">
                        {created}
                      </span>
                    </button>
                  </td>
                  <td class="hidden xl:table-cell text-base-content/60 text-sm">
                    {Formatting.format_timestamp(tx["timestamp"])}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp resources_modal(assigns) do
    ~H"""
    <%= if @resources do %>
      <div class="modal modal-open" phx-click="close_resources_modal">
        <div class="modal-box max-w-2xl" phx-click-away="close_resources_modal">
          <button
            class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
            phx-click="close_resources_modal"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>

          <div class="space-y-4">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <h3 class="text-lg font-semibold">Resources</h3>
                <span class="badge badge-outline">{length(@resources.tags)} total</span>
              </div>
              <a href={"/transactions/#{@resources.tx_id}"} class="btn btn-ghost btn-sm">
                View Transaction <.icon name="hero-arrow-right" class="w-4 h-4" />
              </a>
            </div>

            <%= if @resources.tags == [] do %>
              <div class="text-base-content/50 text-center py-4">No resources</div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="data-table w-full">
                  <thead>
                    <tr>
                      <th>Index</th>
                      <th>Type</th>
                      <th>Tag</th>
                      <th>Logic Ref</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for {tag, idx} <- Enum.with_index(@resources.tags) do %>
                      <% is_consumed = rem(idx, 2) == 0 %>
                      <% logic_ref = Enum.at(@resources.logic_refs, idx) %>
                      <tr>
                        <td>
                          <span class="text-sm text-base-content/60">{idx}</span>
                        </td>
                        <td>
                          <%= if is_consumed do %>
                            <div class="flex items-center gap-1 text-sm">
                              <.icon
                                name="hero-arrow-right-start-on-rectangle"
                                class="w-3 h-3 text-base-content/50"
                              />
                              <span class="text-base-content/70">Consumed</span>
                            </div>
                          <% else %>
                            <div class="flex items-center gap-1 text-sm">
                              <.icon name="hero-plus-circle" class="w-3 h-3 text-base-content/50" />
                              <span class="text-base-content/70">Created</span>
                            </div>
                          <% end %>
                        </td>
                        <td>
                          <div class="flex items-center gap-1">
                            <code class="hash-display text-xs">{Formatting.truncate_hash(tag)}</code>
                            <.copy_button :if={tag} text={tag} tooltip="Copy tag" />
                          </div>
                        </td>
                        <td>
                          <div class="flex items-center gap-1">
                            <code class="hash-display text-xs">{Formatting.truncate_hash(logic_ref)}</code>
                            <.copy_button :if={logic_ref} text={logic_ref} tooltip="Copy logic ref" />
                          </div>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
        <div class="modal-backdrop bg-black/50"></div>
      </div>
    <% end %>
    """
  end

end
