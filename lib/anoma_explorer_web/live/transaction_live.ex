defmodule AnomaExplorerWeb.TransactionLive do
  @moduledoc """
  LiveView for displaying a single transaction's details.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Networks
  alias AnomaExplorer.Utils.Formatting

  alias AnomaExplorerWeb.Layouts

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
         |> assign(
           :page_title,
           "Transaction #{Formatting.truncate_hash(transaction["evmTransaction"]["txHash"])}"
         )}

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
              {if @transaction,
                do: Formatting.truncate_hash(@transaction["evmTransaction"]["txHash"]),
                else: "Loading..."}
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
    <.loading_blocks message="Loading transaction details..." class="py-12" />
    """
  end

  defp transaction_header(assigns) do
    evm_tx = assigns.tx["evmTransaction"]

    assigns =
      assign(
        assigns,
        :block_url,
        Networks.block_url(evm_tx["chainId"], evm_tx["blockNumber"])
      )

    assigns =
      assign(assigns, :tx_url, Networks.tx_url(evm_tx["chainId"], evm_tx["txHash"]))

    assigns =
      assign(
        assigns,
        :contract_url,
        Networks.address_url(evm_tx["chainId"], assigns.tx["contractAddress"])
      )

    assigns =
      assign(
        assigns,
        :from_url,
        if(evm_tx["from"], do: Networks.address_url(evm_tx["chainId"], evm_tx["from"]))
      )

    assigns = assign(assigns, :evm_tx, evm_tx)

    ~H"""
    <div class="stat-card mb-6">
      <h2 class="text-lg font-semibold mb-4">Overview</h2>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="md:col-span-2">
          <div
            class="text-xs text-base-content/60 uppercase tracking-wide mb-1"
            title="Unique identifier of this EVM transaction on the blockchain"
          >
            Transaction Hash
          </div>
          <div class="flex items-center gap-2">
            <code class="hash-display text-sm break-all">{@evm_tx["txHash"]}</code>
            <.copy_button text={@evm_tx["txHash"]} tooltip="Copy tx hash" />
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
          <div
            class="text-xs text-base-content/60 uppercase tracking-wide mb-1"
            title="When this transaction was included in a block"
          >
            Timestamp
          </div>
          <div class="font-mono">{Formatting.format_timestamp_full(@evm_tx["timestamp"])}</div>
        </div>
        <div>
          <div
            class="text-xs text-base-content/60 uppercase tracking-wide mb-1"
            title="Blockchain network where this transaction was recorded"
          >
            Network
          </div>
          <div>
            <.network_button chain_id={@evm_tx["chainId"]} />
          </div>
        </div>
        <div>
          <div
            class="text-xs text-base-content/60 uppercase tracking-wide mb-1"
            title="Block number where this transaction was included"
          >
            Block Number
          </div>
          <div class="flex items-center gap-2">
            <%= if @block_url do %>
              <a href={@block_url} target="_blank" class="font-mono hover:text-primary">
                {@evm_tx["blockNumber"]}
                <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3 inline ml-1" />
              </a>
            <% else %>
              <span class="font-mono">{@evm_tx["blockNumber"]}</span>
            <% end %>
            <.copy_button text={to_string(@evm_tx["blockNumber"])} tooltip="Copy block number" />
          </div>
        </div>
        <div>
          <div
            class="text-xs text-base-content/60 uppercase tracking-wide mb-1"
            title="Account address that sent and signed this transaction"
          >
            From
          </div>
          <div class="flex items-center gap-2">
            <%= if @evm_tx["from"] do %>
              <code class="hash-display text-sm break-all">{@evm_tx["from"]}</code>
              <.copy_button text={@evm_tx["from"]} tooltip="Copy address" />
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
        <%= if @tx["contractAddress"] do %>
          <div>
            <div
              class="text-xs text-base-content/60 uppercase tracking-wide mb-1"
              title="Anoma resource machine contract that processed this transaction"
            >
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
      <h2
        class="text-lg font-semibold mb-4"
        title="All resource identifiers and their logic references in this transaction"
      >
        Resource IDs & Logic Refs <span class="badge badge-ghost ml-2">{length(@tags || [])}</span>
      </h2>
      <%= if (@tags || []) == [] do %>
        <div class="text-base-content/50 text-center py-4">No resource IDs</div>
      <% else %>
        <%!-- Mobile card layout --%>
        <div class="space-y-3 lg:hidden">
          <%= for {tag, idx} <- Enum.with_index(@tags || []) do %>
            <% is_consumed = rem(idx, 2) == 0 %>
            <% logic_ref = Enum.at(@logic_refs || [], idx) %>
            <div class="p-3 rounded-lg bg-base-200/50 hover:bg-base-200 transition-colors">
              <div class="flex flex-col gap-1">
                <div class="flex items-start gap-1">
                  <code class="font-mono text-sm break-all">{tag}</code>
                  <.copy_button :if={tag} text={tag} tooltip="Copy resource ID" class="shrink-0" />
                </div>
                <div class="flex items-center gap-1 text-xs text-base-content/50">
                  <span class="font-mono break-all">{logic_ref}</span>
                  <.copy_button
                    :if={logic_ref}
                    text={logic_ref}
                    tooltip="Copy logic ref"
                    class="shrink-0"
                  />
                </div>
                <div class="flex items-center gap-1.5">
                  <span class="badge badge-ghost badge-xs">{idx}</span>
                  <%= if is_consumed do %>
                    <span class="badge badge-outline badge-xs text-error border-error/50">
                      Nullifier
                    </span>
                  <% else %>
                    <span class="badge badge-outline badge-xs text-success border-success/50">
                      Commitment
                    </span>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Desktop table layout --%>
        <div class="hidden lg:block overflow-x-auto">
          <table class="data-table w-full">
            <thead>
              <tr>
                <th title="Position in the array (even = nullifier, odd = commitment)">Index</th>
                <th title="Resource identifier - nullifier hash or commitment hash">Resource ID</th>
                <th title="Determined by index parity: even = Nullifier, odd = Commitment">Type</th>
              </tr>
            </thead>
            <tbody>
              <%= for {tag, idx} <- Enum.with_index(@tags || []) do %>
                <% is_consumed = rem(idx, 2) == 0 %>
                <% logic_ref = Enum.at(@logic_refs || [], idx) %>
                <tr class="hover:bg-base-200/50">
                  <td>
                    <span class="badge badge-ghost badge-sm">{idx}</span>
                  </td>
                  <td>
                    <div class="flex flex-col gap-0.5">
                      <div class="flex items-center gap-1">
                        <code class="font-mono text-sm break-all">{tag}</code>
                        <.copy_button :if={tag} text={tag} tooltip="Copy resource ID" />
                      </div>
                      <div class="flex items-center gap-1 text-xs text-base-content/50">
                        <span>logic:</span>
                        <code class="font-mono break-all">{logic_ref}</code>
                        <.copy_button :if={logic_ref} text={logic_ref} tooltip="Copy logic ref" />
                      </div>
                    </div>
                  </td>
                  <td>
                    <%= if is_consumed do %>
                      <span
                        class="badge badge-outline badge-sm text-error border-error/50"
                        title="Nullifier - resource consumed as input"
                      >
                        Nullifier
                      </span>
                    <% else %>
                      <span
                        class="badge badge-outline badge-sm text-success border-success/50"
                        title="Commitment - new resource created as output"
                      >
                        Commitment
                      </span>
                    <% end %>
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
      <h2
        class="text-lg font-semibold mb-4"
        title="Resources consumed and created in this transaction"
      >
        Resources <span class="badge badge-ghost ml-2">{length(@resources)}</span>
      </h2>
      <%= if @resources == [] do %>
        <div class="text-base-content/50 text-center py-4">No resources</div>
      <% else %>
        <%!-- Mobile card layout --%>
        <div class="space-y-3 lg:hidden">
          <%= for resource <- @resources do %>
            <div class="p-3 rounded-lg bg-base-200/50 hover:bg-base-200 transition-colors">
              <div class="flex flex-col gap-1">
                <div class="flex items-start gap-1">
                  <a
                    href={"/resources/#{resource["id"]}"}
                    class="font-mono text-sm hover:text-primary break-all"
                  >
                    {resource["tag"]}
                  </a>
                  <.copy_button
                    :if={resource["tag"]}
                    text={resource["tag"]}
                    tooltip="Copy resource ID"
                    class="shrink-0"
                  />
                </div>
                <div class="flex items-center gap-1 text-xs text-base-content/50">
                  <span class="font-mono break-all">{resource["logicRef"]}</span>
                  <.copy_button
                    :if={resource["logicRef"]}
                    text={resource["logicRef"]}
                    tooltip="Copy logic ref"
                    class="shrink-0"
                  />
                </div>
                <div class="flex items-center">
                  <%= if resource["isConsumed"] do %>
                    <span class="badge badge-outline badge-xs text-error border-error/50">
                      Nullifier
                    </span>
                  <% else %>
                    <span class="badge badge-outline badge-xs text-success border-success/50">
                      Commitment
                    </span>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Desktop table layout --%>
        <div class="hidden lg:block overflow-x-auto">
          <table class="data-table w-full">
            <thead>
              <tr>
                <th title="Unique identifier - nullifier hash (if consumed) or commitment hash (if created)">
                  Resource ID
                </th>
                <th title="Resource type: Nullifier (consumed input) or Commitment (created output)">
                  Type
                </th>
              </tr>
            </thead>
            <tbody>
              <%= for resource <- @resources do %>
                <tr class="hover:bg-base-200/50">
                  <td>
                    <div class="flex flex-col gap-0.5">
                      <div class="flex items-center gap-1">
                        <a
                          href={"/resources/#{resource["id"]}"}
                          class="font-mono text-sm hover:text-primary break-all"
                        >
                          {resource["tag"]}
                        </a>
                        <.copy_button
                          :if={resource["tag"]}
                          text={resource["tag"]}
                          tooltip="Copy resource ID"
                        />
                      </div>
                      <div class="flex items-center gap-1 text-xs text-base-content/50">
                        <span>logic:</span>
                        <code class="font-mono break-all">{resource["logicRef"]}</code>
                        <.copy_button
                          :if={resource["logicRef"]}
                          text={resource["logicRef"]}
                          tooltip="Copy logic ref"
                        />
                      </div>
                    </div>
                  </td>
                  <td>
                    <%= if resource["isConsumed"] do %>
                      <span
                        class="badge badge-outline badge-sm text-error border-error/50"
                        title="Nullifier - resource consumed as input"
                      >
                        Nullifier
                      </span>
                    <% else %>
                      <span
                        class="badge badge-outline badge-sm text-success border-success/50"
                        title="Commitment - new resource created as output"
                      >
                        Commitment
                      </span>
                    <% end %>
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
      <h2
        class="text-lg font-semibold mb-4"
        title="Atomic units of computation in this transaction, each containing compliance units and logic inputs"
      >
        Actions <span class="badge badge-ghost ml-2">{length(@actions)}</span>
      </h2>
      <%= if @actions == [] do %>
        <div class="text-base-content/50 text-center py-4">No actions</div>
      <% else %>
        <div class="overflow-x-auto">
          <table class="data-table w-full">
            <thead>
              <tr>
                <th title="Merkle root uniquely identifying the action and all its contents">
                  Action Tree Root
                </th>
                <th title="Total number of resource tags (nullifiers + commitments)">Tag Count</th>
              </tr>
            </thead>
            <tbody>
              <%= for action <- @actions do %>
                <tr>
                  <td>
                    <div class="flex items-start gap-1">
                      <a
                        href={"/actions/#{action["id"]}"}
                        class="hash-display text-xs hover:text-primary break-all"
                      >
                        {action["actionTreeRoot"]}
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
end
