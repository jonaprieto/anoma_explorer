defmodule AnomaExplorerWeb.ResourcesLive do
  @moduledoc """
  LiveView for listing resources from the Envio indexer.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorer.Indexer.Client
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Networks
  alias AnomaExplorer.Utils.Formatting

  alias AnomaExplorerWeb.IndexerSetupComponents
  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorerWeb.Live.Helpers.SetupHandlers
  alias AnomaExplorerWeb.Live.Helpers.SharedHandlers
  import AnomaExplorerWeb.Live.Helpers.FilterHelpers

  @page_size 20

  @default_filters %{
    "is_consumed" => "",
    "tag" => "",
    "logic_ref" => "",
    "chain_id" => "",
    "decoding_status" => "",
    "block_min" => "",
    "block_max" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: send(self(), :check_connection)

    {:ok,
     socket
     |> assign(:page_title, "Resources")
     |> assign(:resources, [])
     |> assign(:loading, true)
     |> assign(:error, nil)
     |> assign(:page, 0)
     |> assign(:has_more, false)
     |> assign(:filters, @default_filters)
     |> assign(:filter_version, 0)
     |> assign(:show_filters, false)
     |> assign(:configured, Client.configured?())
     |> assign(:connection_status, nil)
     |> assign(:chains, Networks.list_chains())
     |> assign(:selected_chain, nil)
     |> SetupHandlers.init_setup_assigns()}
  end

  @impl true
  def handle_info(:check_connection, socket) do
    if Client.configured?() do
      case Client.test_connection() do
        {:ok, _} ->
          socket = load_resources(socket)
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
  def handle_info({:setup_auto_test_connection, url}, socket) do
    {:noreply, SetupHandlers.handle_auto_test(socket, url)}
  end

  @impl true
  def handle_event("quick_filter", %{"status" => status}, socket) do
    filters =
      case status do
        "consumed" -> Map.put(socket.assigns.filters, "is_consumed", "true")
        "created" -> Map.put(socket.assigns.filters, "is_consumed", "false")
        _ -> Map.put(socket.assigns.filters, "is_consumed", "")
      end

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:page, 0)
      |> assign(:loading, true)
      |> load_resources()

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
      |> load_resources()

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
      |> load_resources()

    {:noreply, socket}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    socket =
      socket
      |> assign(:page, socket.assigns.page + 1)
      |> assign(:loading, true)
      |> load_resources()

    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    socket =
      socket
      |> assign(:page, max(0, socket.assigns.page - 1))
      |> assign(:loading, true)
      |> load_resources()

    {:noreply, socket}
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
        send(self(), :check_connection)

        {:noreply,
         socket
         |> assign(:configured, true)
         |> assign(:loading, true)}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  defp load_resources(socket) do
    if Client.configured?() do
      offset = socket.assigns.page * @page_size
      filters = socket.assigns.filters

      opts =
        [limit: @page_size + 1, offset: offset]
        |> maybe_add_bool_filter(:is_consumed, filters["is_consumed"])
        |> maybe_add_filter(:tag, filters["tag"])
        |> maybe_add_filter(:logic_ref, filters["logic_ref"])
        |> maybe_add_filter(:decoding_status, filters["decoding_status"])
        |> maybe_add_int_filter(:chain_id, filters["chain_id"])
        |> maybe_add_int_filter(:block_min, filters["block_min"])
        |> maybe_add_int_filter(:block_max, filters["block_max"])

      case GraphQL.list_resources(opts) do
        {:ok, resources} ->
          has_more = length(resources) > @page_size
          display_resources = Enum.take(resources, @page_size)

          socket
          |> assign(:resources, display_resources)
          |> assign(:has_more, has_more)
          |> assign(:loading, false)
          |> assign(:error, nil)
          |> assign(:configured, true)

        {:error, reason} ->
          socket
          |> assign(:loading, false)
          |> assign(:error, format_error(reason))
      end
    else
      socket
      |> assign(:configured, false)
      |> assign(:loading, false)
    end
  end

  defp format_error(reason), do: Formatting.format_error(reason)

  defp resource_active_filter_count(filters) do
    active_filter_count(filters, exclude: ["is_consumed"])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/resources">
      <div class="page-header">
        <div>
          <h1 class="page-title flex items-center gap-2">
            Resources
            <a
              href="https://specs.anoma.net/v1.0.0/arch/system/state/resource_machine/data_structures/resource/index.html"
              target="_blank"
              rel="noopener noreferrer"
              class="tooltip tooltip-right"
              data-tip="Resources are the atomic unit of ARM state - immutable, created once and consumed once"
            >
              <.icon
                name="hero-question-mark-circle"
                class="w-5 h-5 text-base-content/40 hover:text-primary"
              />
            </a>
          </h1>
          <p class="text-sm text-base-content/70 mt-1">
            All indexed Anoma resources
          </p>
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
            url={@setup_url_input}
          />
        <% true -> %>
          <%= if @error do %>
            <div class="alert alert-error mb-6">
              <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
              <span>{@error}</span>
            </div>
          <% end %>

          <div class="stat-card">
            <.filter_header
              filters={@filters}
              show_filters={@show_filters}
              filter_count={resource_active_filter_count(@filters)}
            />
            <.filter_form
              :if={@show_filters}
              filters={@filters}
              chains={@chains}
              filter_version={@filter_version}
            />

            <%= if @loading and @resources == [] do %>
              <.loading_skeleton />
            <% else %>
              <.resources_table resources={@resources} />
            <% end %>

            <.pagination page={@page} has_more={@has_more} loading={@loading} />
          </div>

          <.chain_info_modal chain={@selected_chain} />
      <% end %>
    </Layouts.app>
    """
  end

  defp filter_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-2 mb-4">
      <div class="flex gap-2">
        <button
          phx-click="quick_filter"
          phx-value-status="all"
          class={["btn btn-sm", (@filters["is_consumed"] == "" && "btn-primary") || "btn-ghost"]}
        >
          All
        </button>
        <button
          phx-click="quick_filter"
          phx-value-status="consumed"
          class={["btn btn-sm", (@filters["is_consumed"] == "true" && "btn-primary") || "btn-ghost"]}
          title="Show only nullifiers (consumed resources)"
        >
          <.icon name="hero-arrow-right-start-on-rectangle" class="w-4 h-4" /> Nullifiers
        </button>
        <button
          phx-click="quick_filter"
          phx-value-status="created"
          class={["btn btn-sm", (@filters["is_consumed"] == "false" && "btn-primary") || "btn-ghost"]}
          title="Show only commitments (created resources)"
        >
          <.icon name="hero-plus-circle" class="w-4 h-4" /> Commitments
        </button>
      </div>

      <button phx-click="toggle_filters" class="btn btn-ghost btn-sm gap-2">
        <.icon name="hero-funnel" class="w-4 h-4" /> More Filters
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
          <label
            class="text-xs text-base-content/60 uppercase tracking-wide mb-1 block"
            title="Search by resource identifier (nullifier or commitment hash)"
          >
            Resource ID
          </label>
          <input
            type="text"
            name="filters[tag]"
            value={@filters["tag"]}
            placeholder="0x..."
            class="input input-bordered input-sm w-full"
          />
        </div>

        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wide mb-1 block">
            Logic Ref
          </label>
          <input
            type="text"
            name="filters[logic_ref]"
            value={@filters["logic_ref"]}
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
            Decoding Status
          </label>
          <select name="filters[decoding_status]" class="select select-bordered select-sm w-full">
            <option value="">All Statuses</option>
            <option value="success" selected={@filters["decoding_status"] == "success"}>
              Decoded
            </option>
            <option value="failed" selected={@filters["decoding_status"] == "failed"}>Failed</option>
            <option value="pending" selected={@filters["decoding_status"] == "pending"}>
              Pending
            </option>
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

        <input type="hidden" name="filters[is_consumed]" value={@filters["is_consumed"]} />
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

  defp loading_skeleton(assigns) do
    ~H"""
    <.loading_blocks message="Loading resources..." class="py-12" />
    """
  end

  defp resources_table(assigns) do
    ~H"""
    <%= if @resources == [] do %>
      <div class="text-center py-12 text-base-content/50">
        <.icon name="hero-inbox" class="w-12 h-12 mx-auto mb-2 opacity-50" />
        <p>No resources found</p>
      </div>
    <% else %>
      <%!-- Mobile card layout --%>
      <div class="space-y-3 lg:hidden">
        <%= for resource <- @resources do %>
          <div class="p-3 rounded-lg bg-base-200/50 hover:bg-base-200 transition-colors">
            <div class="flex flex-col gap-1">
              <div class="flex items-start gap-1">
                <%= if resource["isConsumed"] do %>
                  <span class="text-error text-xs shrink-0" title="Nullifier">N</span>
                <% else %>
                  <span class="text-success text-xs shrink-0" title="Commitment">C</span>
                <% end %>
                <a
                  href={"/resources/#{resource["id"]}"}
                  class="font-mono text-sm hover:text-primary break-all"
                >
                  {resource["tag"]}
                </a>
                <.copy_button
                  :if={resource["tag"]}
                  text={resource["tag"]}
                  tooltip="Copy resource ID"
                  class="shrink-0"
                />
              </div>
              <%= if resource["logicRef"] do %>
                <div class="flex items-start gap-1 text-xs text-base-content/60">
                  <span>logic:</span>
                  <code class="font-mono break-all">{resource["logicRef"]}</code>
                  <.copy_button text={resource["logicRef"]} tooltip="Copy logic ref" class="shrink-0" />
                </div>
              <% end %>
              <%= if resource["transaction"] do %>
                <div class="flex items-start gap-1 text-xs text-base-content/60">
                  <span>tx:</span>
                  <a
                    href={"/transactions/#{resource["transaction"]["id"]}"}
                    class="font-mono hover:text-primary break-all"
                  >
                    {resource["transaction"]["evmTransaction"]["txHash"]}
                  </a>
                  <.copy_button
                    text={resource["transaction"]["evmTransaction"]["txHash"]}
                    tooltip="Copy tx hash"
                  />
                </div>
              <% end %>
              <div class="flex items-center gap-1.5 text-xs text-base-content/50 flex-wrap">
                <span
                  class="hover:text-primary cursor-pointer"
                  phx-click="show_chain_info"
                  phx-value-chain-id={resource["chainId"]}
                >
                  {Networks.short_name(resource["chainId"])}
                </span>
                <span>•</span>
                <%= if block_url = Networks.block_url(resource["chainId"], resource["blockNumber"]) do %>
                  <a href={block_url} target="_blank" rel="noopener" class="hover:text-primary">
                    #{resource["blockNumber"]}
                  </a>
                <% else %>
                  <span>#{resource["blockNumber"]}</span>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Desktop table layout --%>
      <div class="hidden lg:block overflow-x-auto">
        <table class="data-table w-full">
          <thead>
            <tr>
              <th title="Unique identifier - nullifier hash (if consumed) or commitment hash (if created)">
                Resource ID
              </th>
              <th title="Blockchain network where this resource exists">Network</th>
              <th title="Block number where this resource was recorded">Block</th>
            </tr>
          </thead>
          <tbody>
            <%= for resource <- @resources do %>
              <tr class="hover:bg-base-200/50">
                <td>
                  <div class="flex flex-col gap-0.5">
                    <div class="flex items-center gap-1">
                      <%= if resource["isConsumed"] do %>
                        <span class="text-error text-xs" title="Nullifier">N</span>
                      <% else %>
                        <span class="text-success text-xs" title="Commitment">C</span>
                      <% end %>
                      <a
                        href={"/resources/#{resource["id"]}"}
                        class="font-mono text-sm hover:text-primary"
                      >
                        {resource["tag"]}
                      </a>
                      <.copy_button
                        :if={resource["tag"]}
                        text={resource["tag"]}
                        tooltip="Copy resource ID"
                      />
                    </div>
                    <%= if resource["logicRef"] do %>
                      <div class="flex items-center gap-1 text-xs text-base-content/50">
                        <span>logic:</span>
                        <code class="font-mono">{resource["logicRef"]}</code>
                        <.copy_button text={resource["logicRef"]} tooltip="Copy logic ref" />
                      </div>
                    <% end %>
                    <%= if resource["transaction"] do %>
                      <div class="flex items-center gap-1 text-xs text-base-content/50">
                        <span>tx:</span>
                        <a
                          href={"/transactions/#{resource["transaction"]["id"]}"}
                          class="font-mono hover:text-primary"
                        >
                          {resource["transaction"]["evmTransaction"]["txHash"]}
                        </a>
                        <.copy_button
                          text={resource["transaction"]["evmTransaction"]["txHash"]}
                          tooltip="Copy tx hash"
                        />
                      </div>
                    <% end %>
                  </div>
                </td>
                <td>
                  <.network_button chain_id={resource["chainId"]} />
                </td>
                <td>
                  <div class="flex items-center gap-1">
                    <%= if block_url = Networks.block_url(resource["chainId"], resource["blockNumber"]) do %>
                      <a
                        href={block_url}
                        target="_blank"
                        rel="noopener"
                        class="font-mono text-sm link link-hover"
                      >
                        {resource["blockNumber"]}
                      </a>
                    <% else %>
                      <span class="font-mono text-sm">{resource["blockNumber"]}</span>
                    <% end %>
                    <.copy_button
                      text={to_string(resource["blockNumber"])}
                      tooltip="Copy block number"
                    />
                  </div>
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
