defmodule AnomaExplorerWeb.ComplianceLive do
  @moduledoc """
  LiveView for displaying a single compliance unit's details.
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
      |> assign(:page_title, "Compliance Unit Details")
      |> assign(:compliance, nil)
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:compliance_id, id)

    if connected?(socket) do
      send(self(), {:load_compliance, id})
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:load_compliance, id}, socket) do
    case GraphQL.get_compliance_unit(id) do
      {:ok, compliance} ->
        {:noreply,
         socket
         |> assign(:compliance, compliance)
         |> assign(:loading, false)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:error, "Compliance unit not found")
         |> assign(:loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, "Failed to load compliance unit: #{inspect(reason)}")
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
    <Layouts.app flash={@flash} current_path="/compliances">
      <div class="page-header">
        <div class="flex items-center gap-3">
          <a href="/compliances" class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="w-4 h-4" />
          </a>
          <div>
            <h1 class="page-title">Compliance Unit Details</h1>
            <p class="text-sm text-base-content/70 mt-1">
              {if @compliance, do: "Index: #{@compliance["index"]}", else: "Loading..."}
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
        <%= if @compliance do %>
          <.compliance_header unit={@compliance} />
          <.consumed_section unit={@compliance} />
          <.created_section unit={@compliance} />
          <.delta_section unit={@compliance} />
        <% end %>
      <% end %>
    </Layouts.app>
    """
  end

  defp loading_skeleton(assigns) do
    ~H"""
    <.loading_blocks message="Loading compliance details..." class="py-12" />
    """
  end

  defp compliance_header(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4">Overview</h2>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Position of this compliance unit within the action">Index</div>
          <div class="font-mono">{@unit["index"]}</div>
        </div>
        <%= if @unit["action"] do %>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Network</div>
            <div>
              <span class="badge badge-outline" title={"Chain ID: #{@unit["action"]["chainId"]}"}>
                {Networks.name(@unit["action"]["chainId"])}
              </span>
            </div>
          </div>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Block Number</div>
            <div class="font-mono">{@unit["action"]["blockNumber"]}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Timestamp</div>
            <div>{Formatting.format_timestamp_full(@unit["action"]["timestamp"])}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Action</div>
            <div class="flex items-center gap-1">
              <a
                href={"/actions/#{@unit["action"]["id"]}"}
                class="hash-display text-sm hover:text-primary"
              >
                {Formatting.truncate_hash(@unit["action"]["actionTreeRoot"])}
              </a>
              <.copy_button
                :if={@unit["action"]["actionTreeRoot"]}
                text={@unit["action"]["actionTreeRoot"]}
                tooltip="Copy action tree root"
              />
            </div>
          </div>
          <%= if @unit["action"]["transaction"] do %>
            <div>
              <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Transaction</div>
              <div class="flex items-center gap-1">
                <a
                  href={"/transactions/#{@unit["action"]["transaction"]["id"]}"}
                  class="hash-display text-sm hover:text-primary"
                >
                  {Formatting.truncate_hash(@unit["action"]["transaction"]["evmTransaction"]["txHash"])}
                </a>
                <.copy_button text={@unit["action"]["transaction"]["evmTransaction"]["txHash"]} tooltip="Copy tx hash" />
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp consumed_section(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4 flex items-center gap-2" title="The resource being spent/consumed in this compliance unit">
        <span class="badge badge-outline badge-sm text-error border-error/50">Nullifier</span> Input
      </h2>
      <div class="grid grid-cols-1 gap-4">
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Hash that proves this resource has been consumed - prevents double-spending">Nullifier</div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@unit["consumedNullifier"] || "-"}</code>
            <.copy_button :if={@unit["consumedNullifier"]} text={@unit["consumedNullifier"]} tooltip="Copy nullifier" />
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Reference to the logic circuit that validates this resource's consumption">Logic Ref</div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@unit["consumedLogicRef"] || "-"}</code>
            <.copy_button
              :if={@unit["consumedLogicRef"]}
              text={@unit["consumedLogicRef"]}
              tooltip="Copy logic ref"
            />
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Merkle root proving the consumed resource existed in the commitment tree">
            Commitment Tree Root
          </div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">
              {@unit["consumedCommitmentTreeRoot"] || "-"}
            </code>
            <.copy_button
              :if={@unit["consumedCommitmentTreeRoot"]}
              text={@unit["consumedCommitmentTreeRoot"]}
              tooltip="Copy commitment tree root"
            />
          </div>
        </div>
        <%= if @unit["consumedResource"] do %>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Link to the full resource record if available">Resource</div>
            <div class="flex items-center gap-1">
              <a
                href={"/resources/#{@unit["consumedResource"]["id"]}"}
                class="hash-display text-sm hover:text-primary"
              >
                {Formatting.truncate_hash(@unit["consumedResource"]["tag"])}
              </a>
              <.copy_button
                :if={@unit["consumedResource"]["tag"]}
                text={@unit["consumedResource"]["tag"]}
                tooltip="Copy resource ID"
              />
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp created_section(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4 flex items-center gap-2" title="The new resource being created in this compliance unit">
        <span class="badge badge-outline badge-sm text-success border-success/50">Commitment</span>
        Output
      </h2>
      <div class="grid grid-cols-1 gap-4">
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Hash representing the newly created resource - added to the commitment tree">Commitment</div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@unit["createdCommitment"] || "-"}</code>
            <.copy_button :if={@unit["createdCommitment"]} text={@unit["createdCommitment"]} tooltip="Copy commitment" />
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Reference to the logic circuit that validates this resource's creation">Logic Ref</div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@unit["createdLogicRef"] || "-"}</code>
            <.copy_button
              :if={@unit["createdLogicRef"]}
              text={@unit["createdLogicRef"]}
              tooltip="Copy logic ref"
            />
          </div>
        </div>
        <%= if @unit["createdResource"] do %>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Link to the full resource record">Resource</div>
            <div class="flex items-center gap-1">
              <a
                href={"/resources/#{@unit["createdResource"]["id"]}"}
                class="hash-display text-sm hover:text-primary"
              >
                {Formatting.truncate_hash(@unit["createdResource"]["tag"])}
              </a>
              <.copy_button
                :if={@unit["createdResource"]["tag"]}
                text={@unit["createdResource"]["tag"]}
                tooltip="Copy resource ID"
              />
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp delta_section(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4" title="Value balance proof using secp256k1 elliptic curve points">Unit Delta</h2>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="X coordinate of the secp256k1 delta point for value balance verification">Delta X</div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@unit["unitDeltaX"] || "-"}</code>
            <.copy_button :if={@unit["unitDeltaX"]} text={@unit["unitDeltaX"]} tooltip="Copy delta X" />
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Y coordinate of the secp256k1 delta point for value balance verification">Delta Y</div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@unit["unitDeltaY"] || "-"}</code>
            <.copy_button :if={@unit["unitDeltaY"]} text={@unit["unitDeltaY"]} tooltip="Copy delta Y" />
          </div>
        </div>
      </div>
      <div class="mt-4 text-sm text-base-content/60 italic">
        Proof not included for the moment.
      </div>
    </div>
    """
  end

end
