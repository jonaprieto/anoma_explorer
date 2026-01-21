defmodule AnomaExplorerWeb.AnalyticsLive do
  @moduledoc """
  LiveView for displaying analytics dashboard.

  Shows activity statistics, charts, and trends.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorer.Analytics
  alias AnomaExplorer.Config

  @default_days 30

  @impl true
  def mount(_params, _session, socket) do
    days = @default_days

    socket =
      socket
      |> assign(:page_title, "Analytics")
      |> assign(:days, days)
      |> assign(:selected_network, nil)
      |> load_analytics()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    days = parse_days(params["days"])
    network = params["network"]

    socket =
      socket
      |> assign(:days, days)
      |> assign(:selected_network, network)
      |> load_analytics()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_days", %{"days" => days}, socket) do
    params = build_params(days, socket.assigns.selected_network)
    {:noreply, push_patch(socket, to: ~p"/analytics?#{params}")}
  end

  @impl true
  def handle_event("change_network", %{"network" => network}, socket) do
    network = if network == "", do: nil, else: network
    params = build_params(socket.assigns.days, network)
    {:noreply, push_patch(socket, to: ~p"/analytics?#{params}")}
  end

  defp load_analytics(socket) do
    days = socket.assigns.days
    network = socket.assigns.selected_network

    opts =
      [days: days]
      |> maybe_add_network(network)

    socket
    |> assign(:summary, Analytics.summary_stats(opts))
    |> assign(:daily_counts, Analytics.daily_counts(opts))
    |> assign(:by_kind, Analytics.activity_by_kind(opts))
    |> assign(:by_network, Analytics.activity_by_network(days: days))
    |> assign(:networks, Config.supported_networks())
  end

  defp maybe_add_network(opts, nil), do: opts
  defp maybe_add_network(opts, network), do: Keyword.put(opts, :network, network)

  defp parse_days(nil), do: @default_days

  defp parse_days(days) when is_binary(days) do
    case Integer.parse(days) do
      {n, _} when n > 0 and n <= 365 -> n
      _ -> @default_days
    end
  end

  defp build_params(days, network) do
    []
    |> then(fn p -> if days != @default_days, do: [{"days", days} | p], else: p end)
    |> then(fn p -> if network, do: [{"network", network} | p], else: p end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-3xl font-bold">Analytics Dashboard</h1>

        <div class="flex gap-4">
          <form phx-change="change_network">
            <select name="network" class="rounded border-gray-300 text-sm">
              <option value="">All Networks</option>
              <%= for network <- @networks do %>
                <option value={network} selected={@selected_network == network}>
                  {network}
                </option>
              <% end %>
            </select>
          </form>

          <form phx-change="change_days">
            <select name="days" class="rounded border-gray-300 text-sm">
              <option value="7" selected={@days == 7}>Last 7 days</option>
              <option value="14" selected={@days == 14}>Last 14 days</option>
              <option value="30" selected={@days == 30}>Last 30 days</option>
              <option value="90" selected={@days == 90}>Last 90 days</option>
            </select>
          </form>
        </div>
      </div>
      
    <!-- Summary Stats Cards -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
        <.stat_card title="Total Activities" value={@summary.total_count} />
        <.stat_card title="Active Networks" value={@summary.networks_active} />
        <.stat_card title="Activity Types" value={@summary.kinds_used} />
        <.stat_card title="Avg per Day" value={Float.round(@summary.avg_per_day, 1)} />
      </div>
      
    <!-- Charts Section -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
        <!-- Daily Activity Chart -->
        <div class="bg-white rounded-lg shadow p-4">
          <h2 class="text-lg font-semibold mb-4">Daily Activity</h2>
          <.bar_chart data={@daily_counts} />
        </div>
        
    <!-- Activity by Kind -->
        <div class="bg-white rounded-lg shadow p-4">
          <h2 class="text-lg font-semibold mb-4">Activity by Type</h2>
          <.horizontal_bar_chart data={@by_kind} />
        </div>
      </div>
      
    <!-- Network Distribution -->
      <div class="bg-white rounded-lg shadow p-4">
        <h2 class="text-lg font-semibold mb-4">Activity by Network</h2>
        <.horizontal_bar_chart data={@by_network} />
      </div>
    </div>
    """
  end

  # Component for stat cards
  defp stat_card(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow p-4">
      <p class="text-sm text-gray-500">{@title}</p>
      <p class="text-2xl font-bold">{@value}</p>
    </div>
    """
  end

  # Simple text-based bar chart (CSS-based for simplicity)
  defp bar_chart(assigns) do
    max_count = assigns.data |> Enum.map(& &1.count) |> Enum.max(fn -> 1 end)
    assigns = assign(assigns, :max_count, max_count)

    ~H"""
    <div class="space-y-1">
      <%= if Enum.empty?(@data) do %>
        <p class="text-gray-400 text-sm">No data available</p>
      <% else %>
        <%= for item <- @data do %>
          <div class="flex items-center gap-2 text-xs">
            <span class="w-16 text-gray-500 text-right">{format_date(item.date)}</span>
            <div class="flex-1 bg-gray-100 rounded h-4">
              <div
                class="bg-blue-500 h-4 rounded"
                style={"width: #{bar_width(item.count, @max_count)}%"}
              >
              </div>
            </div>
            <span class="w-8 text-right">{item.count}</span>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Horizontal bar chart for categorical data
  defp horizontal_bar_chart(assigns) do
    data = Map.to_list(assigns.data) |> Enum.sort_by(fn {_, v} -> -v end)
    max_count = data |> Enum.map(fn {_, v} -> v end) |> Enum.max(fn -> 1 end)
    assigns = assign(assigns, data: data, max_count: max_count)

    ~H"""
    <div class="space-y-2">
      <%= if Enum.empty?(@data) do %>
        <p class="text-gray-400 text-sm">No data available</p>
      <% else %>
        <%= for {label, count} <- @data do %>
          <div class="flex items-center gap-2">
            <span class="w-32 text-sm font-medium truncate">{label}</span>
            <div class="flex-1 bg-gray-100 rounded h-6">
              <div
                class="bg-green-500 h-6 rounded flex items-center justify-end pr-2"
                style={"width: #{bar_width(count, @max_count)}%"}
              >
                <span class="text-xs text-white font-medium">{count}</span>
              </div>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp format_date(date) do
    Calendar.strftime(date, "%m/%d")
  end

  defp bar_width(count, max) when max > 0, do: count / max * 100
  defp bar_width(_, _), do: 0
end
