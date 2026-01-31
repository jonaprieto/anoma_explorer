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
    <div class="min-h-screen bg-base-100" id="app-container" phx-hook="SidebarState">
      <!-- Mobile sidebar backdrop -->
      <div id="sidebar-backdrop" class="sidebar-backdrop" onclick="window.closeMobileSidebar()"></div>
      <!-- Sidebar -->
      <aside id="sidebar" class="sidebar">
        <div class="flex flex-col h-full">
          <!-- Logo -->
          <div class="p-6 border-b border-base-300 sidebar-header">
            <div class="flex items-center justify-between">
              <a href="/" class="flex items-center gap-3 sidebar-logo-full">
                <img src="/images/anoma-logo.svg" alt="Anoma" class="w-10 h-10" />
                <div class="sidebar-logo-text">
                  <span class="text-lg font-semibold text-base-content">Anoma</span>
                  <span class="text-lg font-light text-base-content/70">Explorer</span>
                </div>
              </a>
              <a href="/" class="sidebar-logo-icon">
                <img src="/images/anoma-logo.svg" alt="Anoma" class="w-10 h-10" />
              </a>
              <div class="sidebar-theme-toggle">
                <.theme_toggle />
              </div>
            </div>
          </div>
          
    <!-- Navigation -->
          <nav class="flex-1 py-6 overflow-y-auto">
            <div class="px-4 mb-2 sidebar-section-label">
              <span class="text-xs font-medium text-base-content/60 uppercase tracking-wider">
                Overview
              </span>
            </div>

            <.link navigate="/" class={nav_class(@current_path, "/")} title="Dashboard">
              <.icon name="hero-home" class="w-5 h-5" />
              <span>Dashboard</span>
            </.link>

            <div class="px-4 mb-2 mt-4 sidebar-section-label">
              <span class="text-xs font-medium text-base-content/60 uppercase tracking-wider">
                Explorer
              </span>
            </div>

            <.link
              navigate="/transactions"
              class={nav_class(@current_path, "/transactions")}
              title="Transactions"
            >
              <.icon name="hero-document-text" class="w-5 h-5" />
              <span>Transactions</span>
            </.link>

            <.link navigate="/actions" class={nav_class(@current_path, "/actions")} title="Actions">
              <.icon name="hero-bolt" class="w-5 h-5" />
              <span>Actions</span>
            </.link>

            <.link
              navigate="/compliances"
              class={nav_class(@current_path, "/compliances")}
              title="Compliance Units"
            >
              <.icon name="hero-shield-check" class="w-5 h-5" />
              <span>Compliances</span>
            </.link>

            <.link
              navigate="/resources"
              class={nav_class(@current_path, "/resources")}
              title="Resources"
            >
              <.icon name="hero-cube" class="w-5 h-5" />
              <span>Resources</span>
            </.link>

            <div class="px-4 mb-2 mt-4 sidebar-section-label">
              <span class="text-[10px] font-medium text-base-content/40 uppercase tracking-wider">
                Resource Specific
              </span>
            </div>

            <.link
              navigate="/commitments"
              class={nav_class(@current_path, "/commitments")}
              title="Commitment Tree Roots"
            >
              <.icon name="hero-finger-print" class="w-5 h-5" />
              <span>Commitments</span>
            </.link>

            <.link
              navigate="/nullifiers"
              class={nav_class(@current_path, "/nullifiers")}
              title="Nullifiers"
            >
              <.icon name="hero-no-symbol" class="w-5 h-5" />
              <span>Nullifiers</span>
            </.link>

            <.link navigate="/logics" class={nav_class(@current_path, "/logics")} title="Logic Inputs">
              <.icon name="hero-cpu-chip" class="w-5 h-5" />
              <span>Logics</span>
            </.link>

            <div class="px-4 mb-2 mt-4 sidebar-section-label">
              <span class="text-xs font-medium text-base-content/60 uppercase tracking-wider">
                Tools
              </span>
            </div>

            <.link
              navigate="/playground"
              class={nav_class(@current_path, "/playground")}
              title="GraphQL Playground"
            >
              <.icon name="hero-command-line" class="w-5 h-5" />
              <span>Playground</span>
            </.link>

            <div class="px-4 mb-2 mt-4 sidebar-section-label">
              <span class="text-xs font-medium text-base-content/60 uppercase tracking-wider">
                Settings
              </span>
            </div>

            <.link
              navigate="/settings/indexer"
              class={nav_class(@current_path, "/settings/indexer")}
              title="Indexer"
            >
              <.icon name="hero-server-stack" class="w-5 h-5" />
              <span>Indexer</span>
            </.link>

            <%= if show_dev_tools?() do %>
              <.link
                navigate="/settings/api-keys"
                class={nav_class(@current_path, "/settings/api-keys")}
                title="Environment"
              >
                <.icon name="hero-cog-6-tooth" class="w-5 h-5" />
                <span>Environment</span>
              </.link>
            <% end %>

            <div class="px-4 mb-2 mt-4 sidebar-section-label">
              <span class="text-[10px] font-medium text-base-content/40 uppercase tracking-wider">
                Network Info
              </span>
            </div>

            <.link
              navigate="/settings/contracts"
              class={nav_class(@current_path, "/settings/contracts")}
              title="Contracts"
            >
              <.icon name="hero-document-text" class="w-5 h-5" />
              <span>Contracts</span>
            </.link>

            <.link
              navigate="/settings/networks"
              class={nav_class(@current_path, "/settings/networks")}
              title="Networks"
            >
              <.icon name="hero-globe-alt" class="w-5 h-5" />
              <span>Networks</span>
            </.link>
          </nav>
          
    <!-- Footer -->
          <div class="p-4 border-t border-base-300 shrink-0">
            <div class="flex items-center justify-between">
              <div class="text-xs text-base-content/60 sidebar-version">
                v{app_version()}
              </div>
              <button
                id="sidebar-toggle"
                class="sidebar-collapse-btn"
                onclick="window.toggleSidebar()"
                title="Toggle sidebar"
              >
                <span id="collapse-icon"><.icon name="hero-chevron-left" class="w-5 h-5" /></span>
                <span id="expand-icon" class="hidden">
                  <.icon name="hero-chevron-right" class="w-5 h-5" />
                </span>
              </button>
            </div>
          </div>
        </div>
      </aside>
      
    <!-- Main content -->
      <main id="main-content" class="main-content">
        <!-- Search Header -->
        <div class="sticky top-0 z-10 bg-base-100/95 backdrop-blur-sm border-b border-base-200">
          <div class="px-4 sm:px-8 py-3 sm:py-4 flex items-center gap-3">
            <!-- Mobile menu button -->
            <button
              class="mobile-menu-btn"
              onclick="window.toggleSidebar()"
              title="Toggle menu"
            >
              <.icon name="hero-bars-3" class="w-6 h-6" />
            </button>
            <.global_search />
          </div>
        </div>
        <div class="p-4 sm:p-8">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
      <.copy_toast />
    </div>
    """
  end

  defp nav_class(current_path, target_path) do
    base = "sidebar-nav-item"

    is_active =
      cond do
        current_path == target_path -> true
        target_path != "/" and String.starts_with?(current_path, target_path) -> true
        true -> false
      end

    if is_active do
      "#{base} active"
    else
      base
    end
  end

  defp app_version do
    Application.spec(:anoma_explorer, :vsn) |> to_string()
  end

  defp show_dev_tools? do
    Application.get_env(:anoma_explorer, :env) != :prod
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
  Global search component for the header.
  """
  attr :id, :string, default: "global-search"

  def global_search(assigns) do
    ~H"""
    <form id={@id} phx-submit="global_search" class="relative flex items-center w-full">
      <div class="relative w-full group">
        <div class="absolute inset-y-0 left-0 flex items-center pl-3.5 pointer-events-none">
          <.icon
            name="hero-magnifying-glass"
            class="w-5 h-5 text-base-content/40 group-focus-within:text-primary transition-colors"
          />
        </div>
        <input
          type="text"
          name="query"
          id="search-input"
          placeholder="Search transactions by hash..."
          autocomplete="off"
          class="block w-full pl-11 pr-28 py-3 text-sm bg-base-200/50 border border-base-300/50 rounded-xl focus:ring-2 focus:ring-primary/30 focus:border-primary/50 focus:bg-base-100 transition-all duration-200 placeholder:text-base-content/40 shadow-sm hover:border-base-300"
        />
        <div class="absolute inset-y-0 right-0 flex items-center gap-2 pr-3">
          <span class="text-xs text-base-content/40 hidden sm:inline">Transactions</span>
          <kbd class="hidden sm:inline-flex items-center gap-0.5 px-2 py-1 text-xs font-medium text-base-content/50 bg-base-300/70 rounded-md border border-base-content/10">
            <span class="text-[10px]">⌘</span>K
          </kbd>
        </div>
      </div>
    </form>
    """
  end

  @doc """
  Provides dark vs light theme toggle.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5 bg-base-200/60 rounded-full p-0.5 border border-base-300/50">
      <button
        class="p-1.5 rounded-full transition-all duration-200 [[data-theme=light]_&]:bg-base-100 [[data-theme=light]_&]:shadow-sm hover:bg-base-100/50"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light mode"
      >
        <.icon
          name="hero-sun-micro"
          class="w-4 h-4 text-base-content/60 [[data-theme=light]_&]:text-amber-500"
        />
      </button>
      <button
        class="p-1.5 rounded-full transition-all duration-200 [[data-theme=dark]_&]:bg-base-100 [[data-theme=dark]_&]:shadow-sm hover:bg-base-100/50"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Dark mode"
      >
        <.icon
          name="hero-moon-micro"
          class="w-4 h-4 text-base-content/60 [[data-theme=dark]_&]:text-indigo-400"
        />
      </button>
    </div>
    """
  end
end
