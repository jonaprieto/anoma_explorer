defmodule AnomaExplorerWeb.TransactionLive do
  @moduledoc """
  LiveView for displaying a single transaction's details.
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
     |> assign(:page_title, "Transaction")
     |> assign(:transaction, nil)
     |> assign(:loading, true)
     |> assign(:error, nil)
     |> assign(:tx_id, id)
     |> assign(:selected_chain, nil)}
  end

  @impl true
  def handle_info({:load_data, id}, socket) do
    case GraphQL.get_transaction(id) do
      {:ok, transaction} ->
        {:noreply,
         socket
         |> assign(:transaction, transaction)
         |> assign(:loading, false)
         |> assign(:page_title, "Transaction #{Formatting.truncate_hash(transaction["txHash"])}")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Transaction not found")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Error loading transaction: #{inspect(reason)}")}
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

  def handle_event("show_chain_info", %{"chain-id" => chain_id_str}, socket) do
    chain_id = String.to_integer(chain_id_str)
    chain_info = Networks.chain_info(chain_id)
    {:noreply, assign(socket, :selected_chain, chain_info)}
  end

  def handle_event("close_chain_modal", _params, socket) do
    {:noreply, assign(socket, :selected_chain, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/transactions">
      <div class="page-header">
        <div class="flex items-center gap-3">
          <a href="/transactions" class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" class="w-4 h-4" />
          </a>
          <div>
            <h1 class="page-title">Transaction Details</h1>
            <p class="text-sm text-base-content/70 mt-1">
              {if @transaction, do: Formatting.truncate_hash(@transaction["txHash"]), else: "Loading..."}
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
        <%= if @transaction do %>
          <.transaction_header tx={@transaction} />
          <.resources_section resources={@transaction["resources"] || []} />
          <.actions_section actions={@transaction["actions"] || []} />
          <.tags_section tags={@transaction["tags"]} logic_refs={@transaction["logicRefs"]} />
        <% end %>
      <% end %>

      <.chain_info_modal chain={@selected_chain} />
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

  defp transaction_header(assigns) do
    assigns =
      assign(
        assigns,
        :block_url,
        Networks.block_url(assigns.tx["chainId"], assigns.tx["blockNumber"])
      )

    assigns =
      assign(assigns, :tx_url, Networks.tx_url(assigns.tx["chainId"], assigns.tx["txHash"]))

    assigns =
      assign(
        assigns,
        :contract_url,
        Networks.address_url(assigns.tx["chainId"], assigns.tx["contractAddress"])
      )

    assigns =
      assign(
        assigns,
        :from_url,
        if(assigns.tx["from"], do: Networks.address_url(assigns.tx["chainId"], assigns.tx["from"]))
      )

    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4">Overview</h2>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="md:col-span-2">
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">
            Transaction Hash
          </div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@tx["txHash"]}</code>
            <.copy_button text={@tx["txHash"]} />
            <%= if @tx_url do %>
              <a
                href={@tx_url}
                target="_blank"
                class="btn btn-ghost shrink-0 opacity-60 hover:opacity-100"
                title="View on Explorer"
              >
                <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
              </a>
            <% end %>
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Timestamp</div>
          <div class="font-mono">{Formatting.format_timestamp_full(@tx["timestamp"])}</div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Network</div>
          <div>
            <.network_button chain_id={@tx["chainId"]} />
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Block Number</div>
          <div class="flex items-center gap-2">
            <%= if @block_url do %>
              <a href={@block_url} target="_blank" class="font-mono hover:text-primary">
                {@tx["blockNumber"]}
                <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3 inline ml-1" />
              </a>
            <% else %>
              <span class="font-mono">{@tx["blockNumber"]}</span>
            <% end %>
            <.copy_button text={to_string(@tx["blockNumber"])} tooltip="Copy block number" />
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">From</div>
          <div class="flex items-center gap-2">
            <%= if @tx["from"] do %>
              <code class="hash-display text-sm">{Formatting.truncate_hash(@tx["from"])}</code>
              <.copy_button text={@tx["from"]} tooltip="Copy address" />
              <%= if @from_url do %>
                <a
                  href={@from_url}
                  target="_blank"
                  class="btn btn-ghost shrink-0 opacity-60 hover:opacity-100"
                  title="View on Explorer"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
                </a>
              <% end %>
            <% else %>
              <span class="text-base-content/50">-</span>
            <% end %>
          </div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Value</div>
          <div class="font-mono">{Formatting.format_eth(@tx["value"])}</div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Gas Price</div>
          <div class="font-mono">{Formatting.format_gwei(@tx["gasPrice"])}</div>
        </div>
        <div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Transaction Fee</div>
          <div class="font-mono">{Formatting.format_tx_fee(@tx["gasUsed"], @tx["gasPrice"])}</div>
        </div>
        <%= if @tx["contractAddress"] do %>
          <div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">
              Contract Address
            </div>
            <div class="flex items-center gap-2">
              <code class="hash-display text-sm">{@tx["contractAddress"]}</code>
              <.copy_button text={@tx["contractAddress"]} tooltip="Copy address" />
              <%= if @contract_url do %>
                <a
                  href={@contract_url}
                  target="_blank"
                  class="btn btn-ghost shrink-0 opacity-60 hover:opacity-100"
                  title="View on Explorer"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
                </a>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp tags_section(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4">
        Tags & Logic Refs <span class="badge badge-ghost ml-2">{length(@tags || [])}</span>
      </h2>
      <%= if (@tags || []) == [] do %>
        <div class="text-base-content/50 text-center py-4">No tags</div>
      <% else %>
        <div class="overflow-x-auto">
          <table class="data-table w-full">
            <thead>
              <tr>
                <th>Index</th>
                <th>Type</th>
                <th>Tag</th>
                <th>Logic Ref</th>
              </tr>
            </thead>
            <tbody>
              <%= for {tag, idx} <- Enum.with_index(@tags || []) do %>
                <% is_consumed = rem(idx, 2) == 0 %>
                <% logic_ref = Enum.at(@logic_refs || [], idx) %>
                <tr>
                  <td>
                    <span class="badge badge-ghost badge-sm">{idx}</span>
                  </td>
                  <td>
                    <%= if is_consumed do %>
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
                      <code class="hash-display text-xs">{Formatting.truncate_hash(tag)}</code>
                      <.copy_button :if={tag} text={tag} tooltip="Copy tag" />
                    </div>
                  </td>
                  <td>
                    <div class="flex items-center gap-1">
                      <code class="hash-display text-xs">{Formatting.truncate_hash(logic_ref)}</code>
                      <.copy_button :if={logic_ref} text={logic_ref} tooltip="Copy logic ref" />
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

  defp resources_section(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4">
        Resources <span class="badge badge-ghost ml-2">{length(@resources)}</span>
      </h2>
      <%= if @resources == [] do %>
        <div class="text-base-content/50 text-center py-4">No resources</div>
      <% else %>
        <div class="overflow-x-auto">
          <table class="data-table w-full">
            <thead>
              <tr>
                <th>Tag</th>
                <th>Status</th>
                <th>Logic Ref</th>
                <th>Quantity</th>
                <th>Decoding</th>
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
                        {Formatting.truncate_hash(resource["tag"])}
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
                    <div class="flex items-center gap-1">
                      <code class="hash-display text-xs">{Formatting.truncate_hash(resource["logicRef"])}</code>
                      <.copy_button
                        :if={resource["logicRef"]}
                        text={resource["logicRef"]}
                        tooltip="Copy logic ref"
                      />
                    </div>
                  </td>
                  <td>
                    {resource["quantity"] || "-"}
                  </td>
                  <td>
                    <.decoding_badge status={resource["decodingStatus"]} />
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

  defp actions_section(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4">
        Actions <span class="badge badge-ghost ml-2">{length(@actions)}</span>
      </h2>
      <%= if @actions == [] do %>
        <div class="text-base-content/50 text-center py-4">No actions</div>
      <% else %>
        <div class="overflow-x-auto">
          <table class="data-table w-full">
            <thead>
              <tr>
                <th>Action Tree Root</th>
                <th>Tag Count</th>
              </tr>
            </thead>
            <tbody>
              <%= for action <- @actions do %>
                <tr>
                  <td>
                    <div class="flex items-center gap-1">
                      <a
                        href={"/actions/#{action["id"]}"}
                        class="hash-display text-xs hover:text-primary"
                      >
                        {Formatting.truncate_hash(action["actionTreeRoot"])}
                      </a>
                      <.copy_button
                        :if={action["actionTreeRoot"]}
                        text={action["actionTreeRoot"]}
                        tooltip="Copy action tree root"
                      />
                    </div>
                  </td>
                  <td>
                    <span class="badge badge-ghost">{action["tagCount"]}</span>
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

  defp decoding_badge(assigns) do
    ~H"""
    <%= case @status do %>
      <% "success" -> %>
        <span class="badge badge-outline badge-sm text-success border-success/50">Decoded</span>
      <% "failed" -> %>
        <span class="badge badge-outline badge-sm text-error border-error/50">Failed</span>
      <% "pending" -> %>
        <span class="badge badge-outline badge-sm text-warning border-warning/50">Pending</span>
      <% _ -> %>
        <span class="badge badge-outline badge-ghost badge-sm">{@status || "-"}</span>
    <% end %>
    """
  end

end
