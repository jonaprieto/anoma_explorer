defmodule AnomaExplorerWeb.ResourcesLive do
  @moduledoc """
  LiveView for listing resources from the Envio indexer.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Client
  alias AnomaExplorer.Indexer.Networks

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
    if connected?(socket), do: send(self(), :load_data)

    {:ok,
     socket
     |> assign(:page_title, "Resources")
     |> assign(:resources, [])
     |> assign(:loading, true)
     |> assign(:error, nil)
     |> assign(:page, 0)
     |> assign(:has_more, false)
     |> assign(:filters, @default_filters)
     |> assign(:show_filters, false)
     |> assign(:configured, Client.configured?())
     |> assign(:chains, Networks.list_chains())}
  end

  @impl true
  def handle_info(:load_data, socket) do
    socket = load_resources(socket)
    {:noreply, socket}
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
    socket =
      socket
      |> assign(:filters, @default_filters)
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
    query = String.trim(query)

    if query != "" do
      {:noreply, push_navigate(socket, to: "/transactions?search=#{URI.encode_www_form(query)}")}
    else
      {:noreply, socket}
    end
  end

  defp load_resources(socket) do
    if not Client.configured?() do
      socket
      |> assign(:configured, false)
      |> assign(:loading, false)
    else
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
    end
  end

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, _key, ""), do: opts
  defp maybe_add_filter(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_add_bool_filter(opts, _key, nil), do: opts
  defp maybe_add_bool_filter(opts, _key, ""), do: opts
  defp maybe_add_bool_filter(opts, key, "true"), do: Keyword.put(opts, key, true)
  defp maybe_add_bool_filter(opts, key, "false"), do: Keyword.put(opts, key, false)
  defp maybe_add_bool_filter(opts, _key, _), do: opts

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
    filters
    |> Map.delete("is_consumed")
    |> Enum.count(fn {_k, v} -> v != "" and not is_nil(v) end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/resources">
      <div class="page-header">
        <div>
          <h1 class="page-title">Resources</h1>
          <p class="text-sm text-base-content/70 mt-1">
            All indexed Anoma resources
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
          <.filter_header
            filters={@filters}
            show_filters={@show_filters}
            filter_count={active_filter_count(@filters)}
          />
          <.filter_form :if={@show_filters} filters={@filters} chains={@chains} />

          <%= if @loading and @resources == [] do %>
            <.loading_skeleton />
          <% else %>
            <.resources_table resources={@resources} />
          <% end %>

          <.pagination page={@page} has_more={@has_more} loading={@loading} />
        </div>
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
        >
          <.icon name="hero-arrow-right-start-on-rectangle" class="w-4 h-4" /> Consumed
        </button>
        <button
          phx-click="quick_filter"
          phx-value-status="created"
          class={["btn btn-sm", (@filters["is_consumed"] == "false" && "btn-primary") || "btn-ghost"]}
        >
          <.icon name="hero-plus-circle" class="w-4 h-4" /> Created
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
    <form phx-submit="apply_filters" class="mb-6 p-4 bg-base-200/50 rounded-lg">
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wide mb-1 block">Tag</label>
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
            Configure the Envio GraphQL endpoint to view resources.
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

  defp resources_table(assigns) do
    ~H"""
    <%= if @resources == [] do %>
      <div class="text-center py-12 text-base-content/50">
        <.icon name="hero-inbox" class="w-12 h-12 mx-auto mb-2 opacity-50" />
        <p>No resources found</p>
      </div>
    <% else %>
      <div class="overflow-x-auto">
        <table class="data-table w-full">
          <thead>
            <tr>
              <th>Tag</th>
              <th>Status</th>
              <th>Network</th>
              <th class="hidden md:table-cell">Logic Ref</th>
              <th class="hidden lg:table-cell">Block</th>
              <th>Transaction</th>
            </tr>
          </thead>
          <tbody>
            <%= for resource <- @resources do %>
              <tr class="hover:bg-base-200/50">
                <td>
                  <div class="flex items-center gap-1">
                    <a
                      href={"/resources/#{resource["id"]}"}
                      class="hash-display text-xs hover:text-primary"
                    >
                      {truncate_hash(resource["tag"])}
                    </a>
                    <.copy_button :if={resource["tag"]} text={resource["tag"]} tooltip="Copy tag" />
                  </div>
                </td>
                <td>
                  <%= if resource["isConsumed"] do %>
                    <span class="badge badge-outline badge-sm text-error border-error/50">
                      Consumed
                    </span>
                  <% else %>
                    <span class="badge badge-outline badge-sm text-success border-success/50">
                      Created
                    </span>
                  <% end %>
                </td>
                <td>
                  <span
                    class="text-sm text-base-content/70"
                    title={"Chain ID: #{resource["chainId"]}"}
                  >
                    {Networks.short_name(resource["chainId"])}
                  </span>
                </td>
                <td class="hidden md:table-cell">
                  <div class="flex items-center gap-1">
                    <code class="hash-display text-xs">{truncate_hash(resource["logicRef"])}</code>
                    <.copy_button
                      :if={resource["logicRef"]}
                      text={resource["logicRef"]}
                      tooltip="Copy logic ref"
                    />
                  </div>
                </td>
                <td class="hidden lg:table-cell font-mono text-sm">
                  {resource["blockNumber"]}
                </td>
                <td>
                  <%= if resource["transaction"] do %>
                    <div class="flex items-center gap-1">
                      <a
                        href={"/transactions/#{resource["transaction"]["id"]}"}
                        class="hash-display text-xs hover:text-primary"
                      >
                        {truncate_hash(resource["transaction"]["txHash"])}
                      </a>
                      <.copy_button
                        text={resource["transaction"]["txHash"]}
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
