defmodule AnomaExplorerWeb.NetworksLive do
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorer.Settings
  alias AnomaExplorer.Settings.Network
  alias AnomaExplorerWeb.AdminAuth
  alias AnomaExplorerWeb.Layouts

  on_mount {AdminAuth, :load_admin_state}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Settings.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Networks")
     |> assign(:networks, list_networks())
     |> assign(:modal, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/settings/networks">
      <div class="page-header">
        <div>
          <h1 class="page-title">Networks</h1>
          <p class="text-sm text-base-content/70 mt-1">
            Configure blockchain networks and RPC endpoints
          </p>
        </div>
        <div class="flex items-center gap-4">
          <.admin_status
            authorized={@admin_authorized}
            authorized_at={@admin_authorized_at}
            timeout_ms={@admin_timeout_ms}
          />
          <.protected_button
            authorized={@admin_authorized}
            phx-click="new_network"
            class="btn btn-primary btn-sm"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Add Network
          </.protected_button>
        </div>
      </div>

      <div class="space-y-4">
        <%= if Enum.empty?(@networks) do %>
          <div class="stat-card text-center py-12">
            <.icon name="hero-globe-alt" class="w-12 h-12 text-base-content/30 mx-auto mb-4" />
            <p class="text-base-content/70">No networks configured yet.</p>
            <.protected_button
              authorized={@admin_authorized}
              phx-click="new_network"
              class="btn btn-primary btn-sm mt-4"
            >
              Add your first network
            </.protected_button>
          </div>
        <% else %>
          <div class="stat-card">
            <div class="overflow-x-auto">
              <table class="data-table w-full">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Display Name</th>
                    <th>Chain ID</th>
                    <th class="hidden xl:table-cell">RPC URL</th>
                    <th>Type</th>
                    <th>Status</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for network <- Enum.sort_by(@networks, & &1.active, :desc) do %>
                    <tr class={unless network.active, do: "opacity-50"}>
                      <td>
                        <span class="font-mono text-sm">{network.name}</span>
                      </td>
                      <td>{network.display_name}</td>
                      <td>
                        <%= if network.chain_id do %>
                          <span class="badge badge-outline badge-sm">{network.chain_id}</span>
                        <% else %>
                          <span class="text-base-content/40">-</span>
                        <% end %>
                      </td>
                      <td class="hidden xl:table-cell">
                        <%= if network.rpc_url do %>
                          <span
                            class="text-sm font-mono text-base-content/70 truncate max-w-[200px] inline-block"
                            title={network.rpc_url}
                          >
                            {truncate_url(network.rpc_url)}
                          </span>
                        <% else %>
                          <span class="text-base-content/40">-</span>
                        <% end %>
                      </td>
                      <td>
                        <%= if network.is_testnet do %>
                          <span class="badge badge-warning badge-sm">Testnet</span>
                        <% else %>
                          <span class="badge badge-info badge-sm">Mainnet</span>
                        <% end %>
                      </td>
                      <td>
                        <%= if network.active do %>
                          <span class="badge badge-success badge-sm">Active</span>
                        <% else %>
                          <span class="badge badge-ghost badge-sm">Inactive</span>
                        <% end %>
                      </td>
                      <td class="text-right">
                        <.protected_button
                          authorized={@admin_authorized}
                          phx-click="edit_network"
                          phx-value-id={network.id}
                          class="btn btn-ghost btn-xs"
                        >
                          <.icon name="hero-pencil" class="w-3 h-3" />
                        </.protected_button>
                        <.protected_button
                          authorized={@admin_authorized}
                          phx-click="delete_network"
                          phx-value-id={network.id}
                          data-confirm="Delete this network?"
                          class="btn btn-ghost btn-xs text-error"
                        >
                          <.icon name="hero-trash" class="w-3 h-3" />
                        </.protected_button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @modal do %>
        <.modal id="network-modal" show on_cancel={JS.push("close_modal")}>
          <.render_modal modal={@modal} form={@form} />
        </.modal>
      <% end %>

      <.unlock_modal show={@admin_show_unlock_modal} error={@admin_error} />
    </Layouts.app>
    """
  end

  defp render_modal(%{modal: :new_network, form: _form} = assigns) do
    ~H"""
    <h3 class="text-lg font-semibold mb-4">New Network</h3>
    <.form for={@form} phx-submit="save_network" class="space-y-4">
      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="label">Name</label>
          <input
            type="text"
            name="network[name]"
            value={@form[:name].value}
            class="input input-bordered w-full font-mono"
            placeholder="e.g., eth-mainnet"
            required
          />
          <p class="text-xs text-base-content/50 mt-1">Lowercase, hyphens allowed</p>
          <.error_tag errors={@form[:name].errors} />
        </div>
        <div>
          <label class="label">Display Name</label>
          <input
            type="text"
            name="network[display_name]"
            value={@form[:display_name].value}
            class="input input-bordered w-full"
            placeholder="e.g., Ethereum Mainnet"
            required
          />
          <.error_tag errors={@form[:display_name].errors} />
        </div>
      </div>
      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="label">Chain ID (optional)</label>
          <input
            type="number"
            name="network[chain_id]"
            value={@form[:chain_id].value}
            class="input input-bordered w-full"
            placeholder="e.g., 1"
          />
        </div>
        <div>
          <label class="label">Explorer URL (optional)</label>
          <input
            type="url"
            name="network[explorer_url]"
            value={@form[:explorer_url].value}
            class="input input-bordered w-full"
            placeholder="e.g., https://etherscan.io/address/"
          />
        </div>
      </div>
      <div>
        <label class="label">RPC URL (optional)</label>
        <input
          type="url"
          name="network[rpc_url]"
          value={@form[:rpc_url].value}
          class="input input-bordered w-full"
          placeholder="e.g., https://mainnet.infura.io/v3/..."
        />
      </div>
      <div class="flex items-center gap-4">
        <div class="flex items-center gap-2">
          <input type="hidden" name="network[is_testnet]" value="false" />
          <input
            type="checkbox"
            name="network[is_testnet]"
            value="true"
            checked={@form[:is_testnet].value}
            class="checkbox checkbox-sm"
          />
          <label class="label">Testnet</label>
        </div>
      </div>
      <div class="flex justify-end gap-2 pt-4">
        <button type="button" phx-click="close_modal" class="btn btn-ghost">Cancel</button>
        <button type="submit" class="btn btn-primary">Create Network</button>
      </div>
    </.form>
    """
  end

  defp render_modal(%{modal: {:edit_network, network}, form: _form} = assigns) do
    assigns = assign(assigns, :network, network)

    ~H"""
    <h3 class="text-lg font-semibold mb-4">Edit Network</h3>
    <.form for={@form} phx-submit="update_network" class="space-y-4">
      <input type="hidden" name="network[id]" value={@network.id} />
      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="label">Name</label>
          <input
            type="text"
            name="network[name]"
            value={@form[:name].value}
            class="input input-bordered w-full font-mono"
            required
          />
          <p class="text-xs text-base-content/50 mt-1">Lowercase, hyphens allowed</p>
          <.error_tag errors={@form[:name].errors} />
        </div>
        <div>
          <label class="label">Display Name</label>
          <input
            type="text"
            name="network[display_name]"
            value={@form[:display_name].value}
            class="input input-bordered w-full"
            required
          />
          <.error_tag errors={@form[:display_name].errors} />
        </div>
      </div>
      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="label">Chain ID (optional)</label>
          <input
            type="number"
            name="network[chain_id]"
            value={@form[:chain_id].value}
            class="input input-bordered w-full"
          />
        </div>
        <div>
          <label class="label">Explorer URL (optional)</label>
          <input
            type="url"
            name="network[explorer_url]"
            value={@form[:explorer_url].value}
            class="input input-bordered w-full"
          />
        </div>
      </div>
      <div>
        <label class="label">RPC URL (optional)</label>
        <input
          type="url"
          name="network[rpc_url]"
          value={@form[:rpc_url].value}
          class="input input-bordered w-full"
        />
      </div>
      <div class="flex items-center gap-4">
        <div class="flex items-center gap-2">
          <input type="hidden" name="network[is_testnet]" value="false" />
          <input
            type="checkbox"
            name="network[is_testnet]"
            value="true"
            checked={@form[:is_testnet].value}
            class="checkbox checkbox-sm"
          />
          <label class="label">Testnet</label>
        </div>
        <div class="flex items-center gap-2">
          <input type="hidden" name="network[active]" value="false" />
          <input
            type="checkbox"
            name="network[active]"
            value="true"
            checked={@form[:active].value}
            class="checkbox checkbox-sm"
          />
          <label class="label">Active</label>
        </div>
      </div>
      <div class="flex justify-end gap-2 pt-4">
        <button type="button" phx-click="close_modal" class="btn btn-ghost">Cancel</button>
        <button type="submit" class="btn btn-primary">Save Changes</button>
      </div>
    </.form>
    """
  end

  defp render_modal(assigns), do: ~H""

  defp error_tag(assigns) do
    ~H"""
    <%= for {msg, _} <- @errors || [] do %>
      <p class="text-error text-sm mt-1">{msg}</p>
    <% end %>
    """
  end

  # Event Handlers

  # Admin authorization events
  @impl true
  def handle_event(event, params, socket)
      when event in ~w(admin_show_unlock_modal admin_close_unlock_modal admin_verify_secret admin_logout) do
    case AdminAuth.handle_event(event, params, socket) do
      {:handled, socket} -> {:noreply, socket}
      :not_handled -> {:noreply, socket}
    end
  end

  def handle_event("new_network", _params, socket) do
    AdminAuth.require_admin(socket, fn ->
      form = to_form(Settings.change_network(%Network{}))
      {:noreply, assign(socket, modal: :new_network, form: form)}
    end)
  end

  def handle_event("edit_network", %{"id" => id}, socket) do
    AdminAuth.require_admin(socket, fn ->
      network = Settings.get_network!(id)
      form = to_form(Settings.change_network(network))
      {:noreply, assign(socket, modal: {:edit_network, network}, form: form)}
    end)
  end

  def handle_event("delete_network", %{"id" => id}, socket) do
    AdminAuth.require_admin(socket, fn ->
      network = Settings.get_network!(id)

      case Settings.delete_network(network) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Network deleted")
           |> assign(:networks, list_networks())}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete network")}
      end
    end)
  end

  def handle_event("save_network", %{"network" => params}, socket) do
    case Settings.create_network(params) do
      {:ok, _network} ->
        {:noreply,
         socket
         |> put_flash(:info, "Network created")
         |> assign(:networks, list_networks())
         |> assign(:modal, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("update_network", %{"network" => params}, socket) do
    {:edit_network, network} = socket.assigns.modal

    case Settings.update_network(network, params) do
      {:ok, _network} ->
        {:noreply,
         socket
         |> put_flash(:info, "Network updated")
         |> assign(:networks, list_networks())
         |> assign(:modal, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil)}
  end

  def handle_event("global_search", %{"query" => query}, socket) do
    query = String.trim(query)

    if query != "" do
      {:noreply, push_navigate(socket, to: "/transactions?search=#{URI.encode_www_form(query)}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:settings_changed, _}, socket) do
    {:noreply, assign(socket, :networks, list_networks())}
  end

  def handle_info(:admin_check_expiration, socket) do
    case AdminAuth.handle_info(:admin_check_expiration, socket) do
      {:handled, socket} -> {:noreply, socket}
      :not_handled -> {:noreply, socket}
    end
  end

  # Helpers

  defp list_networks do
    Settings.list_networks()
  end

  defp truncate_url(url) when is_binary(url) do
    # Remove protocol and truncate if too long
    url
    |> String.replace(~r{^https?://}, "")
    |> String.slice(0, 30)
    |> then(fn truncated ->
      if String.length(url) > 38, do: truncated <> "...", else: truncated
    end)
  end

  defp truncate_url(_), do: "-"
end
