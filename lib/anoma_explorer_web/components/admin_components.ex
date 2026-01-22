defmodule AnomaExplorerWeb.AdminComponents do
  @moduledoc """
  Reusable UI components for admin authorization.

  These components provide visual feedback for the admin authorization system,
  including lock icons, unlock modal, and status indicators.
  """

  use Phoenix.Component
  import AnomaExplorerWeb.CoreComponents

  alias Phoenix.LiveView.JS
  alias AnomaExplorerWeb.AdminAuth

  @doc """
  Renders a protected button that shows a lock icon when not authorized.

  When authorized, renders a normal button. When not authorized, shows a
  lock icon and triggers the unlock modal on click.

  ## Attributes

  - `:authorized` - Whether the user is authorized (required)
  - `:class` - Additional CSS classes
  - `:rest` - All other attributes are passed to the button

  ## Slots

  - `:inner_block` - The button content

  ## Examples

      <.protected_button authorized={@admin_authorized} phx-click="edit_item" class="btn btn-ghost">
        <.icon name="hero-pencil" class="w-4 h-4" />
      </.protected_button>
  """
  attr :authorized, :boolean, required: true
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-click phx-value-id phx-value-protocol-id data-confirm disabled type)

  slot :inner_block, required: true

  def protected_button(assigns) do
    # Check if admin is enabled - if not, always show as authorized
    assigns = assign_new(assigns, :admin_enabled, fn -> AdminAuth.admin_enabled?() end)

    ~H"""
    <%= if @authorized || !@admin_enabled do %>
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
    <% else %>
      <button
        class={[@class, "opacity-60"]}
        phx-click="admin_show_unlock_modal"
        type="button"
        title="Admin authorization required"
      >
        <.icon name="hero-lock-closed" class="w-3 h-3 mr-1 inline" />
        {render_slot(@inner_block)}
      </button>
    <% end %>
    """
  end

  @doc """
  Renders the admin unlock modal.

  Shows a form for entering the admin secret key.

  ## Attributes

  - `:show` - Whether to show the modal (required)
  - `:error` - Error message to display (optional)

  ## Examples

      <.unlock_modal show={@admin_show_unlock_modal} error={@admin_error} />
  """
  attr :show, :boolean, required: true
  attr :error, :string, default: nil

  def unlock_modal(assigns) do
    ~H"""
    <.modal
      :if={@show}
      id="admin-unlock-modal"
      show={@show}
      on_cancel={JS.push("admin_close_unlock_modal")}
    >
      <:title>
        <span class="flex items-center gap-2">
          <.icon name="hero-lock-closed" class="w-5 h-5" />
          Admin Authorization Required
        </span>
      </:title>
      <p class="text-sm text-base-content/70 mb-4">
        Enter the admin secret key to unlock edit and delete actions.
      </p>
      <.form for={%{}} phx-submit="admin_verify_secret" class="space-y-4">
        <div>
          <label class="label">
            <span class="label-text">Secret Key</span>
          </label>
          <input
            type="password"
            name="secret_key"
            class="input input-bordered w-full"
            placeholder="Enter admin secret key"
            autocomplete="off"
            autofocus
            required
          />
          <p :if={@error} class="text-error text-sm mt-2">
            {@error}
          </p>
        </div>
        <div class="flex justify-end gap-2 pt-4">
          <button type="button" phx-click="admin_close_unlock_modal" class="btn btn-ghost">
            Cancel
          </button>
          <button type="submit" class="btn btn-primary">
            <.icon name="hero-lock-open" class="w-4 h-4 mr-1" /> Unlock
          </button>
        </div>
      </.form>
    </.modal>
    """
  end

  @doc """
  Renders the admin status indicator.

  Shows the current authorization state with a badge and remaining time.

  ## Attributes

  - `:authorized` - Whether the user is authorized (required)
  - `:authorized_at` - Timestamp when authorization was granted (optional)
  - `:timeout_ms` - Timeout duration in milliseconds (required)

  ## Examples

      <.admin_status
        authorized={@admin_authorized}
        authorized_at={@admin_authorized_at}
        timeout_ms={@admin_timeout_ms}
      />
  """
  attr :authorized, :boolean, required: true
  attr :authorized_at, :integer, default: nil
  attr :timeout_ms, :integer, required: true

  def admin_status(assigns) do
    # Check if admin is enabled
    admin_enabled = AdminAuth.admin_enabled?()

    remaining_minutes =
      if assigns.authorized && assigns.authorized_at do
        elapsed = System.system_time(:millisecond) - assigns.authorized_at
        max(0, div(assigns.timeout_ms - elapsed, 60_000))
      else
        0
      end

    assigns =
      assigns
      |> assign(:remaining_minutes, remaining_minutes)
      |> assign(:admin_enabled, admin_enabled)

    ~H"""
    <div :if={@admin_enabled} class="flex items-center gap-2 text-sm">
      <%= if @authorized do %>
        <div class="badge badge-success gap-1">
          <.icon name="hero-lock-open" class="w-3 h-3" />
          <span>Admin ({@remaining_minutes}m)</span>
        </div>
        <button
          phx-click="admin_logout"
          class="btn btn-ghost btn-xs"
          title="Revoke admin access"
        >
          <.icon name="hero-lock-closed" class="w-3 h-3" />
        </button>
      <% else %>
        <button
          phx-click="admin_show_unlock_modal"
          class="badge badge-ghost gap-1 cursor-pointer hover:badge-primary transition-colors"
          title="Click to unlock admin access"
        >
          <.icon name="hero-lock-closed" class="w-3 h-3" />
          <span>Locked</span>
        </button>
      <% end %>
    </div>
    """
  end
end
