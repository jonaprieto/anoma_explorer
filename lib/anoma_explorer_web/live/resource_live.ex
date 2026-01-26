defmodule AnomaExplorerWeb.ResourceLive do
  @moduledoc """
  LiveView for displaying a single resource's details.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Networks
  alias AnomaExplorer.Utils.Formatting

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket), do: send(self(), {:load_data, id})

    {:ok,
     socket
     |> assign(:page_title, "Resource")
     |> assign(:resource, nil)
     |> assign(:loading, true)
     |> assign(:error, nil)
     |> assign(:show_raw_blob, false)
     |> assign(:resource_id, id)}
  end

  @impl true
  def handle_info({:load_data, id}, socket) do
    case GraphQL.get_resource(id) do
      {:ok, resource} ->
        {:noreply,
         socket
         |> assign(:resource, resource)
         |> assign(:loading, false)
         |> assign(:page_title, "Resource #{Formatting.truncate_hash(resource["tag"])}")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Resource not found")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Error loading resource: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("toggle_raw_blob", _params, socket) do
    {:noreply, assign(socket, :show_raw_blob, not socket.assigns.show_raw_blob)}
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
    <Layouts.app flash={@flash} current_path="/resources">
      <div class="page-header">
        <div class="flex items-center gap-3">
          <a href="/resources" class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="w-4 h-4" />
          </a>
          <div>
            <h1 class="page-title">Resource Details</h1>
            <p class="text-sm text-base-content/70 mt-1">
              {if @resource, do: Formatting.truncate_hash(@resource["tag"]), else: "Loading..."}
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
        <%= if @resource do %>
          <.resource_header resource={@resource} />
          <.decoded_fields resource={@resource} />
          <.payloads_section resource={@resource} />
          <.raw_blob_section resource={@resource} show={@show_raw_blob} />
          <.transaction_section resource={@resource} />
        <% end %>
      <% end %>
    </Layouts.app>
    """
  end

  defp loading_skeleton(assigns) do
    ~H"""
    <.loading_blocks message="Loading resource details..." class="py-12" />
    """
  end

  defp resource_header(assigns) do
    assigns =
      assign(
        assigns,
        :block_url,
        Networks.block_url(assigns.resource["chainId"], assigns.resource["blockNumber"])
      )

    ~H"""
    <div class="stat-card mb-6">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Overview</h2>
        <%= if @resource["isConsumed"] do %>
          <span class="badge badge-outline text-error border-error/50" title="Nullifier - resource consumed as input">Nullifier</span>
        <% else %>
          <span class="badge badge-outline text-success border-success/50" title="Commitment - new resource created as output">Commitment</span>
        <% end %>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="md:col-span-2">
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Unique identifier - nullifier hash (if consumed) or commitment hash (if created)">Resource ID</div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@resource["tag"]}</code>
            <.copy_button text={@resource["tag"]} tooltip="Copy resource ID" />
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Position in the transaction's tags array (even = nullifier, odd = commitment)">Index</div>
          <div class="font-mono">{@resource["index"]}</div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Blockchain block where this resource was recorded">Block Number</div>
          <div class="flex items-center gap-2">
            <%= if @block_url do %>
              <a href={@block_url} target="_blank" class="font-mono hover:text-primary">
                {@resource["blockNumber"]}
                <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3 inline ml-1" />
              </a>
            <% else %>
              <span class="font-mono">{@resource["blockNumber"]}</span>
            <% end %>
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Blockchain network where this resource exists">Network</div>
          <div>
            <span class="badge badge-outline" title={"Chain ID: #{@resource["chainId"]}"}>
              {Networks.name(@resource["chainId"])}
            </span>
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Status of decoding the raw blob data into structured resource fields">Decoding Status</div>
          <.decoding_badge status={@resource["decodingStatus"]} error={@resource["decodingError"]} />
        </div>
      </div>
    </div>
    """
  end

  defp decoded_fields(assigns) do
    ~H"""
    <%= if @resource["logicRef"] do %>
      <div class="stat-card mb-6">
        <h2 class="text-lg font-semibold mb-4" title="Reference to the logic circuit that governs this resource's behavior">Logic Reference</h2>
        <div class="flex items-center gap-2">
          <code class="hash-display text-sm break-all">{@resource["logicRef"]}</code>
          <.copy_button text={@resource["logicRef"]} tooltip="Copy logic ref" />
        </div>
      </div>
    <% end %>
    """
  end

  defp payloads_section(assigns) do
    ~H"""
    <%= if @resource["payloads"] && length(@resource["payloads"]) > 0 do %>
      <div class="stat-card mb-6">
        <h2 class="text-lg font-semibold mb-4" title="Application data associated with this resource">
          Payloads
          <span class="badge badge-ghost badge-sm ml-2">{length(@resource["payloads"])}</span>
        </h2>
        <div class="overflow-x-auto">
          <table class="data-table w-full">
            <thead>
              <tr>
                <th title="Type of payload: discovery (for indexing), application (app-specific), external (off-chain), or resource (resource data)">Kind</th>
                <th title="Position in the payload array">Index</th>
                <th title="Raw encoded payload data">Blob</th>
              </tr>
            </thead>
            <tbody>
              <%= for payload <- @resource["payloads"] do %>
                <tr class="hover:bg-base-200/50">
                  <td>
                    <span class={"badge badge-outline badge-sm #{payload_kind_class(payload["kind"])}"} title={payload_kind_tooltip(payload["kind"])}>
                      {payload["kind"]}
                    </span>
                  </td>
                  <td class="font-mono">{payload["index"]}</td>
                  <td>
                    <div class="flex items-center gap-1">
                      <code class="hash-display text-xs">{Formatting.truncate_hash(payload["blob"], max_length: 30, prefix_length: 15, suffix_length: 10)}</code>
                      <.copy_button text={payload["blob"]} tooltip="Copy blob" />
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    <% end %>
    """
  end

  defp payload_kind_class("discovery"), do: "text-info border-info/50"
  defp payload_kind_class("application"), do: "text-primary border-primary/50"
  defp payload_kind_class("external"), do: "text-warning border-warning/50"
  defp payload_kind_class("resource"), do: "text-success border-success/50"
  defp payload_kind_class(_), do: ""

  defp payload_kind_tooltip("discovery"), do: "Discovery payload - data for resource indexing and discovery"
  defp payload_kind_tooltip("application"), do: "Application payload - app-specific data for the logic circuit"
  defp payload_kind_tooltip("external"), do: "External payload - data stored off-chain"
  defp payload_kind_tooltip("resource"), do: "Resource payload - encoded resource data"
  defp payload_kind_tooltip(_), do: ""

  defp field_row(assigns) do
    assigns = assign_new(assigns, :copyable, fn -> false end)

    ~H"""
    <div>
      <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">{@label}</div>
      <%= if @value do %>
        <div class="flex items-center gap-2">
          <code class="hash-display text-sm break-all">{Formatting.truncate_value(@value)}</code>
          <.copy_button :if={@copyable and is_binary(@value)} text={@value} />
        </div>
      <% else %>
        <span class="text-base-content/40">-</span>
      <% end %>
    </div>
    """
  end

  defp raw_blob_section(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Raw Blob</h2>
        <button phx-click="toggle_raw_blob" class="btn btn-ghost btn-sm">
          <%= if @show do %>
            <.icon name="hero-chevron-up" class="w-4 h-4" /> Hide
          <% else %>
            <.icon name="hero-chevron-down" class="w-4 h-4" /> Show
          <% end %>
        </button>
      </div>
      <%= if @show do %>
        <%= if @resource["rawBlob"] && @resource["rawBlob"] != "" do %>
          <div class="bg-base-200 rounded-lg p-4 overflow-x-auto">
            <code class="text-xs font-mono break-all whitespace-pre-wrap">
              {@resource["rawBlob"]}
            </code>
          </div>
        <% else %>
          <div class="text-base-content/50 text-center py-4">No raw blob data</div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp transaction_section(assigns) do
    assigns =
      if assigns.resource["transaction"] do
        chain_id = assigns.resource["chainId"]
        tx = assigns.resource["transaction"]
        evm_tx = tx["evmTransaction"]

        assigns
        |> assign(:tx_block_url, Networks.block_url(chain_id, evm_tx["blockNumber"]))
        |> assign(:tx_url, Networks.tx_url(chain_id, evm_tx["txHash"]))
        |> assign(:evm_tx, evm_tx)
      else
        assigns
        |> assign(:tx_block_url, nil)
        |> assign(:tx_url, nil)
        |> assign(:evm_tx, nil)
      end

    ~H"""
    <%= if @resource["transaction"] do %>
      <div class="stat-card">
        <h2 class="text-lg font-semibold mb-4">Parent Transaction</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="md:col-span-2">
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">
              Transaction Hash
            </div>
            <div class="flex items-center gap-2">
              <a
                href={"/transactions/#{@resource["transaction"]["id"]}"}
                class="hash-display text-sm hover:text-primary"
              >
                {@evm_tx["txHash"]}
              </a>
              <.copy_button text={@evm_tx["txHash"]} tooltip="Copy tx hash" />
              <%= if @tx_url do %>
                <a
                  href={@tx_url}
                  target="_blank"
                  class="btn btn-ghost btn-xs"
                  title="View on Explorer"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3" />
                </a>
              <% end %>
            </div>
          </div>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Block</div>
            <div class="flex items-center gap-2">
              <%= if @tx_block_url do %>
                <a href={@tx_block_url} target="_blank" class="font-mono hover:text-primary">
                  {@evm_tx["blockNumber"]}
                  <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3 inline ml-1" />
                </a>
              <% else %>
                <span class="font-mono">{@evm_tx["blockNumber"]}</span>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp decoding_badge(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <%= case @status do %>
        <% "success" -> %>
          <span class="badge badge-outline text-success border-success/50">Decoded</span>
        <% "failed" -> %>
          <span class="badge badge-outline text-error border-error/50">Failed</span>
          <%= if @error do %>
            <span class="text-xs text-error" title={@error}>
              <.icon name="hero-information-circle" class="w-4 h-4" />
            </span>
          <% end %>
        <% "pending" -> %>
          <span class="badge badge-outline text-warning border-warning/50">Pending</span>
        <% _ -> %>
          <span class="badge badge-outline badge-ghost">{@status || "-"}</span>
      <% end %>
    </div>
    """
  end

end
