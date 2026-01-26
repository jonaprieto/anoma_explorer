defmodule AnomaExplorerWeb.Live.Helpers.SetupHandlers do
  @moduledoc """
  Shared event handlers for indexer setup flow.

  Provides helpers for handling URL input, auto-testing, and saving
  that can be used across any LiveView that needs configuration setup.

  ## Usage

      alias AnomaExplorerWeb.Live.Helpers.SetupHandlers

      def mount(_params, _session, socket) do
        {:ok, SetupHandlers.init_setup_assigns(socket)}
      end

      def handle_event("setup_update_url", %{"url" => url}, socket) do
        {:noreply, SetupHandlers.handle_update_url(socket, url)}
      end

      def handle_event("setup_save_url", %{"url" => url}, socket) do
        case SetupHandlers.handle_save_url(socket, url) do
          {:ok, socket} -> {:noreply, socket}
          {:error, socket} -> {:noreply, socket}
        end
      end

      def handle_info({:setup_auto_test_connection, url}, socket) do
        {:noreply, SetupHandlers.handle_auto_test(socket, url)}
      end
  """

  alias AnomaExplorer.Indexer.Client
  alias AnomaExplorer.Settings

  @doc """
  Initializes socket assigns for setup flow.
  Call this in mount/3 for views that need setup functionality.
  """
  @spec init_setup_assigns(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init_setup_assigns(socket) do
    url = Settings.get_envio_url() || ""

    Phoenix.Component.assign(socket,
      setup_url_input: url,
      setup_status: nil,
      setup_auto_test_timer: nil,
      setup_auto_testing: false,
      setup_saving: false
    )
  end

  @doc """
  Handles URL input change with debounced auto-test.
  """
  @spec handle_update_url(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def handle_update_url(socket, url) do
    # Cancel any pending auto-test timer
    if socket.assigns[:setup_auto_test_timer] do
      Process.cancel_timer(socket.assigns.setup_auto_test_timer)
    end

    # Schedule auto-test after 1.5 seconds of inactivity
    timer =
      if url != "" do
        Process.send_after(self(), {:setup_auto_test_connection, url}, 1500)
      else
        nil
      end

    Phoenix.Component.assign(socket,
      setup_url_input: url,
      setup_status: nil,
      setup_auto_test_timer: timer,
      setup_auto_testing: url != ""
    )
  end

  @doc """
  Handles auto-test timer firing.
  """
  @spec handle_auto_test(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def handle_auto_test(socket, url) do
    # Only test if URL hasn't changed since timer was set
    if socket.assigns.setup_url_input == url do
      status = Client.test_connection(url)

      Phoenix.Component.assign(socket,
        setup_status: status,
        setup_auto_test_timer: nil,
        setup_auto_testing: false
      )
    else
      socket
    end
  end

  @doc """
  Handles save URL action.
  Returns {:ok, socket} on success, {:error, socket} on failure.
  """
  @spec handle_save_url(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:error, Phoenix.LiveView.Socket.t()}
  def handle_save_url(socket, url) do
    socket = Phoenix.Component.assign(socket, :setup_saving, true)

    case Settings.set_envio_url(url) do
      {:ok, _} ->
        {:ok,
         socket
         |> Phoenix.Component.assign(:setup_saving, false)
         |> Phoenix.LiveView.put_flash(:info, "Indexer endpoint saved successfully")}

      {:error, _} ->
        {:error,
         socket
         |> Phoenix.Component.assign(:setup_saving, false)
         |> Phoenix.LiveView.put_flash(:error, "Failed to save endpoint")}
    end
  end
end
