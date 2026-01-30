defmodule AnomaExplorerWeb.PlaygroundLive do
  @moduledoc """
  LiveView for a GraphQL playground to execute ad-hoc queries.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorerWeb.Layouts
  alias AnomaExplorer.Indexer.GraphQL
  alias AnomaExplorer.Indexer.Client
  alias AnomaExplorerWeb.IndexerSetupComponents
  alias AnomaExplorerWeb.Live.Helpers.SetupHandlers

  @default_query """
  query {
    Transaction(limit: 10, order_by: {evmTransaction: {blockNumber: desc}}) {
      id
      tags
      logicRefs
      evmTransaction {
        txHash
        blockNumber
        timestamp
        chainId
      }
    }
  }
  """

  @query_templates %{
    "list_transactions" => """
    query {
      Transaction(limit: 10, order_by: {evmTransaction: {blockNumber: desc}}) {
        id
        tags
        logicRefs
        evmTransaction {
          txHash
          blockNumber
          timestamp
          chainId
        }
      }
    }
    """,
    "list_resources" => """
    query {
      Resource(limit: 10, order_by: {blockNumber: desc}) {
        id
        tag
        isConsumed
        blockNumber
        chainId
        logicRef
        decodingStatus
      }
    }
    """,
    "consumed_resources" => """
    query {
      Resource(limit: 10, where: {isConsumed: {_eq: true}}, order_by: {blockNumber: desc}) {
        id
        tag
        blockNumber
        logicRef
        transaction {
          id
          evmTransaction {
            txHash
          }
        }
      }
    }
    """,
    "created_resources" => """
    query {
      Resource(limit: 10, where: {isConsumed: {_eq: false}}, order_by: {blockNumber: desc}) {
        id
        tag
        blockNumber
        logicRef
        transaction {
          id
          evmTransaction {
            txHash
          }
        }
      }
    }
    """,
    "failed_decoding" => """
    query {
      Resource(limit: 10, where: {decodingStatus: {_eq: "failed"}}) {
        id
        tag
        decodingStatus
        decodingError
        blockNumber
      }
    }
    """,
    "list_actions" => """
    query {
      Action(limit: 10, order_by: {blockNumber: desc}) {
        id
        actionTreeRoot
        tagCount
        blockNumber
        timestamp
        transaction {
          id
          evmTransaction {
            txHash
          }
        }
      }
    }
    """,
    "commitment_roots" => """
    query {
      CommitmentTreeRoot(limit: 10, order_by: {blockNumber: desc}) {
        id
        root
        blockNumber
        timestamp
      }
    }
    """
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "GraphQL Playground")
     |> assign(:query, @default_query)
     |> assign(:result, nil)
     |> assign(:error, nil)
     |> assign(:loading, false)
     |> assign(:configured, Client.configured?())
     |> assign(:connection_status, nil)
     |> assign(:templates, @query_templates)
     |> SetupHandlers.init_setup_assigns()}
  end

  @impl true
  def handle_event("retry_connection", _params, socket) do
    {:noreply, assign(socket, :configured, Client.configured?())}
  end

  @impl true
  def handle_event("setup_update_url", %{"url" => url}, socket) do
    {:noreply, SetupHandlers.handle_update_url(socket, url)}
  end

  @impl true
  def handle_event("setup_save_url", %{"url" => url}, socket) do
    case SetupHandlers.handle_save_url(socket, url) do
      {:ok, socket} ->
        {:noreply, assign(socket, :configured, true)}
      {:error, socket} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("execute", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:query, query)
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:result, nil)

    send(self(), {:execute_query, query})
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_template", %{"template" => template_key}, socket) do
    query = Map.get(@query_templates, template_key, @default_query)
    {:noreply, assign(socket, :query, query)}
  end

  @impl true
  def handle_event("clear", _params, socket) do
    {:noreply,
     socket
     |> assign(:query, @default_query)
     |> assign(:result, nil)
     |> assign(:error, nil)}
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
  def handle_info({:setup_auto_test_connection, url}, socket) do
    {:noreply, SetupHandlers.handle_auto_test(socket, url)}
  end

  @impl true
  def handle_info({:execute_query, query}, socket) do
    socket =
      case GraphQL.execute_raw(query) do
        {:ok, result} ->
          socket
          |> assign(:result, Jason.encode!(result, pretty: true))
          |> assign(:loading, false)

        {:error, :not_configured} ->
          socket
          |> assign(:error, "Indexer endpoint not configured")
          |> assign(:loading, false)

        {:error, {:http_error, status, body}} ->
          socket
          |> assign(:error, "HTTP error #{status}: #{String.slice(body, 0, 200)}")
          |> assign(:loading, false)

        {:error, {:decode_error, reason}} ->
          socket
          |> assign(:error, "Failed to decode response: #{inspect(reason)}")
          |> assign(:loading, false)

        {:error, {:connection_error, reason}} ->
          socket
          |> assign(:error, "Connection error: #{inspect(reason)}")
          |> assign(:loading, false)

        {:error, reason} ->
          socket
          |> assign(:error, "Error: #{inspect(reason)}")
          |> assign(:loading, false)
      end

    {:noreply, socket}
  end

  # Block explorer URLs by chain ID
  @block_explorers %{
    1 => "https://etherscan.io",
    8453 => "https://basescan.org",
    84_532 => "https://sepolia.basescan.org",
    11_155_111 => "https://sepolia.etherscan.io",
    42_161 => "https://arbiscan.io",
    421_614 => "https://sepolia.arbiscan.io",
    10 => "https://optimistic.etherscan.io",
    11_155_420 => "https://sepolia-optimism.etherscan.io"
  }

  # JSON rendering with linkable fields
  defp render_json_with_links(json_string) do
    case Jason.decode(json_string) do
      {:ok, data} -> render_value(data, nil, 0)
      {:error, _} -> Phoenix.HTML.raw(json_string)
    end
  end

  defp render_value(value, context, indent) when is_map(value) do
    indent_str = String.duplicate("  ", indent)
    inner_indent = String.duplicate("  ", indent + 1)

    # Extract chainId from this object if present for context
    chain_id = Map.get(value, "chainId", context)

    entries =
      value
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn {k, v} ->
        [
          Phoenix.HTML.raw(inner_indent),
          render_key(k),
          Phoenix.HTML.raw(": "),
          render_field_value(k, v, chain_id, indent + 1)
        ]
      end)
      |> Enum.intersperse(Phoenix.HTML.raw(",\n"))

    [
      Phoenix.HTML.raw("{\n"),
      entries,
      Phoenix.HTML.raw("\n#{indent_str}}")
    ]
  end

  defp render_value(value, context, indent) when is_list(value) do
    if Enum.empty?(value) do
      Phoenix.HTML.raw("[]")
    else
      indent_str = String.duplicate("  ", indent)
      inner_indent = String.duplicate("  ", indent + 1)

      entries =
        value
        |> Enum.map(fn v ->
          [
            Phoenix.HTML.raw(inner_indent),
            render_value(v, context, indent + 1)
          ]
        end)
        |> Enum.intersperse(Phoenix.HTML.raw(",\n"))

      [
        Phoenix.HTML.raw("[\n"),
        entries,
        Phoenix.HTML.raw("\n#{indent_str}]")
      ]
    end
  end

  defp render_value(value, _context, _indent) when is_binary(value) do
    escaped = Phoenix.HTML.html_escape(value)

    [
      Phoenix.HTML.raw(~s(<span class="hljs-string">)),
      "\"",
      escaped,
      "\"",
      Phoenix.HTML.raw("</span>")
    ]
  end

  defp render_value(value, _context, _indent) when is_number(value) do
    [
      Phoenix.HTML.raw(~s(<span class="hljs-number">)),
      to_string(value),
      Phoenix.HTML.raw("</span>")
    ]
  end

  defp render_value(value, _context, _indent) when is_boolean(value) do
    [
      Phoenix.HTML.raw(~s(<span class="hljs-literal">)),
      to_string(value),
      Phoenix.HTML.raw("</span>")
    ]
  end

  defp render_value(nil, _context, _indent) do
    Phoenix.HTML.raw(~s(<span class="hljs-literal">null</span>))
  end

  defp render_key(key) do
    escaped = Phoenix.HTML.html_escape(key)

    [
      Phoenix.HTML.raw(~s(<span class="hljs-attr">)),
      "\"",
      escaped,
      "\"",
      Phoenix.HTML.raw("</span>")
    ]
  end

  # Render field values with potential links
  defp render_field_value("id", value, _chain_id, _indent) when is_binary(value) do
    link = get_id_link(value)
    render_linked_string(value, link)
  end

  defp render_field_value("txHash", value, chain_id, _indent)
       when is_binary(value) and not is_nil(chain_id) do
    link = "/transactions/#{chain_id}_#{value}"
    render_linked_string(value, link)
  end

  defp render_field_value("logicRef", value, _chain_id, indent) when is_binary(value) do
    # logicRef alone isn't enough to form a valid logic URL (needs txHash + actionTreeRoot + index)
    # So we just render it as a plain string
    render_value(value, nil, indent)
  end

  defp render_field_value("blockNumber", value, chain_id, _indent)
       when is_integer(value) and not is_nil(chain_id) do
    case Map.get(@block_explorers, chain_id) do
      nil ->
        [
          Phoenix.HTML.raw(~s(<span class="hljs-number">)),
          to_string(value),
          Phoenix.HTML.raw("</span>")
        ]

      explorer_url ->
        link = "#{explorer_url}/block/#{value}"

        [
          Phoenix.HTML.raw(
            ~s(<a href="#{link}" target="_blank" rel="noopener" class="hljs-number underline hover:text-primary">)
          ),
          to_string(value),
          Phoenix.HTML.raw("</a>")
        ]
    end
  end

  defp render_field_value(_key, value, context, indent) do
    render_value(value, context, indent)
  end

  defp get_id_link(id) do
    cond do
      String.ends_with?(id, "_resource") -> "/resources/#{id}"
      String.ends_with?(id, "_transaction") -> "/transactions/#{id}"
      String.ends_with?(id, "_action") -> "/actions/#{id}"
      String.ends_with?(id, "_compliance") -> "/compliances/#{id}"
      String.ends_with?(id, "_logic") -> "/logics/#{id}"
      true -> nil
    end
  end

  defp render_linked_string(value, nil) do
    escaped = Phoenix.HTML.html_escape(value)

    [
      Phoenix.HTML.raw(~s(<span class="hljs-string">)),
      "\"",
      escaped,
      "\"",
      Phoenix.HTML.raw("</span>")
    ]
  end

  defp render_linked_string(value, link) do
    escaped = Phoenix.HTML.html_escape(value)

    [
      Phoenix.HTML.raw(
        ~s(<span class="hljs-string">"<a href="#{link}" class="underline hover:text-primary">)
      ),
      escaped,
      Phoenix.HTML.raw("</a>\"</span>")
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/playground">
      <div class="page-header">
        <div>
          <h1 class="page-title">GraphQL Playground</h1>
          <p class="text-sm text-base-content/70 mt-1">
            Execute GraphQL queries against the
            <a
              href="https://docs.envio.dev/docs/HyperIndex/overview"
              target="_blank"
              rel="noopener noreferrer"
              class="link link-primary"
            >
              Envio HyperIndexer
            </a>
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
            url={@setup_url_input}
          />
        <% true -> %>
          <.action_bar templates={@templates} loading={@loading} />
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <.query_editor query={@query} />
            <.results_panel result={@result} error={@error} loading={@loading} />
          </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp action_bar(assigns) do
    ~H"""
    <div class="stat-card mb-6">
      <div class="flex items-center justify-between flex-wrap gap-4">
        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2">
            <.icon name="hero-document-duplicate" class="w-4 h-4 text-base-content/50" />
            <span class="text-sm font-medium text-base-content/70">Template:</span>
          </div>
          <form phx-change="select_template">
            <select
              name="template"
              class="select select-bordered select-sm min-w-[200px] bg-base-100 focus:border-primary"
            >
              <option value="">Custom query</option>
              <option value="list_transactions">List Transactions</option>
              <option value="list_resources">List Resources</option>
              <option value="consumed_resources">Consumed Resources</option>
              <option value="created_resources">Created Resources</option>
              <option value="failed_decoding">Failed Decoding</option>
              <option value="list_actions">List Actions</option>
              <option value="commitment_roots">Commitment Roots</option>
            </select>
          </form>
        </div>
        <form phx-submit="execute" id="query-form" class="flex items-center gap-3">
          <kbd class="hidden sm:inline-flex items-center gap-1 px-2 py-1 text-xs font-medium text-base-content/50 bg-base-200 rounded-md border border-base-content/10">
            <span class="text-[10px]">Ctrl</span>+<span class="text-[10px]">↵</span>
          </kbd>
          <button type="button" phx-click="clear" class="btn btn-ghost btn-sm gap-1">
            <.icon name="hero-arrow-path" class="w-4 h-4" /> Reset
          </button>
          <button type="submit" class="btn btn-primary btn-sm gap-2 shadow-sm" disabled={@loading}>
            <%= if @loading do %>
              <span class="loading loading-spinner loading-xs"></span> Running...
            <% else %>
              <.icon name="hero-play" class="w-4 h-4" /> Execute
            <% end %>
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp query_editor(assigns) do
    ~H"""
    <div class="stat-card flex flex-col h-[600px]">
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-2">
          <div class="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
            <.icon name="hero-code-bracket" class="w-4 h-4 text-primary" />
          </div>
          <h2 class="text-lg font-semibold">Query</h2>
        </div>
        <span class="text-xs text-base-content/50 px-2 py-1 bg-base-200 rounded">GraphQL</span>
      </div>

      <div phx-hook="GraphQLEditor" id="query-editor-wrapper" class="flex flex-col flex-1 min-h-0">
        <div class="relative flex-1 min-h-0 rounded-xl overflow-hidden shadow-inner">
          <pre
            class="highlight-layer absolute inset-0 p-4 m-0 overflow-auto pointer-events-none bg-base-100 border border-base-300"
            aria-hidden="true"
          ><code class="language-graphql text-sm !bg-transparent !p-0 leading-relaxed text-base-content"><%= @query %></code></pre>
          <textarea
            name="query"
            form="query-form"
            class="absolute inset-0 w-full h-full font-mono text-sm p-4 resize-none bg-transparent text-transparent caret-base-content border border-base-300 focus:outline-none focus:ring-2 focus:ring-primary/30 leading-relaxed"
            placeholder="Enter your GraphQL query..."
            id="query-editor"
            spellcheck="false"
          ><%= @query %></textarea>
        </div>
      </div>
    </div>
    """
  end

  defp results_panel(assigns) do
    ~H"""
    <div class="stat-card flex flex-col h-[600px]">
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-2">
          <div class="w-8 h-8 rounded-lg bg-success/10 flex items-center justify-center">
            <.icon name="hero-document-text" class="w-4 h-4 text-success" />
          </div>
          <h2 class="text-lg font-semibold">Results</h2>
        </div>
        <%= if @result do %>
          <button
            type="button"
            phx-click={
              JS.dispatch("phx:copy", detail: %{text: @result})
              |> JS.remove_class("opacity-50", to: "#copy-toast")
              |> JS.add_class("opacity-100", to: "#copy-toast")
              |> JS.show(
                to: "#copy-toast",
                transition: {"ease-out duration-200", "opacity-0", "opacity-100"}
              )
              |> JS.hide(
                to: "#copy-toast",
                time: 1500,
                transition: {"ease-in duration-300", "opacity-100", "opacity-0"}
              )
            }
            class="btn btn-ghost btn-sm gap-1"
            title="Copy results"
          >
            <.icon name="hero-clipboard-document" class="w-4 h-4" /> Copy
          </button>
        <% end %>
      </div>

      <div class="flex-1 min-h-0 overflow-hidden rounded-xl shadow-inner">
        <%= if @loading do %>
          <div class="flex items-center justify-center h-full bg-base-100 border border-base-300 rounded-xl">
            <div class="flex flex-col items-center gap-3">
              <span class="loading loading-spinner loading-lg text-primary"></span>
              <span class="text-sm text-base-content/60">Executing query...</span>
            </div>
          </div>
        <% else %>
          <%= if @error do %>
            <div class="bg-error/10 text-error p-4 rounded-xl border border-error/30 h-full overflow-auto">
              <div class="flex items-start gap-3">
                <div class="w-8 h-8 rounded-lg bg-error/20 flex items-center justify-center shrink-0">
                  <.icon name="hero-exclamation-triangle" class="w-4 h-4" />
                </div>
                <div>
                  <p class="font-medium mb-2">Query Error</p>
                  <pre class="text-sm whitespace-pre-wrap font-mono opacity-90"><%= @error %></pre>
                </div>
              </div>
            </div>
          <% else %>
            <%= if @result do %>
              <pre
                id="result-display"
                class="bg-base-100 p-4 text-sm font-mono whitespace-pre h-full overflow-auto border border-base-300 text-base-content leading-relaxed"
              ><%= render_json_with_links(@result) %></pre>
            <% else %>
              <div class="flex flex-col items-center justify-center h-full bg-base-100 border border-base-300 rounded-xl text-base-content/50">
                <div class="w-16 h-16 rounded-2xl bg-base-200 flex items-center justify-center mb-4">
                  <.icon name="hero-command-line" class="w-8 h-8 opacity-50" />
                </div>
                <p class="text-sm font-medium">No results yet</p>
                <p class="text-xs mt-1 opacity-70">Execute a query to see results here</p>
              </div>
            <% end %>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
