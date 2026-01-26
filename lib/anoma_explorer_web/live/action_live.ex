defmodule AnomaExplorerWeb.ActionLive do
  @moduledoc """
  LiveView for displaying a single action's details.
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
      |> assign(:page_title, "Action Details")
      |> assign(:action, nil)
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:action_id, id)

    if connected?(socket) do
      send(self(), {:load_action, id})
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:load_action, id}, socket) do
    case GraphQL.get_action(id) do
      {:ok, action} ->
        {:noreply,
         socket
         |> assign(:action, action)
         |> assign(:loading, false)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:error, "Action not found")
         |> assign(:loading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, "Failed to load action: #{inspect(reason)}")
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
    <Layouts.app flash={@flash} current_path="/actions">
      <div class="page-header">
        <div class="flex items-center gap-3">
          <a href="/actions" class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="w-4 h-4" />
          </a>
          <div>
            <h1 class="page-title">Action Details</h1>
            <p class="text-sm text-base-content/70 mt-1">
              {if @action, do: Formatting.truncate_hash(@action["actionTreeRoot"]), else: "Loading..."}
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
        <%= if @action do %>
          <.action_header action={@action} />
          <.compliance_units_section units={@action["complianceUnits"] || []} />
          <.logic_inputs_section inputs={@action["logicInputs"] || []} />
        <% end %>
      <% end %>
    </Layouts.app>
    """
  end

  defp loading_skeleton(assigns) do
    ~H"""
    <.loading_blocks message="Loading action details..." class="py-12" />
    """
  end

  defp action_header(assigns) do
    assigns =
      assign(
        assigns,
        :block_url,
        Networks.block_url(assigns.action["chainId"], assigns.action["blockNumber"])
      )

    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4">Overview</h2>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="md:col-span-2">
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Merkle root uniquely identifying this action and all its contents">
            Action Tree Root
          </div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@action["actionTreeRoot"]}</code>
            <.copy_button text={@action["actionTreeRoot"]} tooltip="Copy action tree root" />
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Total number of resource tags (nullifiers + commitments) in this action">Tag Count</div>
          <div><span class="badge badge-ghost">{@action["tagCount"]}</span></div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Position of this action within the transaction's actions array">Index</div>
          <div class="font-mono">{@action["index"]}</div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Blockchain block where this action was recorded">Block Number</div>
          <div class="flex items-center gap-2">
            <%= if @block_url do %>
              <a href={@block_url} target="_blank" class="font-mono hover:text-primary">
                {@action["blockNumber"]}
                <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3 inline ml-1" />
              </a>
            <% else %>
              <span class="font-mono">{@action["blockNumber"]}</span>
            <% end %>
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="Blockchain network where this action was recorded">Network</div>
          <div>
            <span class="text-sm text-base-content/70" title={"Chain ID: #{@action["chainId"]}"}>
              {Networks.name(@action["chainId"])}
            </span>
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="When this action was recorded on the blockchain">Timestamp</div>
          <div>{Formatting.format_timestamp_full(@action["timestamp"])}</div>
        </div>
        <%= if @action["transaction"] do %>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1" title="EVM transaction that submitted this action to the blockchain">Transaction</div>
            <div class="flex items-center gap-1">
              <a
                href={"/transactions/#{@action["transaction"]["id"]}"}
                class="hash-display text-sm hover:text-primary"
              >
                {Formatting.truncate_hash(@action["transaction"]["evmTransaction"]["txHash"])}
              </a>
              <.copy_button text={@action["transaction"]["evmTransaction"]["txHash"]} tooltip="Copy tx hash" />
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp compliance_units_section(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4" title="Pairs of consumed (input) and created (output) resources that balance each other">
        Compliance Units <span class="badge badge-ghost ml-2">{length(@units)}</span>
      </h2>
      <%= if @units == [] do %>
        <div class="text-base-content/50 text-center py-4">No compliance units</div>
      <% else %>
        <div class="overflow-x-auto">
          <table class="data-table w-full">
            <thead>
              <tr>
                <th title="Hash proving the input resource was consumed - prevents double-spending">Consumed Nullifier</th>
                <th title="Hash representing the new output resource added to the commitment tree">Created Commitment</th>
                <th title="Logic circuit reference validating the consumed resource">Consumed Logic Ref</th>
                <th title="Logic circuit reference validating the created resource">Created Logic Ref</th>
              </tr>
            </thead>
            <tbody>
              <%= for unit <- @units do %>
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
                    <div class="flex items-center gap-1">
                      <code class="hash-display text-xs">
                        {Formatting.truncate_hash(unit["createdLogicRef"])}
                      </code>
                      <.copy_button
                        :if={unit["createdLogicRef"]}
                        text={unit["createdLogicRef"]}
                        tooltip="Copy logic ref"
                      />
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp logic_inputs_section(assigns) do
    ~H"""
    <div class="stat-card">
      <h2 class="text-lg font-semibold mb-4" title="Resources with their logic circuit references and proofs for this action">
        Logic Inputs <span class="badge badge-ghost ml-2">{length(@inputs)}</span>
      </h2>
      <%= if @inputs == [] do %>
        <div class="text-base-content/50 text-center py-4">No logic inputs</div>
      <% else %>
        <div class="overflow-x-auto">
          <table class="data-table w-full">
            <thead>
              <tr>
                <th title="Unique identifier - nullifier hash (if consumed) or commitment hash (if created)">Resource ID</th>
                <th title="Determined by index parity: even = Nullifier (consumed), odd = Commitment (created)">Type</th>
                <th title="Reference to the logic circuit (verifying key) that validates this resource">Logic Ref</th>
              </tr>
            </thead>
            <tbody>
              <%= for input <- @inputs do %>
                <tr class="hover:bg-base-200/50">
                  <td>
                    <div class="flex items-center gap-1">
                      <%= if input["resource"] do %>
                        <a
                          href={"/resources/#{input["resource"]["id"]}"}
                          class="hash-display text-xs hover:text-primary"
                        >
                          {Formatting.truncate_hash(input["tag"])}
                        </a>
                      <% else %>
                        <a
                          href={"/logics/#{input["id"]}"}
                          class="hash-display text-xs hover:text-primary"
                          title="No linked resource - view logic input"
                        >
                          {Formatting.truncate_hash(input["tag"])}
                        </a>
                      <% end %>
                      <.copy_button :if={input["tag"]} text={input["tag"]} tooltip="Copy resource ID" />
                    </div>
                  </td>
                  <td>
                    <%= if input["isConsumed"] do %>
                      <span class="badge badge-outline badge-sm text-error border-error/50" title="Nullifier - resource consumed as input">
                        Nullifier
                      </span>
                    <% else %>
                      <span class="badge badge-outline badge-sm text-success border-success/50" title="Commitment - new resource created as output">
                        Commitment
                      </span>
                    <% end %>
                  </td>
                  <td>
                    <div class="flex items-center gap-1">
                      <code class="hash-display text-xs">{Formatting.truncate_hash(input["logicRef"])}</code>
                      <.copy_button
                        :if={input["logicRef"]}
                        text={input["logicRef"]}
                        tooltip="Copy logic ref"
                      />
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

end
