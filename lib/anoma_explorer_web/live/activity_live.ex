defmodule AnomaExplorerWeb.ActivityLive do
  @moduledoc """
  LiveView for displaying contract activity feed with realtime updates.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorer.Activity
  alias AnomaExplorer.Config

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) do
      # Subscribe to all activity topics
      subscribe_to_activities()
    end

    filters = parse_filters(params)

    socket =
      socket
      |> assign(:page_title, "Activity Feed")
      |> assign(:filters, filters)
      |> assign(:networks, ["all" | Config.supported_networks()])
      |> assign(:kinds, ["all", "tx", "log", "transfer"])
      |> stream(:activities, list_activities(filters), at: 0)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)

    socket =
      socket
      |> assign(:filters, filters)
      |> stream(:activities, list_activities(filters), reset: true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter_params}, socket) do
    filters = %{
      network: normalize_filter(filter_params["network"]),
      kind: normalize_filter(filter_params["kind"])
    }

    params = build_query_params(filters)
    {:noreply, push_patch(socket, to: ~p"/activity?#{params}")}
  end

  @impl true
  def handle_event("load_more", %{"cursor" => cursor_id}, socket) do
    cursor_id = String.to_integer(cursor_id)
    filters = socket.assigns.filters

    more_activities = list_activities(filters, after_id: cursor_id)

    socket = stream(socket, :activities, more_activities, at: -1)
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/activity")}
  end

  @impl true
  def handle_info({:new_activity, activity}, socket) do
    # Only show if it matches current filters
    if matches_filters?(activity, socket.assigns.filters) do
      {:noreply, stream_insert(socket, :activities, activity, at: 0)}
    else
      {:noreply, socket}
    end
  end

  # Private helpers

  defp subscribe_to_activities do
    # Subscribe to all networks
    for network <- Config.supported_networks() do
      # We subscribe to a wildcard topic for now
      # In production, you'd subscribe to specific contract addresses
      Phoenix.PubSub.subscribe(AnomaExplorer.PubSub, "contract:#{network}:*")
    end

    # Also subscribe to a general topic
    Phoenix.PubSub.subscribe(AnomaExplorer.PubSub, "activities:new")
  end

  defp parse_filters(params) do
    %{
      network: normalize_filter(params["network"]),
      kind: normalize_filter(params["kind"])
    }
  end

  defp normalize_filter(nil), do: nil
  defp normalize_filter(""), do: nil
  defp normalize_filter("all"), do: nil
  defp normalize_filter(value), do: value

  defp list_activities(filters, opts \\ []) do
    opts =
      opts
      |> maybe_add_filter(:network, filters.network)
      |> maybe_add_filter(:kind, filters.kind)
      |> Keyword.put_new(:limit, 50)

    Activity.list_activities(opts)
  end

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, key, value), do: Keyword.put(opts, key, value)

  defp matches_filters?(activity, filters) do
    matches_network?(activity, filters.network) and
      matches_kind?(activity, filters.kind)
  end

  defp matches_network?(_activity, nil), do: true
  defp matches_network?(activity, network), do: activity.network == network

  defp matches_kind?(_activity, nil), do: true
  defp matches_kind?(activity, kind), do: activity.kind == kind

  defp build_query_params(filters) do
    filters
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-6">Activity Feed</h1>
      
    <!-- Filters -->
      <div class="bg-base-200 rounded-lg p-4 mb-6">
        <form phx-change="filter" class="flex flex-wrap gap-4 items-end">
          <div class="form-control">
            <label class="label">
              <span class="label-text">Network</span>
            </label>
            <select name="filter[network]" class="select select-bordered">
              <%= for network <- @networks do %>
                <option
                  value={network}
                  selected={
                    @filters.network == network || (@filters.network == nil && network == "all")
                  }
                >
                  {network}
                </option>
              <% end %>
            </select>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text">Type</span>
            </label>
            <select name="filter[kind]" class="select select-bordered">
              <%= for kind <- @kinds do %>
                <option
                  value={kind}
                  selected={@filters.kind == kind || (@filters.kind == nil && kind == "all")}
                >
                  {kind}
                </option>
              <% end %>
            </select>
          </div>

          <div class="form-control">
            <a href="#" phx-click="clear_filters" class="btn btn-ghost">Clear filters</a>
          </div>
        </form>
      </div>
      
    <!-- Activity List -->
      <div class="overflow-x-auto">
        <table class="table table-zebra w-full">
          <thead>
            <tr>
              <th>Block</th>
              <th>Network</th>
              <th>Type</th>
              <th>Transaction Hash</th>
              <th>Time</th>
            </tr>
          </thead>
          <tbody id="activities" phx-update="stream">
            <%= for {id, activity} <- @streams.activities do %>
              <tr id={id}>
                <td class="font-mono">{activity.block_number}</td>
                <td>
                  <span class="badge badge-primary badge-sm">{activity.network}</span>
                </td>
                <td>
                  <span class={["badge badge-sm", kind_badge_class(activity.kind)]}>
                    {activity.kind}
                  </span>
                </td>
                <td class="font-mono text-sm">
                  <span title={activity.tx_hash}>{truncate_hash(activity.tx_hash)}</span>
                </td>
                <td class="text-sm text-gray-500">
                  {format_time(activity.inserted_at)}
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
      
    <!-- Load More -->
      <div class="mt-4 text-center">
        <%= if has_more?(@streams.activities) do %>
          <button
            phx-click="load_more"
            phx-value-cursor={last_id(@streams.activities)}
            class="btn btn-outline"
          >
            Load More
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp kind_badge_class("tx"), do: "badge-info"
  defp kind_badge_class("log"), do: "badge-success"
  defp kind_badge_class("transfer"), do: "badge-warning"
  defp kind_badge_class(_), do: "badge-ghost"

  defp truncate_hash(nil), do: "-"

  defp truncate_hash(hash) when byte_size(hash) > 16 do
    String.slice(hash, 0, 10) <> "..." <> String.slice(hash, -6, 6)
  end

  defp truncate_hash(hash), do: hash

  defp format_time(nil), do: "-"

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  defp has_more?(stream) do
    # Simple heuristic: if we got 50 items, there might be more
    Enum.count(stream) >= 50
  end

  defp last_id(stream) do
    case Enum.at(stream, -1) do
      {_id, activity} -> activity.id
      nil -> nil
    end
  end
end
