defmodule AnomaExplorerWeb.SettingsLive do
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorer.Settings
  alias AnomaExplorer.Settings.Protocol
  alias AnomaExplorer.Settings.ContractAddress

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Settings.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:protocols, list_protocols())
     |> assign(:modal, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/settings">
      <div class="page-header">
        <div>
          <h1 class="page-title">Settings</h1>
          <p class="text-sm text-base-content/70 mt-1">
            Manage categories and contract addresses
          </p>
        </div>
        <button phx-click="new_protocol" class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="w-4 h-4" /> Add Category
        </button>
      </div>

      <div class="space-y-6">
        <%= if Enum.empty?(@protocols) do %>
          <div class="stat-card text-center py-12">
            <.icon name="hero-cube-transparent" class="w-12 h-12 text-base-content/30 mx-auto mb-4" />
            <p class="text-base-content/70">No categories configured yet.</p>
            <button phx-click="new_protocol" class="btn btn-primary btn-sm mt-4">
              Add your first category
            </button>
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
                      <h2 class="text-lg font-semibold text-base-content"><%= protocol.name %></h2>
                      <%= if first_address = List.first(protocol.contract_addresses) do %>
                        <div class="tooltip" data-tip={"Category: #{first_address.category}"}>
                          <.icon name="hero-tag" class="w-4 h-4 text-base-content/50" />
                        </div>
                      <% end %>
                    </div>
                    <%= if protocol.description do %>
                      <p class="text-sm text-base-content/60"><%= protocol.description %></p>
                    <% end %>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <button
                    phx-click="new_address"
                    phx-value-protocol-id={protocol.id}
                    class="btn btn-ghost btn-sm"
                  >
                    <.icon name="hero-plus" class="w-4 h-4" /> Add Address
                  </button>
                  <button
                    phx-click="edit_protocol"
                    phx-value-id={protocol.id}
                    class="btn btn-ghost btn-sm"
                  >
                    <.icon name="hero-pencil" class="w-4 h-4" />
                  </button>
                  <button
                    phx-click="delete_protocol"
                    phx-value-id={protocol.id}
                    data-confirm="Delete this category and all its addresses?"
                    class="btn btn-ghost btn-sm text-error"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </button>
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
                      <%= for address <- protocol.contract_addresses do %>
                        <tr>
                          <td>
                            <%= if protocol.github_url do %>
                              <a
                                href={github_release_url(protocol.github_url, address.version)}
                                target="_blank"
                                rel="noopener noreferrer"
                                class="badge badge-outline badge-sm hover:bg-primary hover:text-primary-content hover:border-primary transition-colors"
                              >
                                <%= address.version %>
                              </a>
                            <% else %>
                              <span class="badge badge-outline badge-sm"><%= address.version %></span>
                            <% end %>
                          </td>
                          <td>
                            <.network_badge network={address.network} />
                          </td>
                          <td>
                            <div class="inline-flex items-center gap-1">
                              <a
                                href={explorer_url(address.network, address.address)}
                                target="_blank"
                                rel="noopener noreferrer"
                                class="text-sm font-mono link link-primary"
                                title={address.address}
                              >
                                <%= truncate_address(address.address) %>
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
                            <button
                              phx-click="edit_address"
                              phx-value-id={address.id}
                              class="btn btn-ghost btn-xs"
                            >
                              <.icon name="hero-pencil" class="w-3 h-3" />
                            </button>
                            <button
                              phx-click="delete_address"
                              phx-value-id={address.id}
                              data-confirm="Delete this address?"
                              class="btn btn-ghost btn-xs text-error"
                            >
                              <.icon name="hero-trash" class="w-3 h-3" />
                            </button>
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
          <.render_modal modal={@modal} form={@form} protocols={@protocols} />
        </.modal>
      <% end %>
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
        <p class="text-xs text-base-content/50 mt-1">Used to link version badges to GitHub releases</p>
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
        <p class="text-xs text-base-content/50 mt-1">Used to link version badges to GitHub releases</p>
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

  defp render_modal(%{modal: {:new_address, protocol_id}, form: _form, protocols: _protocols} = assigns) do
    assigns = assign(assigns, :protocol_id, protocol_id)

    ~H"""
    <h3 class="text-lg font-semibold mb-4">New Contract Address</h3>
    <.form for={@form} phx-submit="save_address" class="space-y-4">
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
        <input
          type="text"
          name="address[network]"
          value={@form[:network].value}
          class="input input-bordered w-full"
          placeholder="e.g., eth-mainnet, base-sepolia"
          required
        />
        <.error_tag errors={@form[:network].errors} />
      </div>
      <div>
        <label class="label">Contract Address</label>
        <input
          type="text"
          name="address[address]"
          value={@form[:address].value}
          class="input input-bordered w-full font-mono"
          placeholder="0x..."
          required
        />
        <.error_tag errors={@form[:address].errors} />
      </div>
      <div class="flex justify-end gap-2 pt-4">
        <button type="button" phx-click="close_modal" class="btn btn-ghost">Cancel</button>
        <button type="submit" class="btn btn-primary">Add Address</button>
      </div>
    </.form>
    """
  end

  defp render_modal(%{modal: {:edit_address, address}, form: _form} = assigns) do
    assigns = assign(assigns, :address, address)

    ~H"""
    <h3 class="text-lg font-semibold mb-4">Edit Contract Address</h3>
    <.form for={@form} phx-submit="update_address" class="space-y-4">
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
        <input
          type="text"
          name="address[network]"
          value={@form[:network].value}
          class="input input-bordered w-full"
          required
        />
      </div>
      <div>
        <label class="label">Contract Address</label>
        <input
          type="text"
          name="address[address]"
          value={@form[:address].value}
          class="input input-bordered w-full font-mono"
          required
        />
        <.error_tag errors={@form[:address].errors} />
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
          <div class="tooltip tooltip-right ml-1" data-tip="Inactive addresses are excluded from monitoring and won't appear in queries or dashboards">
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

  defp render_modal(assigns), do: ~H""

  defp error_tag(assigns) do
    ~H"""
    <%= for {msg, _} <- @errors || [] do %>
      <p class="text-error text-sm mt-1"><%= msg %></p>
    <% end %>
    """
  end

  defp network_badge(assigns) do
    ~H"""
    <span class="text-sm text-base-content/70"><%= @network %></span>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("new_protocol", _params, socket) do
    form = to_form(Settings.change_protocol(%Protocol{}))
    {:noreply, assign(socket, modal: :new_protocol, form: form)}
  end

  def handle_event("edit_protocol", %{"id" => id}, socket) do
    protocol = Settings.get_protocol!(id)
    form = to_form(Settings.change_protocol(protocol))
    {:noreply, assign(socket, modal: {:edit_protocol, protocol}, form: form)}
  end

  def handle_event("delete_protocol", %{"id" => id}, socket) do
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
    form = to_form(Settings.change_contract_address(%ContractAddress{protocol_id: String.to_integer(protocol_id)}))
    {:noreply, assign(socket, modal: {:new_address, protocol_id}, form: form)}
  end

  def handle_event("edit_address", %{"id" => id}, socket) do
    address = Settings.get_contract_address!(id)
    form = to_form(Settings.change_contract_address(address))
    {:noreply, assign(socket, modal: {:edit_address, address}, form: form)}
  end

  def handle_event("delete_address", %{"id" => id}, socket) do
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
    {:noreply, assign(socket, modal: nil, form: nil)}
  end

  @impl true
  def handle_info({:settings_changed, _}, socket) do
    {:noreply, assign(socket, :protocols, list_protocols())}
  end

  # Helpers

  defp list_protocols do
    Settings.list_protocols(preload: [:contract_addresses])
  end

  defp truncate_address(address) when byte_size(address) > 16 do
    String.slice(address, 0, 10) <> "..." <> String.slice(address, -6, 6)
  end

  defp truncate_address(address), do: address

  defp explorer_url(network, address) do
    base_url = case network do
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
