defmodule AnomaExplorerWeb.SettingsLive do
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorer.Settings
  alias AnomaExplorerWeb.AdminAuth

  on_mount {AdminAuth, :load_admin_state}
  alias AnomaExplorer.Settings.Protocol
  alias AnomaExplorer.Settings.ContractAddress
  alias AnomaExplorer.ChainVerifier

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Settings.subscribe()

    networks = list_networks()

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:protocols, list_protocols())
     |> assign(:networks, networks)
     |> assign(:networks_map, build_networks_map(networks))
     |> assign(:modal, nil)
     |> assign(:form, nil)
     |> assign(:verifying, false)
     |> assign(:verification_result, nil)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/settings/contracts">
      <div class="page-header">
        <div>
          <h1 class="page-title">Contracts</h1>
          <p class="text-sm text-base-content/70 mt-1">
            Manage contract categories and addresses
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
            phx-click="new_protocol"
            class="btn btn-primary btn-sm"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Add Category
          </.protected_button>
        </div>
      </div>

      <div class="space-y-6">
        <%= if Enum.empty?(@protocols) do %>
          <div class="stat-card text-center py-12">
            <.icon name="hero-cube-transparent" class="w-12 h-12 text-base-content/30 mx-auto mb-4" />
            <p class="text-base-content/70">No categories configured yet.</p>
            <.protected_button
              authorized={@admin_authorized}
              phx-click="new_protocol"
              class="btn btn-primary btn-sm mt-4"
            >
              Add your first category
            </.protected_button>
          </div>
        <% else %>
          <%= for protocol <- @protocols do %>
            <div class="stat-card">
              <div class="flex items-center justify-between mb-4">
                <div class="flex items-center gap-3">
                  <div class="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
                    <.icon name="hero-cube" class="w-5 h-5 text-primary" />
                  </div>
                  <div>
                    <div class="flex items-center gap-2">
                      <h2 class="text-lg font-semibold text-base-content">{protocol.name}</h2>
                      <%= if first_address = List.first(protocol.contract_addresses) do %>
                        <div class="tooltip" data-tip={"Category: #{first_address.category}"}>
                          <.icon name="hero-tag" class="w-4 h-4 text-base-content/50" />
                        </div>
                      <% end %>
                    </div>
                    <%= if protocol.description do %>
                      <p class="text-sm text-base-content/60">{protocol.description}</p>
                    <% end %>
                    <%= if protocol.github_url do %>
                      <a
                        href={protocol.github_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex items-center gap-1 text-xs text-base-content/50 hover:text-primary mt-1"
                      >
                        <svg
                          class="w-3 h-3"
                          fill="currentColor"
                          viewBox="0 0 24 24"
                          aria-hidden="true"
                        >
                          <path
                            fill-rule="evenodd"
                            d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z"
                            clip-rule="evenodd"
                          />
                        </svg>
                        <span>{protocol.github_url}</span>
                      </a>
                    <% end %>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <.protected_button
                    authorized={@admin_authorized}
                    phx-click="new_address"
                    phx-value-protocol-id={protocol.id}
                    class="btn btn-ghost btn-sm"
                  >
                    <.icon name="hero-plus" class="w-4 h-4" /> Add Address
                  </.protected_button>
                  <.protected_button
                    authorized={@admin_authorized}
                    phx-click="edit_protocol"
                    phx-value-id={protocol.id}
                    class="btn btn-ghost btn-sm"
                  >
                    <.icon name="hero-pencil" class="w-4 h-4" />
                  </.protected_button>
                  <.protected_button
                    authorized={@admin_authorized}
                    phx-click="delete_protocol"
                    phx-value-id={protocol.id}
                    data-confirm="Delete this category and all its addresses?"
                    class="btn btn-ghost btn-sm text-error"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </.protected_button>
                </div>
              </div>

              <%= if Enum.empty?(protocol.contract_addresses) do %>
                <p class="text-sm text-base-content/50 italic">No contract addresses configured.</p>
              <% else %>
                <div class="overflow-x-auto">
                  <table class="data-table w-full">
                    <thead>
                      <tr>
                        <th>Version</th>
                        <th>Network</th>
                        <th>Address</th>
                        <th>Status</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for address <- Enum.sort_by(protocol.contract_addresses, & &1.active, :desc) do %>
                        <tr class={unless address.active, do: "opacity-50"}>
                          <td>
                            <%= if protocol.github_url do %>
                              <a
                                href={github_release_url(protocol.github_url, address.version)}
                                target="_blank"
                                rel="noopener noreferrer"
                                class="badge badge-outline badge-sm hover:bg-primary hover:text-primary-content hover:border-primary transition-colors"
                              >
                                {address.version}
                              </a>
                            <% else %>
                              <span class="badge badge-outline badge-sm">{address.version}</span>
                            <% end %>
                          </td>
                          <td>
                            <.network_badge network={address.network} />
                          </td>
                          <td>
                            <div class="inline-flex items-center gap-1">
                              <a
                                href={explorer_url(@networks_map, address.network, address.address)}
                                target="_blank"
                                rel="noopener noreferrer"
                                class="text-sm font-mono link link-primary"
                                title={address.address}
                              >
                                {truncate_address(address.address)}
                              </a>
                              <button
                                type="button"
                                phx-click={JS.dispatch("phx:copy", detail: %{text: address.address})}
                                class="btn btn-ghost btn-xs"
                                title="Copy address"
                              >
                                <.icon name="hero-clipboard-document" class="w-3 h-3" />
                              </button>
                            </div>
                          </td>
                          <td>
                            <%= if address.active do %>
                              <span class="badge badge-success badge-sm">Active</span>
                            <% else %>
                              <span class="badge badge-ghost badge-sm">Inactive</span>
                            <% end %>
                          </td>
                          <td class="text-right">
                            <.protected_button
                              authorized={@admin_authorized}
                              phx-click="edit_address"
                              phx-value-id={address.id}
                              class="btn btn-ghost btn-xs"
                            >
                              <.icon name="hero-pencil" class="w-3 h-3" />
                            </.protected_button>
                            <.protected_button
                              authorized={@admin_authorized}
                              phx-click="delete_address"
                              phx-value-id={address.id}
                              data-confirm="Delete this address?"
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
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>

      <%= if @modal do %>
        <.modal id="settings-modal" show on_cancel={JS.push("close_modal")}>
          <.render_modal
            modal={@modal}
            form={@form}
            protocols={@protocols}
            networks={@networks}
            verifying={@verifying}
            verification_result={@verification_result}
          />
        </.modal>
      <% end %>

      <.unlock_modal show={@admin_show_unlock_modal} error={@admin_error} />
    </Layouts.app>
    """
  end

  defp render_modal(%{modal: :new_protocol, form: _form} = assigns) do
    ~H"""
    <h3 class="text-lg font-semibold mb-4">New Category</h3>
    <.form for={@form} phx-submit="save_protocol" class="space-y-4">
      <div>
        <label class="label">Name</label>
        <input
          type="text"
          name="protocol[name]"
          value={@form[:name].value}
          class="input input-bordered w-full"
          placeholder="e.g., Protocol Adapter"
          required
        />
        <.error_tag errors={@form[:name].errors} />
      </div>
      <div>
        <label class="label">Description (optional)</label>
        <input
          type="text"
          name="protocol[description]"
          value={@form[:description].value}
          class="input input-bordered w-full"
          placeholder="Brief description"
        />
      </div>
      <div>
        <label class="label">GitHub URL (optional)</label>
        <input
          type="url"
          name="protocol[github_url]"
          value={@form[:github_url].value}
          class="input input-bordered w-full"
          placeholder="e.g., https://github.com/anoma/anoma-apps"
        />
        <p class="text-xs text-base-content/50 mt-1">
          Used to link version badges to GitHub releases
        </p>
      </div>
      <div class="flex justify-end gap-2 pt-4">
        <button type="button" phx-click="close_modal" class="btn btn-ghost">Cancel</button>
        <button type="submit" class="btn btn-primary">Create Category</button>
      </div>
    </.form>
    """
  end

  defp render_modal(%{modal: {:edit_protocol, protocol}, form: _form} = assigns) do
    assigns = assign(assigns, :protocol, protocol)

    ~H"""
    <h3 class="text-lg font-semibold mb-4">Edit Category</h3>
    <.form for={@form} phx-submit="update_protocol" class="space-y-4">
      <input type="hidden" name="protocol[id]" value={@protocol.id} />
      <div>
        <label class="label">Name</label>
        <input
          type="text"
          name="protocol[name]"
          value={@form[:name].value}
          class="input input-bordered w-full"
          required
        />
        <.error_tag errors={@form[:name].errors} />
      </div>
      <div>
        <label class="label">Description</label>
        <input
          type="text"
          name="protocol[description]"
          value={@form[:description].value}
          class="input input-bordered w-full"
        />
      </div>
      <div>
        <label class="label">GitHub URL (optional)</label>
        <input
          type="url"
          name="protocol[github_url]"
          value={@form[:github_url].value}
          class="input input-bordered w-full"
          placeholder="e.g., https://github.com/anoma/anoma-apps"
        />
        <p class="text-xs text-base-content/50 mt-1">
          Used to link version badges to GitHub releases
        </p>
      </div>
      <div class="flex items-center gap-2">
        <input type="hidden" name="protocol[active]" value="false" />
        <input
          type="checkbox"
          name="protocol[active]"
          value="true"
          checked={@form[:active].value}
          class="checkbox checkbox-sm"
        />
        <label class="label">Active</label>
      </div>
      <div class="flex justify-end gap-2 pt-4">
        <button type="button" phx-click="close_modal" class="btn btn-ghost">Cancel</button>
        <button type="submit" class="btn btn-primary">Save Changes</button>
      </div>
    </.form>
    """
  end

  defp render_modal(
         %{
           modal: {:new_address, protocol_id},
           form: _form,
           protocols: _protocols,
           networks: _networks
         } = assigns
       ) do
    assigns = assign(assigns, :protocol_id, protocol_id)

    ~H"""
    <h3 class="text-lg font-semibold mb-4">New Contract Address</h3>
    <.form for={@form} phx-submit="save_address" phx-change="form_change" class="space-y-4">
      <input type="hidden" name="address[protocol_id]" value={@protocol_id} />
      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="label">Category</label>
          <input
            type="text"
            name="address[category]"
            value={@form[:category].value}
            class="input input-bordered w-full"
            placeholder="e.g., pa-evm"
            required
          />
          <.error_tag errors={@form[:category].errors} />
        </div>
        <div>
          <label class="label">Version</label>
          <input
            type="text"
            name="address[version]"
            value={@form[:version].value}
            class="input input-bordered w-full"
            placeholder="e.g., 1.0.0"
            required
          />
          <.error_tag errors={@form[:version].errors} />
        </div>
      </div>
      <div>
        <label class="label">Network</label>
        <select name="address[network]" class="select select-bordered w-full" required>
          <option
            value=""
            disabled
            selected={is_nil(@form[:network].value) || @form[:network].value == ""}
          >
            Select a network
          </option>
          <%= for network <- @networks do %>
            <option value={network.name} selected={@form[:network].value == network.name}>
              {network.display_name} ({network.name})
            </option>
          <% end %>
        </select>
        <.error_tag errors={@form[:network].errors} />
      </div>
      <div>
        <label class="label">Contract Address</label>
        <div class="flex gap-2">
          <input
            type="text"
            name="address[address]"
            value={@form[:address].value}
            class="input input-bordered w-full font-mono"
            placeholder="0x..."
            required
          />
          <button
            type="button"
            phx-click="verify_address"
            disabled={
              @verifying || is_nil(@form[:address].value) || @form[:address].value == "" ||
                is_nil(@form[:network].value) || @form[:network].value == ""
            }
            class="btn btn-outline btn-sm whitespace-nowrap"
          >
            <%= if @verifying do %>
              <span class="loading loading-spinner loading-xs"></span> Verifying...
            <% else %>
              <.icon name="hero-check-badge" class="w-4 h-4" /> Verify
            <% end %>
          </button>
        </div>
        <.error_tag errors={@form[:address].errors} />
        <.verification_badge result={@verification_result} />
      </div>
      <div class="flex justify-end gap-2 pt-4">
        <button type="button" phx-click="close_modal" class="btn btn-ghost">Cancel</button>
        <button type="submit" class="btn btn-primary">Add Address</button>
      </div>
    </.form>
    """
  end

  defp render_modal(
         %{modal: {:edit_address, address}, form: _form, networks: _networks} = assigns
       ) do
    assigns = assign(assigns, :address, address)

    ~H"""
    <h3 class="text-lg font-semibold mb-4">Edit Contract Address</h3>
    <.form for={@form} phx-submit="update_address" phx-change="form_change" class="space-y-4">
      <input type="hidden" name="address[id]" value={@address.id} />
      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="label">Category</label>
          <input
            type="text"
            name="address[category]"
            value={@form[:category].value}
            class="input input-bordered w-full"
            required
          />
          <.error_tag errors={@form[:category].errors} />
        </div>
        <div>
          <label class="label">Version</label>
          <input
            type="text"
            name="address[version]"
            value={@form[:version].value}
            class="input input-bordered w-full"
            required
          />
          <.error_tag errors={@form[:version].errors} />
        </div>
      </div>
      <div>
        <label class="label">Network</label>
        <select name="address[network]" class="select select-bordered w-full" required>
          <option value="" disabled>Select a network</option>
          <%= for network <- @networks do %>
            <option value={network.name} selected={@form[:network].value == network.name}>
              {network.display_name} ({network.name})
            </option>
          <% end %>
        </select>
      </div>
      <div>
        <label class="label">Contract Address</label>
        <div class="flex gap-2">
          <input
            type="text"
            name="address[address]"
            value={@form[:address].value}
            class="input input-bordered w-full font-mono"
            required
          />
          <button
            type="button"
            phx-click="verify_address"
            disabled={
              @verifying || is_nil(@form[:address].value) || @form[:address].value == "" ||
                is_nil(@form[:network].value) || @form[:network].value == ""
            }
            class="btn btn-outline btn-sm whitespace-nowrap"
          >
            <%= if @verifying do %>
              <span class="loading loading-spinner loading-xs"></span> Verifying...
            <% else %>
              <.icon name="hero-check-badge" class="w-4 h-4" /> Verify
            <% end %>
          </button>
        </div>
        <.error_tag errors={@form[:address].errors} />
        <.verification_badge result={@verification_result} />
      </div>
      <div class="flex items-center gap-2">
        <input type="hidden" name="address[active]" value="false" />
        <input
          type="checkbox"
          name="address[active]"
          value="true"
          checked={@form[:active].value}
          class="checkbox checkbox-sm"
        />
        <label class="label cursor-pointer">
          Active
          <div
            class="tooltip tooltip-right ml-1"
            data-tip="Inactive addresses are excluded from monitoring and won't appear in queries or dashboards"
          >
            <.icon name="hero-question-mark-circle" class="w-4 h-4 text-base-content/50" />
          </div>
        </label>
      </div>
      <div class="flex justify-end gap-2 pt-4">
        <button type="button" phx-click="close_modal" class="btn btn-ghost">Cancel</button>
        <button type="submit" class="btn btn-primary">Save Changes</button>
      </div>
    </.form>
    """
  end

  defp render_modal(%{modal: {:network_info, network}} = assigns) do
    assigns = assign(assigns, :network, network)

    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h3 class="text-lg font-semibold">Network Details</h3>
        <%= if @network.is_testnet do %>
          <span class="badge badge-warning">Testnet</span>
        <% else %>
          <span class="badge badge-info">Mainnet</span>
        <% end %>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wider">Name</label>
          <p class="font-mono text-sm">{@network.name}</p>
        </div>
        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wider">Display Name</label>
          <p class="text-sm">{@network.display_name}</p>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wider">Chain ID</label>
          <p class="text-sm">
            <%= if @network.chain_id do %>
              <span class="badge badge-outline badge-sm">{@network.chain_id}</span>
            <% else %>
              <span class="text-base-content/40">Not set</span>
            <% end %>
          </p>
        </div>
        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wider">Status</label>
          <p class="text-sm">
            <%= if @network.active do %>
              <span class="badge badge-success badge-sm">Active</span>
            <% else %>
              <span class="badge badge-ghost badge-sm">Inactive</span>
            <% end %>
          </p>
        </div>
      </div>

      <%= if @network.explorer_url do %>
        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wider">Explorer URL</label>
          <p class="text-sm font-mono break-all text-base-content/70">{@network.explorer_url}</p>
        </div>
      <% end %>

      <%= if @network.rpc_url do %>
        <div>
          <label class="text-xs text-base-content/60 uppercase tracking-wider">RPC URL</label>
          <p class="text-sm font-mono break-all text-base-content/70">{@network.rpc_url}</p>
        </div>
      <% end %>

      <div class="pt-4 border-t border-base-300">
        <a href="/settings/networks" class="btn btn-ghost btn-sm">
          <.icon name="hero-pencil" class="w-4 h-4" /> Edit in Network Settings
        </a>
      </div>
    </div>
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

  defp verification_badge(%{result: nil} = assigns), do: ~H""

  defp verification_badge(%{result: {:ok, :verified, _info}} = assigns) do
    ~H"""
    <div class="flex items-center gap-1 mt-2 text-success text-sm">
      <.icon name="hero-check-circle" class="w-4 h-4" />
      <span>Contract verified on chain explorer</span>
    </div>
    """
  end

  defp verification_badge(%{result: {:ok, :unverified}} = assigns) do
    ~H"""
    <div class="flex items-center gap-1 mt-2 text-warning text-sm">
      <.icon name="hero-exclamation-triangle" class="w-4 h-4" />
      <span>Contract exists but source code is not verified</span>
    </div>
    """
  end

  defp verification_badge(%{result: {:error, :not_contract}} = assigns) do
    ~H"""
    <div class="flex items-center gap-1 mt-2 text-error text-sm">
      <.icon name="hero-x-circle" class="w-4 h-4" />
      <span>Not a contract address (EOA or invalid)</span>
    </div>
    """
  end

  defp verification_badge(%{result: {:error, :network_unsupported}} = assigns) do
    ~H"""
    <div class="flex items-center gap-1 mt-2 text-base-content/50 text-sm">
      <.icon name="hero-information-circle" class="w-4 h-4" />
      <span>Verification not available for this network</span>
    </div>
    """
  end

  defp verification_badge(%{result: {:error, :api_error, reason}} = assigns) do
    assigns = assign(assigns, :reason, reason)

    ~H"""
    <div class="flex items-center gap-1 mt-2 text-error text-sm">
      <.icon name="hero-x-circle" class="w-4 h-4" />
      <span>Verification failed: {@reason}</span>
    </div>
    """
  end

  defp verification_badge(assigns), do: ~H""

  defp network_badge(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="show_network_info"
      phx-value-network={@network}
      class="text-sm text-base-content/70 hover:text-primary hover:underline cursor-pointer"
    >
      {@network}
    </button>
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

  def handle_event("show_network_info", %{"network" => network_name}, socket) do
    case Map.get(socket.assigns.networks_map, network_name) do
      nil ->
        {:noreply, put_flash(socket, :error, "Network '#{network_name}' not found in database")}

      network ->
        {:noreply, assign(socket, modal: {:network_info, network})}
    end
  end

  def handle_event("new_protocol", _params, socket) do
    AdminAuth.require_admin(socket, fn ->
      form = to_form(Settings.change_protocol(%Protocol{}))
      {:noreply, assign(socket, modal: :new_protocol, form: form)}
    end)
  end

  def handle_event("edit_protocol", %{"id" => id}, socket) do
    AdminAuth.require_admin(socket, fn ->
      protocol = Settings.get_protocol!(id)
      form = to_form(Settings.change_protocol(protocol))
      {:noreply, assign(socket, modal: {:edit_protocol, protocol}, form: form)}
    end)
  end

  def handle_event("delete_protocol", %{"id" => id}, socket) do
    AdminAuth.require_admin(socket, fn ->
      protocol = Settings.get_protocol!(id)

      case Settings.delete_protocol(protocol) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Category deleted")
           |> assign(:protocols, list_protocols())}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete protocol")}
      end
    end)
  end

  def handle_event("save_protocol", %{"protocol" => params}, socket) do
    case Settings.create_protocol(params) do
      {:ok, _protocol} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category created")
         |> assign(:protocols, list_protocols())
         |> assign(:modal, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("update_protocol", %{"protocol" => params}, socket) do
    {:edit_protocol, protocol} = socket.assigns.modal

    case Settings.update_protocol(protocol, params) do
      {:ok, _protocol} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category updated")
         |> assign(:protocols, list_protocols())
         |> assign(:modal, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("new_address", %{"protocol-id" => protocol_id}, socket) do
    AdminAuth.require_admin(socket, fn ->
      form =
        to_form(
          Settings.change_contract_address(%ContractAddress{
            protocol_id: String.to_integer(protocol_id)
          })
        )

      {:noreply,
       assign(socket,
         modal: {:new_address, protocol_id},
         form: form,
         verifying: false,
         verification_result: nil
       )}
    end)
  end

  def handle_event("edit_address", %{"id" => id}, socket) do
    AdminAuth.require_admin(socket, fn ->
      address = Settings.get_contract_address!(id)
      form = to_form(Settings.change_contract_address(address))

      {:noreply,
       assign(socket,
         modal: {:edit_address, address},
         form: form,
         verifying: false,
         verification_result: nil
       )}
    end)
  end

  def handle_event("delete_address", %{"id" => id}, socket) do
    AdminAuth.require_admin(socket, fn ->
      address = Settings.get_contract_address!(id)

      case Settings.delete_contract_address(address) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Address deleted")
           |> assign(:protocols, list_protocols())}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete address")}
      end
    end)
  end

  def handle_event("save_address", %{"address" => params}, socket) do
    case Settings.create_contract_address(params) do
      {:ok, _address} ->
        {:noreply,
         socket
         |> put_flash(:info, "Address created")
         |> assign(:protocols, list_protocols())
         |> assign(:modal, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("update_address", %{"address" => params}, socket) do
    {:edit_address, address} = socket.assigns.modal

    case Settings.update_contract_address(address, params) do
      {:ok, _address} ->
        {:noreply,
         socket
         |> put_flash(:info, "Address updated")
         |> assign(:protocols, list_protocols())
         |> assign(:modal, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil, verification_result: nil)}
  end

  def handle_event("form_change", %{"address" => params}, socket) do
    # Update the form with the new values so disabled states work correctly
    changeset = Settings.change_contract_address(%ContractAddress{}, params)
    {:noreply, assign(socket, form: to_form(changeset), verification_result: nil)}
  end

  def handle_event("form_change", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("verify_address", _params, socket) do
    form = socket.assigns.form
    network = form[:network].value
    address = form[:address].value

    if network && address && String.trim(network) != "" && String.trim(address) != "" do
      send(self(), {:do_verify, network, address})
      {:noreply, assign(socket, verifying: true, verification_result: nil)}
    else
      {:noreply, socket}
    end
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
    networks = list_networks()

    {:noreply,
     socket
     |> assign(:protocols, list_protocols())
     |> assign(:networks, networks)
     |> assign(:networks_map, build_networks_map(networks))}
  end

  def handle_info({:do_verify, network, address}, socket) do
    result = ChainVerifier.verify(network, address)
    {:noreply, assign(socket, verifying: false, verification_result: result)}
  end

  def handle_info(:admin_check_expiration, socket) do
    case AdminAuth.handle_info(:admin_check_expiration, socket) do
      {:handled, socket} -> {:noreply, socket}
      :not_handled -> {:noreply, socket}
    end
  end

  # Helpers

  defp list_protocols do
    Settings.list_protocols(preload: [:contract_addresses])
  end

  defp list_networks do
    Settings.list_networks(active: true)
  end

  defp build_networks_map(networks) do
    Map.new(networks, fn n -> {n.name, n} end)
  end

  defp truncate_address(address) when byte_size(address) > 16 do
    String.slice(address, 0, 10) <> "..." <> String.slice(address, -6, 6)
  end

  defp truncate_address(address), do: address

  defp explorer_url(networks_map, network_name, address) do
    case Map.get(networks_map, network_name) do
      %{explorer_url: explorer_url} when is_binary(explorer_url) and explorer_url != "" ->
        explorer_url <> address

      _ ->
        # Fallback to hardcoded URLs for backwards compatibility
        fallback_explorer_url(network_name, address)
    end
  end

  defp fallback_explorer_url(network, address) do
    base_url =
      case network do
        # Ethereum
        "eth-mainnet" -> "https://etherscan.io/address/"
        "eth-sepolia" -> "https://sepolia.etherscan.io/address/"
        # Base
        "base-mainnet" -> "https://basescan.org/address/"
        "base-sepolia" -> "https://sepolia.basescan.org/address/"
        # Polygon
        "polygon-mainnet" -> "https://polygonscan.com/address/"
        "polygon-mumbai" -> "https://mumbai.polygonscan.com/address/"
        # Arbitrum
        "arbitrum-mainnet" -> "https://arbiscan.io/address/"
        "arb-mainnet" -> "https://arbiscan.io/address/"
        "arbitrum-sepolia" -> "https://sepolia.arbiscan.io/address/"
        "arb-sepolia" -> "https://sepolia.arbiscan.io/address/"
        # Optimism
        "optimism-mainnet" -> "https://optimistic.etherscan.io/address/"
        "op-mainnet" -> "https://optimistic.etherscan.io/address/"
        "optimism-sepolia" -> "https://sepolia-optimism.etherscan.io/address/"
        "op-sepolia" -> "https://sepolia-optimism.etherscan.io/address/"
        # BSC
        "bsc-mainnet" -> "https://bscscan.com/address/"
        "bsc-testnet" -> "https://testnet.bscscan.com/address/"
        # Avalanche
        "avalanche-mainnet" -> "https://snowtrace.io/address/"
        "avalanche-fuji" -> "https://testnet.snowtrace.io/address/"
        _ -> nil
      end

    if base_url, do: base_url <> address, else: "#"
  end

  defp github_release_url(github_url, version) do
    # Remove trailing slash if present and append /releases/tag/<version>
    base = String.trim_trailing(github_url, "/")
    "#{base}/releases/tag/#{version}"
  end
end
