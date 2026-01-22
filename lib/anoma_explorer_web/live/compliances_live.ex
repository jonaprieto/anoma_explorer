defmodule AnomaExplorerWeb.CompliancesLive do
  @moduledoc """
  LiveView for listing and filtering compliance units.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Client
  alias AnomaExplorer.Utils.Formatting

  alias AnomaExplorerWeb.Live.Helpers.SharedHandlers
  import AnomaExplorerWeb.Live.Helpers.FilterHelpers

  @default_filters %{
    "nullifier" => "",
    "commitment" => "",
    "logic_ref" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Compliance Units")
      |> assign(:compliances, [])
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
      send(self(), :load_compliances)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_compliances, socket) do
    {:noreply, load_compliances(socket)}
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
      |> load_compliances()

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
      |> load_compliances()

    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    if socket.assigns.page > 0 do
      socket =
        socket
        |> assign(:page, socket.assigns.page - 1)
        |> assign(:loading, true)
        |> load_compliances()

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
        |> load_compliances()

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

  defp load_compliances(socket) do
    page_size = 20
    filters = socket.assigns.filters

    opts =
      [limit: page_size + 1, offset: socket.assigns.page * page_size]
      |> maybe_add_filter(:nullifier, filters["nullifier"])
      |> maybe_add_filter(:commitment, filters["commitment"])
      |> maybe_add_filter(:logic_ref, filters["logic_ref"])

    case GraphQL.list_compliance_units(opts) do
      {:ok, compliances} ->
        has_more = length(compliances) > page_size

        socket
        |> assign(:compliances, Enum.take(compliances, page_size))
        |> assign(:has_more, has_more)
        |> assign(:loading, false)
        |> assign(:error, nil)

      {:error, :not_configured} ->
        socket
        |> assign(:compliances, [])
        |> assign(:loading, false)
        |> assign(:error, "Indexer endpoint not configured")

      {:error, reason} ->
        socket
        |> assign(:compliances, [])
        |> assign(:loading, false)
        |> assign(:error, "Failed to load compliance units: #{inspect(reason)}")
    end
  end


  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/compliances">
      <div class="page-header">
        <div>
          <h1 class="page-title flex items-center gap-2">
            Compliance Units
            <a
              href="https://specs.anoma.net/v1.0.0/arch/system/state/resource_machine/data_structures/compliance_unit/compliance_unit.html"
              target="_blank"
              rel="noopener noreferrer"
              class="tooltip tooltip-right"
              data-tip="Compliance units define the scope of compliance proofs, linking consumed and created resources"
            >
              <.icon
                name="hero-question-mark-circle"
                class="w-5 h-5 text-base-content/40 hover:text-primary"
              />
            </a>
          </h1>
          <p class="text-sm text-base-content/70 mt-1">
            All indexed compliance units linking nullifiers and commitments
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
          <.filter_form :if={@show_filters} filters={@filters} filter_version={@filter_version} />

          <%= if @loading and @compliances == [] do %>
            <.loading_skeleton />
          <% else %>
            <.compliances_table compliances={@compliances} />
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
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
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

        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wide mb-1 block">
            Commitment
          </label>
          <input
            type="text"
            name="filters[commitment]"
            value={@filters["commitment"]}
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
            Configure the Envio GraphQL endpoint in settings to view compliance units.
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

  defp compliances_table(assigns) do
    ~H"""
    <%= if @compliances == [] do %>
      <div class="text-center py-8 text-base-content/50">
        <.icon name="hero-shield-check" class="w-12 h-12 mx-auto mb-2 opacity-50" />
        <p>No compliance units found</p>
      </div>
    <% else %>
      <div class="overflow-x-auto">
        <table class="data-table w-full">
          <thead>
            <tr>
              <th>Consumed Nullifier</th>
              <th>Created Commitment</th>
              <th>Network</th>
              <th>Block</th>
              <th>Transaction</th>
            </tr>
          </thead>
          <tbody>
            <%= for unit <- @compliances do %>
              <tr class="hover:bg-base-200/50">
                <td>
                  <div class="flex items-center gap-1">
                    <a
                      href={"/compliances/#{unit["id"]}"}
                      class="hash-display text-xs hover:text-primary"
                    >
                      {Formatting.truncate_hash(unit["consumedNullifier"])}
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
                    <code class="hash-display text-xs">
                      {Formatting.truncate_hash(unit["createdCommitment"])}
                    </code>
                    <.copy_button
                      :if={unit["createdCommitment"]}
                      text={unit["createdCommitment"]}
                      tooltip="Copy commitment"
                    />
                  </div>
                </td>
                <td>
                  <%= if unit["action"] do %>
                    <.network_button chain_id={unit["action"]["chainId"]} />
                  <% else %>
                    -
                  <% end %>
                </td>
                <td>
                  <%= if unit["action"] do %>
                    <div class="flex items-center gap-1">
                      <span class="font-mono text-sm">{unit["action"]["blockNumber"]}</span>
                      <.copy_button
                        text={to_string(unit["action"]["blockNumber"])}
                        tooltip="Copy block number"
                      />
                    </div>
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
                        {Formatting.truncate_hash(unit["action"]["transaction"]["txHash"])}
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

end
