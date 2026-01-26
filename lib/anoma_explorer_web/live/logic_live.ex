defmodule AnomaExplorerWeb.LogicLive do
  @moduledoc """
  LiveView for displaying a single logic input's details.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Networks
  alias AnomaExplorer.Utils.Formatting

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Logic Input Details")
      |> assign(:logic, nil)
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:logic_id, id)

    if connected?(socket) do
      send(self(), {:load_logic, id})
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:load_logic, id}, socket) do
    case GraphQL.get_logic_input(id) do
      {:ok, logic} ->
        {:noreply,
         socket
         |> assign(:logic, logic)
         |> assign(:loading, false)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:error, "Logic input not found")
         |> assign(:loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, "Failed to load logic input: #{inspect(reason)}")
         |> assign(:loading, false)}
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/logics">
      <div class="page-header">
        <div class="flex items-center gap-3">
          <a href="/logics" class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="w-4 h-4" />
          </a>
          <div>
            <h1 class="page-title">Logic Input Details</h1>
            <p class="text-sm text-base-content/70 mt-1">
              {if @logic, do: Formatting.truncate_hash(@logic["tag"]), else: "Loading..."}
            </p>
          </div>
        </div>
      </div>

      <%= if @error do %>
        <div class="alert alert-error mb-6">
          <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
          <span>{@error}</span>
        </div>
      <% end %>

      <%= if @loading do %>
        <.loading_skeleton />
      <% else %>
        <%= if @logic do %>
          <.logic_header logic={@logic} />
          <.payloads_section logic={@logic} />
          <.proof_section logic={@logic} />
        <% end %>
      <% end %>
    </Layouts.app>
    """
  end

  defp loading_skeleton(assigns) do
    ~H"""
    <.loading_blocks message="Loading logic input details..." class="py-12" />
    """
  end

  defp logic_header(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4">Overview</h2>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="md:col-span-2">
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Unique identifier - nullifier hash (if consumed) or commitment hash (if created)">Resource ID</div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@logic["tag"]}</code>
            <.copy_button text={@logic["tag"]} tooltip="Copy resource ID" />
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Determined by index parity: even indices are nullifiers (consumed), odd indices are commitments (created)">Resource Type</div>
          <div>
            <%= if @logic["isConsumed"] do %>
              <span class="badge badge-outline badge-sm text-error border-error/50" title="Nullifier - resource consumed as input">Nullifier</span>
            <% else %>
              <span class="badge badge-outline badge-sm text-success border-success/50" title="Commitment - new resource created as output">Commitment</span>
            <% end %>
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Position of this logic input within the action's logic inputs array">Index</div>
          <div class="font-mono">{@logic["index"]}</div>
        </div>
        <%= if @logic["logicRef"] do %>
          <div class="md:col-span-2">
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Reference to the logic circuit (verifying key) that validates this resource's creation or consumption">Logic Ref</div>
            <div class="flex items-center gap-2">
              <code class="hash-display text-sm break-all">{@logic["logicRef"]}</code>
              <.copy_button text={@logic["logicRef"]} tooltip="Copy logic ref" />
            </div>
          </div>
        <% end %>
        <%= if @logic["action"] do %>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Blockchain network where this logic input was recorded">Network</div>
            <div>
              <span class="badge badge-outline" title={"Chain ID: #{@logic["action"]["chainId"]}"}>
                {Networks.name(@logic["action"]["chainId"])}
              </span>
            </div>
          </div>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Blockchain block number where this logic input was included">Block Number</div>
            <div class="flex items-center gap-2">
              <span class="font-mono">{@logic["action"]["blockNumber"]}</span>
              <.copy_button
                text={to_string(@logic["action"]["blockNumber"])}
                tooltip="Copy block number"
              />
            </div>
          </div>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="When this logic input was recorded on the blockchain">Timestamp</div>
            <div>{Formatting.format_timestamp_full(@logic["action"]["timestamp"])}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Parent action containing this logic input - identified by action tree root">Action</div>
            <div class="flex items-center gap-1">
              <a
                href={"/actions/#{@logic["action"]["id"]}"}
                class="hash-display text-sm hover:text-primary"
              >
                {Formatting.truncate_hash(@logic["action"]["actionTreeRoot"])}
              </a>
              <.copy_button
                :if={@logic["action"]["actionTreeRoot"]}
                text={@logic["action"]["actionTreeRoot"]}
                tooltip="Copy action tree root"
              />
            </div>
          </div>
          <%= if @logic["action"]["transaction"] do %>
            <div>
              <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="EVM transaction that submitted this action to the blockchain">Transaction</div>
              <div class="flex items-center gap-1">
                <a
                  href={"/transactions/#{@logic["action"]["transaction"]["id"]}"}
                  class="hash-display text-sm hover:text-primary"
                >
                  {Formatting.truncate_hash(@logic["action"]["transaction"]["evmTransaction"]["txHash"])}
                </a>
                <.copy_button text={@logic["action"]["transaction"]["evmTransaction"]["txHash"]} tooltip="Copy tx hash" />
              </div>
            </div>
          <% end %>
        <% end %>
        <%= if @logic["resource"] do %>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Link to the associated resource record with full details">Resource</div>
            <div class="flex items-center gap-1">
              <a
                href={"/resources/#{@logic["resource"]["id"]}"}
                class="hash-display text-sm hover:text-primary"
              >
                {Formatting.truncate_hash(@logic["resource"]["tag"])}
              </a>
              <.copy_button
                :if={@logic["resource"]["tag"]}
                text={@logic["resource"]["tag"]}
                tooltip="Copy resource ID"
              />
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp payloads_section(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4" title="Count of different payload types associated with this logic input">Payload Counts</h2>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div class="bg-base-200/50 rounded-lg p-4 text-center" title="App-specific data for the logic circuit to process">
          <div class="text-2xl font-bold">{@logic["applicationPayloadCount"] || 0}</div>
          <div class="text-xs text-base-content/60 uppercase">Application</div>
        </div>
        <div class="bg-base-200/50 rounded-lg p-4 text-center" title="Data for resource indexing and discovery by other parties">
          <div class="text-2xl font-bold">{@logic["discoveryPayloadCount"] || 0}</div>
          <div class="text-xs text-base-content/60 uppercase">Discovery</div>
        </div>
        <div class="bg-base-200/50 rounded-lg p-4 text-center" title="Data stored off-chain, referenced by this logic input">
          <div class="text-2xl font-bold">{@logic["externalPayloadCount"] || 0}</div>
          <div class="text-xs text-base-content/60 uppercase">External</div>
        </div>
        <div class="bg-base-200/50 rounded-lg p-4 text-center" title="Encoded resource data blobs">
          <div class="text-2xl font-bold">{@logic["resourcePayloadCount"] || 0}</div>
          <div class="text-xs text-base-content/60 uppercase">Resource</div>
        </div>
      </div>
    </div>
    """
  end

  defp proof_section(assigns) do
    ~H"""
    <%= if @logic["proof"] do %>
      <div class="stat-card">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold" title="Zero-knowledge proof validating that this logic input satisfies the logic circuit constraints">Proof</h2>
          <.copy_button text={@logic["proof"]} tooltip="Copy proof" />
        </div>
        <div class="bg-base-200/50 p-4 rounded-lg overflow-x-auto">
          <code class="text-xs break-all">{@logic["proof"]}</code>
        </div>
      </div>
    <% end %>
    """
  end

end
