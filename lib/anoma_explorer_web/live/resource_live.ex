defmodule AnomaExplorerWeb.ResourceLive do
  @moduledoc """
  LiveView for displaying a single resource's details.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Networks

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
         |> assign(:page_title, "Resource #{truncate_hash(resource["tag"])}")}

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
              {if @resource, do: truncate_hash(@resource["tag"]), else: "Loading..."}
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
          <.raw_blob_section resource={@resource} show={@show_raw_blob} />
          <.transaction_section resource={@resource} />
        <% end %>
      <% end %>
    </Layouts.app>
    """
  end

  defp loading_skeleton(assigns) do
    ~H"""
    <div class="space-y-6 animate-pulse">
      <div class="stat-card">
        <div class="h-6 bg-base-300 rounded w-48 mb-4"></div>
        <div class="space-y-2">
          <div class="h-4 bg-base-300 rounded w-full"></div>
          <div class="h-4 bg-base-300 rounded w-3/4"></div>
        </div>
      </div>
    </div>
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
          <span class="badge badge-outline text-error border-error/50">Consumed</span>
        <% else %>
          <span class="badge badge-outline text-success border-success/50">Created</span>
        <% end %>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="md:col-span-2">
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Tag</div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@resource["tag"]}</code>
            <.copy_button text={@resource["tag"]} />
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Index</div>
          <div class="font-mono">{@resource["index"]}</div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Block Number</div>
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
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Network</div>
          <div>
            <span class="badge badge-outline" title={"Chain ID: #{@resource["chainId"]}"}>
              {Networks.name(@resource["chainId"])}
            </span>
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Decoding Status</div>
          <.decoding_badge status={@resource["decodingStatus"]} error={@resource["decodingError"]} />
        </div>
      </div>
    </div>
    """
  end

  defp decoded_fields(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4">Decoded Fields</h2>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.field_row label="Logic Ref" value={@resource["logicRef"]} copyable />
        <.field_row label="Label Ref" value={@resource["labelRef"]} copyable />
        <.field_row label="Value Ref" value={@resource["valueRef"]} copyable />
        <.field_row
          label="Nullifier Key Commitment"
          value={@resource["nullifierKeyCommitment"]}
          copyable
        />
        <.field_row label="Nonce" value={@resource["nonce"]} copyable />
        <.field_row label="Rand Seed" value={@resource["randSeed"]} copyable />
        <.field_row label="Quantity" value={@resource["quantity"]} />
        <.field_row label="Ephemeral" value={format_bool(@resource["ephemeral"])} />
      </div>
    </div>
    """
  end

  defp field_row(assigns) do
    assigns = assign_new(assigns, :copyable, fn -> false end)

    ~H"""
    <div>
      <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">{@label}</div>
      <%= if @value do %>
        <div class="flex items-center gap-2">
          <code class="hash-display text-sm break-all">{truncate_value(@value)}</code>
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

        assigns
        |> assign(:tx_block_url, Networks.block_url(chain_id, tx["blockNumber"]))
        |> assign(:tx_url, Networks.tx_url(chain_id, tx["txHash"]))
      else
        assigns
        |> assign(:tx_block_url, nil)
        |> assign(:tx_url, nil)
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
                {@resource["transaction"]["txHash"]}
              </a>
              <.copy_button text={@resource["transaction"]["txHash"]} tooltip="Copy tx hash" />
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
                  {@resource["transaction"]["blockNumber"]}
                  <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3 inline ml-1" />
                </a>
              <% else %>
                <span class="font-mono">{@resource["transaction"]["blockNumber"]}</span>
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

  defp truncate_hash(nil), do: "-"

  defp truncate_hash(hash) when byte_size(hash) > 20 do
    String.slice(hash, 0, 10) <> "..." <> String.slice(hash, -8, 8)
  end

  defp truncate_hash(hash), do: hash

  defp truncate_value(nil), do: nil

  defp truncate_value(val) when is_binary(val) and byte_size(val) > 50 do
    String.slice(val, 0, 24) <> "..." <> String.slice(val, -24, 24)
  end

  defp truncate_value(val), do: to_string(val)

  defp format_bool(nil), do: nil
  defp format_bool(true), do: "Yes"
  defp format_bool(false), do: "No"
end
