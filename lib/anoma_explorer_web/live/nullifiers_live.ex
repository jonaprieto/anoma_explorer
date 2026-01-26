defmodule AnomaExplorerWeb.NullifiersLive do
  @moduledoc """
  LiveView for listing and filtering nullifiers.
  Nullifiers are extracted from compliance units' consumedNullifier field.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Client
  alias AnomaExplorer.Utils.Formatting

  alias AnomaExplorerWeb.Live.Helpers.SharedHandlers
  alias AnomaExplorerWeb.IndexerSetupComponents
  alias AnomaExplorer.Settings
  alias AnomaExplorerWeb.Live.Helpers.SetupHandlers
  import AnomaExplorerWeb.Live.Helpers.FilterHelpers

  @default_filters %{
    "nullifier" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: send(self(), :check_connection)

    {:ok,
     socket
     |> assign(:page_title, "Nullifiers")
     |> assign(:nullifiers, [])
     |> assign(:loading, true)
     |> assign(:error, nil)
     |> assign(:page, 0)
     |> assign(:has_more, true)
     |> assign(:configured, Client.configured?())
     |> assign(:connection_status, nil)
     |> assign(:filters, @default_filters)
     |> assign(:filter_version, 0)
     |> assign(:show_filters, false)
     |> assign(:selected_chain, nil)
     |> SetupHandlers.init_setup_assigns()}
  end

  @impl true
  def handle_info(:check_connection, socket) do
    if Client.configured?() do
      case Client.test_connection() do
        {:ok, _} ->
          socket = load_nullifiers(socket)
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
    # Increment filter_version to force form re-render and clear input values
    version = Map.get(socket.assigns, :filter_version, 0) + 1

    socket =
      socket
      |> assign(:filters, @default_filters)
      |> assign(:filter_version, version)
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


  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/nullifiers">
      <div class="page-header">
        <div>
          <h1 class="page-title flex items-center gap-2">
            Nullifiers
            <a
              href="https://specs.anoma.net/v1.0.0/arch/system/state/resource_machine/data_structures/resource/computable_components/nullifier.html"
              target="_blank"
              rel="noopener noreferrer"
              class="tooltip tooltip-right"
              data-tip="Nullifiers are added to the global nullifier set when resources are consumed"
            >
              <.icon
                name="hero-question-mark-circle"
                class="w-5 h-5 text-base-content/40 hover:text-primary"
              />
            </a>
          </h1>
          <p class="text-sm text-base-content/70 mt-1">
            All consumed nullifiers from compliance units
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
            url={Settings.get_envio_url()}
          />
        <% true -> %>
          <%= if @error do %>
            <div class="alert alert-error mb-6">
              <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
              <span>{@error}</span>
            </div>
          <% end %>

          <div class="stat-card">
            <.filter_toggle show_filters={@show_filters} filter_count={active_filter_count(@filters)} />
            <.filter_form :if={@show_filters} filters={@filters} filter_version={@filter_version} />

            <%= if @loading and @nullifiers == [] do %>
              <.loading_skeleton />
            <% else %>
              <.nullifiers_table nullifiers={@nullifiers} />
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
    <form
      id={"filter-form-#{@filter_version}"}
      phx-submit="apply_filters"
      class="mb-6 p-4 bg-base-200/50 rounded-lg"
    >
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

  defp loading_skeleton(assigns) do
    ~H"""
    <.loading_blocks message="Loading nullifiers..." class="py-12" />
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
                      {Formatting.truncate_hash(unit["consumedLogicRef"])}
                    </code>
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
                        {Formatting.truncate_hash(unit["consumedResource"]["tag"])}
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
