// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// Custom hooks
const Hooks = {
  CtrlEnterSubmit: {
    mounted() {
      this.el.addEventListener("keydown", (e) => {
        if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
          e.preventDefault()
          this.el.form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
        }
      })
    }
  },

  SyntaxHighlight: {
    mounted() {
      this.highlight()
    },
    updated() {
      this.highlight()
    },
    highlight() {
      if (window.hljs) {
        const codeBlock = this.el.querySelector("code")
        if (codeBlock) {
          codeBlock.removeAttribute("data-highlighted")
          window.hljs.highlightElement(codeBlock)
        }
      }
    }
  },

  GraphQLEditor: {
    mounted() {
      const textarea = this.el.querySelector("textarea")
      const highlightPre = this.el.querySelector(".highlight-layer")

      if (textarea && highlightPre) {
        this.syncHighlight(textarea, highlightPre)

        textarea.addEventListener("input", () => {
          this.syncHighlight(textarea, highlightPre)
        })

        textarea.addEventListener("scroll", () => {
          highlightPre.scrollTop = textarea.scrollTop
          highlightPre.scrollLeft = textarea.scrollLeft
        })
      }

      textarea.addEventListener("keydown", (e) => {
        if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
          e.preventDefault()
          const form = document.getElementById("query-form")
          if (form) {
            form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
          }
        }
      })
    },
    updated() {
      const textarea = this.el.querySelector("textarea")
      const highlightPre = this.el.querySelector(".highlight-layer")
      if (textarea && highlightPre) {
        this.syncHighlight(textarea, highlightPre)
      }
    },
    syncHighlight(textarea, highlightPre) {
      const code = highlightPre.querySelector("code")
      if (code && window.hljs) {
        code.textContent = textarea.value + "\n"
        code.removeAttribute("data-highlighted")
        window.hljs.highlightElement(code)
      }
    }
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Sidebar state persistence and toggle
function restoreSidebarState() {
  const isCollapsed = localStorage.getItem("sidebar-collapsed") === "true"
  const collapseIcon = document.getElementById("collapse-icon")
  const expandIcon = document.getElementById("expand-icon")

  if (isCollapsed) {
    document.getElementById("sidebar")?.classList.add("collapsed")
    document.getElementById("main-content")?.classList.add("sidebar-collapsed")
    // Show expand icon (right chevron) when collapsed
    collapseIcon?.classList.add("hidden")
    expandIcon?.classList.remove("hidden")
  } else {
    // Show collapse icon (left chevron) when expanded
    collapseIcon?.classList.remove("hidden")
    expandIcon?.classList.add("hidden")
  }
}

// Toggle sidebar function - called from onclick handler
window.toggleSidebar = function() {
  const sidebar = document.getElementById("sidebar")
  const mainContent = document.getElementById("main-content")
  const collapseIcon = document.getElementById("collapse-icon")
  const expandIcon = document.getElementById("expand-icon")

  sidebar?.classList.toggle("collapsed")
  mainContent?.classList.toggle("sidebar-collapsed")
  collapseIcon?.classList.toggle("hidden")
  expandIcon?.classList.toggle("hidden")

  // Persist state
  const isNowCollapsed = sidebar?.classList.contains("collapsed")
  localStorage.setItem("sidebar-collapsed", isNowCollapsed ? "true" : "false")
}

// Restore on initial page load
document.addEventListener("DOMContentLoaded", restoreSidebarState)

// Restore on LiveView navigation
window.addEventListener("phx:page-loading-stop", restoreSidebarState)

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// Handle copy to clipboard events
window.addEventListener("phx:copy", (event) => {
  const text = event.detail.text
  if (navigator.clipboard) {
    navigator.clipboard.writeText(text)
  }
})

// Admin session management - store/clear authorization timestamp
window.addEventListener("phx:admin_store_session", (event) => {
  sessionStorage.setItem('admin_authorized_at', event.detail.authorized_at)
})

window.addEventListener("phx:admin_clear_session", () => {
  sessionStorage.removeItem('admin_authorized_at')
})

// Global search keyboard shortcut (⌘K / Ctrl+K)
document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "k") {
    e.preventDefault()
    const searchInput = document.getElementById("search-input")
    if (searchInput) {
      searchInput.focus()
      searchInput.select()
    }
  }
})

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

