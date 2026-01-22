defmodule AnomaExplorerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use AnomaExplorerWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders your app layout with sidebar navigation.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_path, :string, default: "/", doc: "the current request path"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <!-- Sidebar -->
      <aside class="sidebar">
        <div class="flex flex-col h-full">
          <!-- Logo -->
          <div class="p-6 border-b border-base-300">
            <div class="flex items-center justify-between">
              <a href="/" class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-xl bg-primary flex items-center justify-center">
                  <span class="text-xl font-bold text-primary-content">A</span>
                </div>
                <div>
                  <span class="text-lg font-semibold text-base-content">Anoma</span>
                  <span class="text-lg font-light text-base-content/70">Explorer</span>
                </div>
              </a>
              <.theme_toggle />
            </div>
          </div>
          
    <!-- Navigation -->
          <nav class="flex-1 py-6">
            <div class="px-4 mb-2">
              <span class="text-xs font-medium text-base-content/60 uppercase tracking-wider">
                Overview
              </span>
            </div>

            <a href="/" class={nav_class(@current_path, "/")}>
              <.icon name="hero-home" class="w-5 h-5" />
              <span>Dashboard</span>
            </a>

            <a href="/settings" class={nav_class(@current_path, "/settings")}>
              <.icon name="hero-cog-6-tooth" class="w-5 h-5" />
              <span>Settings</span>
            </a>
          </nav>
          
    <!-- Footer -->
          <div class="p-4 border-t border-base-300">
            <div class="text-xs text-base-content/60">
              v{app_version()}
            </div>
          </div>
        </div>
      </aside>
      
    <!-- Main content -->
      <main class="ml-64 min-h-screen">
        <div class="p-8">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  defp nav_class(current_path, target_path) do
    base = "sidebar-nav-item"

    if current_path == target_path do
      "#{base} active"
    else
      base
    end
  end

  defp app_version do
    Application.spec(:anoma_explorer, :vsn) |> to_string()
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-1 bg-base-300 rounded-lg p-1">
      <button
        class="p-1.5 rounded hover:bg-base-200 transition-colors [[data-theme=light]_&]:bg-base-200"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light mode"
      >
        <.icon name="hero-sun-micro" class="w-4 h-4 text-base-content/70" />
      </button>
      <button
        class="p-1.5 rounded hover:bg-base-200 transition-colors [[data-theme=dark]_&]:bg-base-200"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Dark mode"
      >
        <.icon name="hero-moon-micro" class="w-4 h-4 text-base-content/70" />
      </button>
    </div>
    """
  end
end
