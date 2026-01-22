defmodule AnomaExplorerWeb.AdminAuth do
  @moduledoc """
  Provides admin authorization functionality for LiveViews.

  This module implements a lightweight admin authorization system to protect
  edit/delete actions in production. When ADMIN_SECRET_KEY is set, users must
  enter the secret key to unlock editing capabilities.

  ## Usage

      use AnomaExplorerWeb, :live_view
      on_mount {AnomaExplorerWeb.AdminAuth, :load_admin_state}

  Then in your LiveView, handle admin events and use the `require_admin/2` helper
  to protect edit/delete actions.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  @session_key "admin_authorized_at"
  @default_timeout_minutes 30

  @doc """
  LiveView on_mount callback that loads admin authorization state from session.

  Initializes the following socket assigns:
  - `:admin_authorized` - boolean indicating if user is authorized
  - `:admin_authorized_at` - timestamp when authorization was granted (or nil)
  - `:admin_timeout_ms` - timeout duration in milliseconds
  - `:admin_show_unlock_modal` - boolean to control unlock modal visibility
  - `:admin_error` - error message for unlock modal (or nil)
  """
  def on_mount(:load_admin_state, _params, session, socket) do
    timeout_ms = get_timeout_ms()
    admin_authorized_at = Map.get(session, @session_key)

    is_authorized = authorized?(admin_authorized_at, timeout_ms)

    socket =
      socket
      |> assign(:admin_authorized, is_authorized)
      |> assign(:admin_authorized_at, admin_authorized_at)
      |> assign(:admin_timeout_ms, timeout_ms)
      |> assign(:admin_show_unlock_modal, false)
      |> assign(:admin_error, nil)

    # Schedule expiration check if authorized
    if is_authorized and connected?(socket) do
      schedule_expiration_check(admin_authorized_at, timeout_ms)
    end

    {:cont, socket}
  end

  @doc """
  Checks if the authorization is still valid based on timestamp and timeout.

  Returns `true` if the authorization timestamp exists and hasn't expired.
  """
  @spec authorized?(integer() | nil, integer()) :: boolean()
  def authorized?(nil, _timeout_ms), do: false

  def authorized?(authorized_at, timeout_ms) when is_integer(authorized_at) do
    now = System.system_time(:millisecond)
    authorized_at + timeout_ms > now
  end

  def authorized?(_, _), do: false

  @doc """
  Verifies the provided secret key against the configured admin secret.

  Uses `Plug.Crypto.secure_compare/2` to prevent timing attacks.
  Returns `true` if the key matches, `false` otherwise.
  """
  @spec verify_secret(String.t()) :: boolean()
  def verify_secret(key) when is_binary(key) do
    expected = Application.get_env(:anoma_explorer, :admin_secret_key)
    expected != nil && Plug.Crypto.secure_compare(key, expected)
  end

  def verify_secret(_), do: false

  @doc """
  Returns the configured timeout in milliseconds.

  Defaults to #{@default_timeout_minutes} minutes if not configured.
  """
  @spec get_timeout_ms() :: integer()
  def get_timeout_ms do
    minutes = Application.get_env(:anoma_explorer, :admin_timeout_minutes, @default_timeout_minutes)
    minutes * 60 * 1000
  end

  @doc """
  Returns `true` if admin authorization is enabled (ADMIN_SECRET_KEY is set).

  When admin is not enabled, all actions are allowed without authorization.
  """
  @spec admin_enabled?() :: boolean()
  def admin_enabled? do
    Application.get_env(:anoma_explorer, :admin_secret_key) != nil
  end

  @doc """
  Returns the session key used to store the authorization timestamp.
  """
  @spec session_key() :: String.t()
  def session_key, do: @session_key

  @doc """
  Wraps an action to require admin authorization.

  If admin is not enabled or user is authorized, executes the function.
  Otherwise, shows the unlock modal.

  ## Example

      def handle_event("delete_item", %{"id" => id}, socket) do
        AdminAuth.require_admin(socket, fn ->
          # Your delete logic here
          {:noreply, socket}
        end)
      end
  """
  @spec require_admin(Phoenix.LiveView.Socket.t(), (-> {:noreply, Phoenix.LiveView.Socket.t()})) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def require_admin(socket, fun) do
    if socket.assigns[:admin_authorized] || !admin_enabled?() do
      fun.()
    else
      {:noreply, assign(socket, :admin_show_unlock_modal, true)}
    end
  end

  @doc """
  Handles admin-related LiveView events.

  Call this from your LiveView's `handle_event/3` for admin events.
  Returns `{:handled, socket}` if the event was handled, `:not_handled` otherwise.

  ## Handled events

  - `"admin_show_unlock_modal"` - Shows the unlock modal
  - `"admin_close_unlock_modal"` - Closes the unlock modal
  - `"admin_verify_secret"` - Verifies the entered secret key
  - `"admin_logout"` - Revokes admin authorization
  """
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:handled, Phoenix.LiveView.Socket.t()} | :not_handled
  def handle_event("admin_show_unlock_modal", _params, socket) do
    {:handled, assign(socket, admin_show_unlock_modal: true, admin_error: nil)}
  end

  def handle_event("admin_close_unlock_modal", _params, socket) do
    {:handled, assign(socket, admin_show_unlock_modal: false, admin_error: nil)}
  end

  def handle_event("admin_verify_secret", %{"secret_key" => key}, socket) do
    if verify_secret(key) do
      authorized_at = System.system_time(:millisecond)
      timeout_ms = socket.assigns.admin_timeout_ms
      timeout_minutes = div(timeout_ms, 60_000)

      socket =
        socket
        |> assign(:admin_authorized, true)
        |> assign(:admin_authorized_at, authorized_at)
        |> assign(:admin_show_unlock_modal, false)
        |> assign(:admin_error, nil)
        |> push_event("admin_store_session", %{authorized_at: authorized_at})
        |> put_flash(:info, "Admin access granted for #{timeout_minutes} minutes")

      # Schedule expiration check
      schedule_expiration_check(authorized_at, timeout_ms)

      {:handled, socket}
    else
      {:handled, assign(socket, :admin_error, "Invalid secret key")}
    end
  end

  def handle_event("admin_logout", _params, socket) do
    socket =
      socket
      |> assign(:admin_authorized, false)
      |> assign(:admin_authorized_at, nil)
      |> push_event("admin_clear_session", %{})
      |> put_flash(:info, "Admin access revoked")

    {:handled, socket}
  end

  def handle_event(_event, _params, _socket), do: :not_handled

  @doc """
  Handles admin-related LiveView info messages.

  Call this from your LiveView's `handle_info/2` for admin messages.
  Returns `{:handled, socket}` if the message was handled, `:not_handled` otherwise.

  ## Handled messages

  - `:admin_check_expiration` - Checks if authorization has expired
  """
  @spec handle_info(atom(), Phoenix.LiveView.Socket.t()) ::
          {:handled, Phoenix.LiveView.Socket.t()} | :not_handled
  def handle_info(:admin_check_expiration, socket) do
    if socket.assigns.admin_authorized do
      if authorized?(socket.assigns.admin_authorized_at, socket.assigns.admin_timeout_ms) do
        # Still valid, schedule next check
        remaining =
          socket.assigns.admin_authorized_at + socket.assigns.admin_timeout_ms -
            System.system_time(:millisecond)

        if remaining > 0 do
          Process.send_after(self(), :admin_check_expiration, min(remaining + 100, 60_000))
        end

        {:handled, socket}
      else
        # Expired
        socket =
          socket
          |> assign(:admin_authorized, false)
          |> assign(:admin_authorized_at, nil)
          |> push_event("admin_clear_session", %{})
          |> put_flash(:info, "Admin session expired")

        {:handled, socket}
      end
    else
      {:handled, socket}
    end
  end

  def handle_info(_msg, _socket), do: :not_handled

  # Schedules an expiration check message
  defp schedule_expiration_check(authorized_at, timeout_ms) do
    remaining = authorized_at + timeout_ms - System.system_time(:millisecond)

    if remaining > 0 do
      # Check at least every minute, or when expiration is due
      check_in = min(remaining + 100, 60_000)
      Process.send_after(self(), :admin_check_expiration, check_in)
    end
  end
end
