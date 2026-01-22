defmodule AnomaExplorerWeb.LogicsLive do
  @moduledoc """
  LiveView for listing and filtering logic inputs.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Client
  alias AnomaExplorer.Utils.Formatting

  alias AnomaExplorerWeb.Live.Helpers.SharedHandlers
  import AnomaExplorerWeb.Live.Helpers.FilterHelpers

  @default_filters %{
    "tag" => "",
    "is_consumed" => "",
    "verifying_key" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Logic Inputs")
      |> assign(:logics, [])
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:page, 0)
      |> assign(:has_more, true)
      |> assign(:configured, Client.configured?())
      |> assign(:filters, @default_filters)
      |> assign(:filter_version, 0)
      |> assign(:show_filters, false)
      |> assign(:selected_chain, nil)

    if connected?(socket) and Client.configured?() do
      send(self(), :load_logics)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_logics, socket) do
    {:noreply, load_logics(socket)}
  end

  @impl true
  def handle_event("toggle_filters", _params, socket) do
    {:noreply, assign(socket, :show_filters, !socket.assigns.show_filters)}
  end

  @impl true
  def handle_event("quick_filter", %{"status" => status}, socket) do
    filters =
      case status do
        "all" -> Map.put(socket.assigns.filters, "is_consumed", "")
        "consumed" -> Map.put(socket.assigns.filters, "is_consumed", "true")
        "created" -> Map.put(socket.assigns.filters, "is_consumed", "false")
        _ -> socket.assigns.filters
      end

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:page, 0)
      |> assign(:loading, true)
      |> load_logics()

    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_filters", %{"filters" => filters}, socket) do
    socket =
      socket
      |> assign(:filters, Map.merge(@default_filters, filters))
      |> assign(:page, 0)
      |> assign(:loading, true)
      |> load_logics()

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
      |> load_logics()

    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    if socket.assigns.page > 0 do
      socket =
        socket
        |> assign(:page, socket.assigns.page - 1)
        |> assign(:loading, true)
        |> load_logics()

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
        |> load_logics()

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

  defp load_logics(socket) do
    page_size = 20
    filters = socket.assigns.filters

    opts =
      [limit: page_size + 1, offset: socket.assigns.page * page_size]
      |> maybe_add_filter(:tag, filters["tag"])
      |> maybe_add_filter(:verifying_key, filters["verifying_key"])
      |> maybe_add_bool_filter(:is_consumed, filters["is_consumed"])

    case GraphQL.list_logic_inputs(opts) do
      {:ok, logics} ->
        has_more = length(logics) > page_size

        socket
        |> assign(:logics, Enum.take(logics, page_size))
        |> assign(:has_more, has_more)
        |> assign(:loading, false)
        |> assign(:error, nil)

      {:error, :not_configured} ->
        socket
        |> assign(:logics, [])
        |> assign(:loading, false)
        |> assign(:error, "Indexer endpoint not configured")

      {:error, reason} ->
        socket
        |> assign(:logics, [])
        |> assign(:loading, false)
        |> assign(:error, "Failed to load logic inputs: #{inspect(reason)}")
    end
  end

  defp logic_active_filter_count(filters) do
    active_filter_count(filters, exclude: ["is_consumed"])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/logics">
      <div class="page-header">
        <div>
          <h1 class="page-title flex items-center gap-2">
            Logic Inputs
            <a
              href="https://specs.anoma.net/v1.0.0/arch/system/state/resource_machine/data_structures/action/resource_logic_proof.html"
              target="_blank"
              rel="noopener noreferrer"
              class="tooltip tooltip-right"
              data-tip="Resource logic proofs verify that user constraints are satisfied for each resource"
            >
              <.icon
                name="hero-question-mark-circle"
                class="w-5 h-5 text-base-content/40 hover:text-primary"
              />
            </a>
          </h1>
          <p class="text-sm text-base-content/70 mt-1">All indexed logic inputs with proofs</p>
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
            filter_count={logic_active_filter_count(@filters)}
          />
          <.filter_form :if={@show_filters} filters={@filters} filter_version={@filter_version} />

          <%= if @loading and @logics == [] do %>
            <.loading_skeleton />
          <% else %>
            <.logics_table logics={@logics} />
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
    <form
      id={"filter-form-#{@filter_version}"}
      phx-submit="apply_filters"
      class="mb-6 p-4 bg-base-200/50 rounded-lg"
    >
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
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
            Verifying Key
          </label>
          <input
            type="text"
            name="filters[verifying_key]"
            value={@filters["verifying_key"]}
            placeholder="0x..."
            class="input input-bordered input-sm w-full"
          />
        </div>
      </div>

      <input type="hidden" name="filters[is_consumed]" value={@filters["is_consumed"]} />

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
            Configure the Envio GraphQL endpoint in settings to view logic inputs.
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

  defp logics_table(assigns) do
    ~H"""
    <%= if @logics == [] do %>
      <div class="text-center py-8 text-base-content/50">
        <.icon name="hero-cpu-chip" class="w-12 h-12 mx-auto mb-2 opacity-50" />
        <p>No logic inputs found</p>
      </div>
    <% else %>
      <div class="overflow-x-auto">
        <table class="data-table w-full">
          <thead>
            <tr>
              <th>Tag</th>
              <th>Status</th>
              <th>Verifying Key</th>
              <th>Payloads</th>
              <th>Network</th>
              <th>Transaction</th>
            </tr>
          </thead>
          <tbody>
            <%= for logic <- @logics do %>
              <tr class="hover:bg-base-200/50">
                <td>
                  <div class="flex items-center gap-1">
                    <a href={"/logics/#{logic["id"]}"} class="hash-display text-xs hover:text-primary">
                      {Formatting.truncate_hash(logic["tag"])}
                    </a>
                    <.copy_button :if={logic["tag"]} text={logic["tag"]} tooltip="Copy tag" />
                  </div>
                </td>
                <td>
                  <%= if logic["isConsumed"] do %>
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
                  <div class="flex items-center gap-1">
                    <code class="hash-display text-xs">{Formatting.truncate_hash(logic["verifyingKey"])}</code>
                    <.copy_button
                      :if={logic["verifyingKey"]}
                      text={logic["verifyingKey"]}
                      tooltip="Copy verifying key"
                    />
                  </div>
                </td>
                <td>
                  <div class="flex gap-1">
                    <span class="badge badge-ghost badge-xs" title="Application">
                      A:{logic["applicationPayloadCount"] || 0}
                    </span>
                    <span class="badge badge-ghost badge-xs" title="Discovery">
                      D:{logic["discoveryPayloadCount"] || 0}
                    </span>
                    <span class="badge badge-ghost badge-xs" title="External">
                      E:{logic["externalPayloadCount"] || 0}
                    </span>
                  </div>
                </td>
                <td>
                  <%= if logic["action"] do %>
                    <.network_button chain_id={logic["action"]["chainId"]} />
                  <% else %>
                    -
                  <% end %>
                </td>
                <td>
                  <%= if logic["action"] && logic["action"]["transaction"] do %>
                    <div class="flex items-center gap-1">
                      <a
                        href={"/transactions/#{logic["action"]["transaction"]["id"]}"}
                        class="hash-display text-xs hover:text-primary"
                      >
                        {Formatting.truncate_hash(logic["action"]["transaction"]["txHash"])}
                      </a>
                      <.copy_button
                        text={logic["action"]["transaction"]["txHash"]}
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

end
