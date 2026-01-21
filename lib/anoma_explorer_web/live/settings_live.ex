defmodule AnomaExplorerWeb.SettingsLive do
  @moduledoc """
  LiveView for managing contract settings.

  Provides CRUD interface for contract addresses organized by category and network.
  """
  use AnomaExplorerWeb, :live_view

  alias AnomaExplorer.Settings
  alias AnomaExplorer.Settings.ContractSetting
  alias AnomaExplorer.Config

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Settings.subscribe()
    end

    socket =
      socket
      |> assign(:page_title, "Contract Settings")
      |> assign(:settings, list_grouped_settings())
      |> assign(:categories, ContractSetting.valid_categories())
      |> assign(:networks, Config.supported_networks())
      |> assign(:editing, nil)
      |> assign(:form, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:editing, nil)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    changeset = Settings.change_setting(%ContractSetting{})

    socket
    |> assign(:editing, :new)
    |> assign(:form, to_form(changeset))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    setting = Settings.get_setting!(id)
    changeset = Settings.change_setting(setting)

    socket
    |> assign(:editing, setting)
    |> assign(:form, to_form(changeset))
  end

  @impl true
  def handle_event("save", %{"contract_setting" => params}, socket) do
    save_setting(socket, socket.assigns.editing, params)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    setting = Settings.get_setting!(id)

    case Settings.delete_setting(setting) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Setting deleted successfully")
         |> assign(:settings, list_grouped_settings())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete setting")}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/settings")}
  end

  @impl true
  def handle_info({:settings_changed, _setting}, socket) do
    {:noreply, assign(socket, :settings, list_grouped_settings())}
  end

  defp save_setting(socket, :new, params) do
    case Settings.create_setting(params) do
      {:ok, _setting} ->
        {:noreply,
         socket
         |> put_flash(:info, "Setting created successfully")
         |> push_patch(to: ~p"/settings")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_setting(socket, %ContractSetting{} = setting, params) do
    case Settings.update_setting(setting, params) do
      {:ok, _setting} ->
        {:noreply,
         socket
         |> put_flash(:info, "Setting updated successfully")
         |> push_patch(to: ~p"/settings")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp list_grouped_settings do
    Settings.list_settings_by_category()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/settings">
      <!-- Page Header -->
      <div class="page-header">
        <div>
          <h1 class="page-title">Contract Settings</h1>
          <p class="text-sm text-base-content/60 mt-1">
            Manage contract addresses by category and network
          </p>
        </div>
        <div>
          <.link navigate={~p"/settings/new"} class="btn btn-primary">
            <.icon name="hero-plus" class="w-4 h-4 mr-2" /> Add Setting
          </.link>
        </div>
      </div>
      
    <!-- Settings by Category -->
      <%= for category <- @categories do %>
        <div class="stat-card mb-6">
          <h3 class="text-lg font-semibold text-base-content mb-4 flex items-center gap-2">
            <.icon name="hero-cube" class="w-5 h-5 text-primary" />
            {format_category(category)}
          </h3>

          <div class="overflow-x-auto">
            <table class="data-table">
              <thead>
                <tr>
                  <th>Network</th>
                  <th>Address</th>
                  <th>Status</th>
                  <th class="w-24">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for setting <- Map.get(@settings, category, []) do %>
                  <tr>
                    <td>
                      <span class={network_badge_class(setting.network)}>
                        {format_network(setting.network)}
                      </span>
                    </td>
                    <td>
                      <span class="font-mono text-sm" title={setting.address}>
                        {truncate_address(setting.address)}
                      </span>
                    </td>
                    <td>
                      <span class={status_badge_class(setting.active)}>
                        {if setting.active, do: "Active", else: "Inactive"}
                      </span>
                    </td>
                    <td>
                      <div class="flex gap-2">
                        <.link
                          navigate={~p"/settings/#{setting.id}/edit"}
                          class="btn btn-xs btn-ghost"
                        >
                          <.icon name="hero-pencil" class="w-4 h-4" />
                        </.link>
                        <button
                          phx-click="delete"
                          phx-value-id={setting.id}
                          data-confirm="Are you sure you want to delete this setting?"
                          class="btn btn-xs btn-ghost text-error"
                        >
                          <.icon name="hero-trash" class="w-4 h-4" />
                        </button>
                      </div>
                    </td>
                  </tr>
                <% end %>
                <%= if Map.get(@settings, category, []) == [] do %>
                  <tr>
                    <td colspan="4" class="text-center text-base-content/50 py-8">
                      No settings for this category
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>
      
    <!-- Modal for Add/Edit -->
      <%= if @editing do %>
        <.modal id="setting-modal" show on_cancel={JS.patch(~p"/settings")}>
          <:title>{if @editing == :new, do: "Add Setting", else: "Edit Setting"}</:title>

          <.form for={@form} phx-submit="save" class="space-y-4">
            <.input
              field={@form[:category]}
              type="select"
              label="Category"
              options={Enum.map(@categories, &{format_category(&1), &1})}
              prompt="Select category..."
              disabled={@editing != :new}
            />

            <.input
              field={@form[:network]}
              type="select"
              label="Network"
              options={Enum.map(@networks, &{&1, &1})}
              prompt="Select network..."
              disabled={@editing != :new}
            />

            <.input field={@form[:address]} type="text" label="Contract Address" placeholder="0x..." />

            <.input field={@form[:active]} type="checkbox" label="Active" />

            <div class="flex justify-end gap-3 pt-4">
              <button type="button" phx-click="cancel" class="btn">Cancel</button>
              <button type="submit" class="btn btn-primary">
                {if @editing == :new, do: "Create", else: "Update"}
              </button>
            </div>
          </.form>
        </.modal>
      <% end %>
    </Layouts.app>
    """
  end

  # ============================================
  # View Helpers
  # ============================================

  defp format_category(category) do
    category
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_network(network) do
    network
    |> String.split("-")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp truncate_address(address) when byte_size(address) > 16 do
    String.slice(address, 0, 10) <> "..." <> String.slice(address, -6, 6)
  end

  defp truncate_address(address), do: address

  defp network_badge_class(network) do
    base = "network-badge"

    cond do
      String.contains?(network, "eth") -> "#{base} network-badge-eth"
      String.contains?(network, "base") -> "#{base} network-badge-base"
      String.contains?(network, "arb") -> "#{base} network-badge-arbitrum"
      String.contains?(network, "opt") -> "#{base} network-badge-optimism"
      true -> base
    end
  end

  defp status_badge_class(true), do: "badge badge-success badge-sm"
  defp status_badge_class(false), do: "badge badge-ghost badge-sm"
end
