defmodule AnomaExplorerWeb.ComplianceLive do
  @moduledoc """
  LiveView for displaying a single compliance unit's details.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Networks

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
    <div class="stat-card animate-pulse">
      <div class="space-y-4">
        <div class="h-6 bg-base-300 rounded w-1/4"></div>
        <div class="h-4 bg-base-300 rounded w-3/4"></div>
        <div class="h-4 bg-base-300 rounded w-1/2"></div>
      </div>
    </div>
    """
  end

  defp compliance_header(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4">Overview</h2>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Index</div>
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
            <div>{format_timestamp(@unit["action"]["timestamp"])}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Action</div>
            <div class="flex items-center gap-1">
              <a
                href={"/actions/#{@unit["action"]["id"]}"}
                class="hash-display text-sm hover:text-primary"
              >
                {truncate_hash(@unit["action"]["actionTreeRoot"])}
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
                  {truncate_hash(@unit["action"]["transaction"]["txHash"])}
                </a>
                <.copy_button
                  text={@unit["action"]["transaction"]["txHash"]}
                  tooltip="Copy tx hash"
                />
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
      <h2 class="text-lg font-semibold mb-4 flex items-center gap-2">
        <span class="badge badge-outline badge-sm text-error border-error/50">Consumed</span>
        Input
      </h2>
      <div class="grid grid-cols-1 gap-4">
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Nullifier</div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@unit["consumedNullifier"] || "-"}</code>
            <.copy_button :if={@unit["consumedNullifier"]} text={@unit["consumedNullifier"]} />
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Logic Ref</div>
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
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">
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
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Resource</div>
            <div class="flex items-center gap-1">
              <a
                href={"/resources/#{@unit["consumedResource"]["id"]}"}
                class="hash-display text-sm hover:text-primary"
              >
                {truncate_hash(@unit["consumedResource"]["tag"])}
              </a>
              <.copy_button
                :if={@unit["consumedResource"]["tag"]}
                text={@unit["consumedResource"]["tag"]}
                tooltip="Copy tag"
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
      <h2 class="text-lg font-semibold mb-4 flex items-center gap-2">
        <span class="badge badge-outline badge-sm text-success border-success/50">Created</span>
        Output
      </h2>
      <div class="grid grid-cols-1 gap-4">
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Commitment</div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@unit["createdCommitment"] || "-"}</code>
            <.copy_button :if={@unit["createdCommitment"]} text={@unit["createdCommitment"]} />
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Logic Ref</div>
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
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Resource</div>
            <div class="flex items-center gap-1">
              <a
                href={"/resources/#{@unit["createdResource"]["id"]}"}
                class="hash-display text-sm hover:text-primary"
              >
                {truncate_hash(@unit["createdResource"]["tag"])}
              </a>
              <.copy_button
                :if={@unit["createdResource"]["tag"]}
                text={@unit["createdResource"]["tag"]}
                tooltip="Copy tag"
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
      <h2 class="text-lg font-semibold mb-4">Unit Delta</h2>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Delta X</div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@unit["unitDeltaX"] || "-"}</code>
            <.copy_button
              :if={@unit["unitDeltaX"]}
              text={@unit["unitDeltaX"]}
              tooltip="Copy delta X"
            />
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Delta Y</div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@unit["unitDeltaY"] || "-"}</code>
            <.copy_button
              :if={@unit["unitDeltaY"]}
              text={@unit["unitDeltaY"]}
              tooltip="Copy delta Y"
            />
          </div>
        </div>
      </div>
      <%= if @unit["proof"] do %>
        <div class="mt-4">
          <div class="flex items-center justify-between mb-1">
            <div class="text-xs text-base-content/60 uppercase tracking-wide">Proof</div>
            <.copy_button text={@unit["proof"]} tooltip="Copy proof" />
          </div>
          <div class="bg-base-200/50 p-3 rounded-lg overflow-x-auto">
            <code class="text-xs break-all">{@unit["proof"]}</code>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp truncate_hash(nil), do: "-"

  defp truncate_hash(hash) when byte_size(hash) > 20 do
    String.slice(hash, 0, 10) <> "..." <> String.slice(hash, -8, 8)
  end

  defp truncate_hash(hash), do: hash

  defp format_timestamp(nil), do: "-"

  defp format_timestamp(ts) when is_integer(ts) do
    case DateTime.from_unix(ts) do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
      _ -> "-"
    end
  end
end
