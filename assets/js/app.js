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
import {hooks as colocatedHooks} from "phoenix-colocated/tcg_cheap"
import {Hooks as BackpexHooks, backpexParams} from "backpex"
import {createLiveToastHook} from "live_toast"
import VisitorLocation from "./hooks/visitor_location"
import initAnalytics from "./analytics"
import topbar from "../vendor/topbar"

(() => {
  const systemTheme = () => matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
  const setTheme = theme => {
    if (theme === "system") {
      localStorage.removeItem("phx:theme")
      document.documentElement.setAttribute("data-theme", systemTheme())
      document.documentElement.setAttribute("data-theme-source", "system")
    } else {
      localStorage.setItem("phx:theme", theme)
      document.documentElement.setAttribute("data-theme", theme)
      document.documentElement.setAttribute("data-theme-source", "user")
    }
  }
  if (!document.documentElement.hasAttribute("data-theme")) setTheme(localStorage.getItem("phx:theme") || "system")
  window.addEventListener("storage", e => e.key === "phx:theme" && setTheme(e.newValue || "system"))
  window.addEventListener("phx:set-theme", e => setTheme(e.target.dataset.phxTheme))
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
    if (document.documentElement.getAttribute("data-theme-source") === "system") document.documentElement.setAttribute("data-theme", systemTheme())
  })
})()

// Page transitions: LiveView navigations (links, back and forward) cross-fade
// as a view transition, and the product photo moves between its row in the
// list and the product page. Other patches (search, filters, live updates)
// apply at once.
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)")
// Names the photo of the list row linking to `path`, the one that moves.
const nameRowPhoto = path => {
  document.querySelectorAll(".guide-product-image").forEach(el => el.style.viewTransitionName = "")
  const photo = path && document.querySelector(`.guide-product-link[href="${CSS.escape(path)}"] .product-image`)
  if (photo) photo.style.viewTransitionName = "product-photo"
}
let shownPath = location.pathname
let navigatingFrom = null
// Where LiveView scrolls the page it navigates to, a frame after the patch:
// the top, or on back and forward where that page was left.
let landingScroll = null
// Whether the page shown was opened from the list in this tab.
let cameFromList = false
// Patches arriving while a transition waits to apply its own, applied in order after it.
let heldPatches = null

// A link navigation announces itself before the new page arrives; back and
// forward only after the address has already changed.
window.addEventListener("phx:page-loading-start", ({detail}) => {
  if (detail.kind === "redirect") navigatingFrom = location.pathname
})
window.addEventListener("phx:navigate", ({detail}) => {
  if (detail.pop && !detail.patch) {
    navigatingFrom = shownPath
    nameRowPhoto(location.pathname)
  }
  if (!detail.patch) landingScroll = detail.pop ? history.state?.scroll : !location.hash && 0
  // Set pages share HomeLive, so their path changes are patches. Unlike a
  // filter change, entering a set must show its title at the top.
  if (detail.patch && shownPath !== location.pathname && location.pathname.startsWith("/rozszerzenia/")) {
    window.scrollTo({top: 0, behavior: "instant"})
  }
  cameFromList = shownPath === "/" && location.pathname !== "/"
  shownPath = location.pathname
})
// Back to the list from a product opened there goes back in history, so the
// list returns with its search, filters and scroll. LiveView's own link
// handler listens on window, after this one.
document.addEventListener("click", e => {
  if (!cameFromList || !e.target.closest?.("#product-back") || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
  e.preventDefault()
  e.stopPropagation()
  history.back()
})
window.addEventListener("phx:page-loading-stop", ({detail}) => {
  if (detail.kind === "redirect") navigatingFrom = null
})
document.addEventListener("click", e => nameRowPhoto(e.target.closest?.(".guide-product-link")?.getAttribute("href")), true)

const onDocumentPatch = start => {
  if (heldPatches) return heldPatches.push(start)
  const from = navigatingFrom
  if (!from || !document.startViewTransition || reduceMotion.matches) return start()

  navigatingFrom = null
  heldPatches = []
  document.startViewTransition(() => {
    try {
      start()
      // The new page is captured right after this, so it scrolls now for the
      // photo to land where it shows.
      if (typeof landingScroll === "number") window.scrollTo(0, landingScroll)
      landingScroll = null
      // Back on the list, the photo returns to its product's row.
      nameRowPhoto(from)
      while (heldPatches.length) heldPatches.shift()()
    } finally {
      heldPatches = null
    }
  }).finished.finally(() => nameRowPhoto(null))
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  // No visitor location here: these params also go into the socket URL, which
  // proxies log. The VisitorLocation hook sends it as an event instead.
  params: backpexParams({_csrf_token: csrfToken}),
  hooks: {...colocatedHooks, VisitorLocation, LiveToast: createLiveToastHook(), ...BackpexHooks},
  dom: {
    onDocumentPatch,
    // A loaded photo stays shown when LiveView patches it (the mark is set in the root layout).
    onBeforeElUpdated(from, to) {
      if (from.hasAttribute("data-loaded") && from.getAttribute("src") === to.getAttribute("src")) to.setAttribute("data-loaded", from.getAttribute("data-loaded"))
    },
  },
})

// Bring an element to the top once the layout above it has changed, e.g. the
// results after the filter panel folds away on a phone.
window.addEventListener("guide:reveal", e => e.target.scrollIntoView({block: "start"}))
// Links to a section of the same page glide to it instead of jumping, opening
// the folded group they point into (a jump where motion is reduced). Focus
// moves along, so the keyboard carries on from the section as after a jump.
// The section stays framed (site.css) until the page scrolls again after the glide.
const unframeOnScroll = target => {
  // Settle the unframed style first, so the frame fades in.
  getComputedStyle(target).outlineColor
  target.dataset.jumped = ""
  const unframe = () => delete target.dataset.jumped
  const afterGlide = () => window.addEventListener("scroll", unframe, {once: true, passive: true})
  if (!("onscrollend" in window)) return setTimeout(afterGlide, 1000)
  window.addEventListener("scrollend", afterGlide, {once: true})
  // A section already in place does not glide, so no scrollend comes.
  const start = window.scrollY
  requestAnimationFrame(() => requestAnimationFrame(() => {
    if (window.scrollY !== start) return
    window.removeEventListener("scrollend", afterGlide)
    afterGlide()
  }))
}
document.addEventListener("click", e => {
  const link = e.target.closest?.('a[href^="#"]')
  if (!link || e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
  const target = link.hash && document.getElementById(decodeURIComponent(link.hash.slice(1)))
  if (!target || matchMedia("(prefers-reduced-motion: reduce)").matches) return
  e.preventDefault()
  const group = target.closest("details")
  if (group) group.open = true
  if (!target.matches("a[href], button, input, select, textarea, summary, [tabindex]")) target.setAttribute("tabindex", "-1")
  target.focus({preventScroll: true})
  unframeOnScroll(target)
  target.scrollIntoView({behavior: "smooth", block: "start"})
  history.pushState(history.state, "", link.hash)
})
// Phone filters open as a panel right under the search bar, the page first scrolled
// to bring the bar up to its sticky place so the panel gets the screen below it
// (measured again when the screen turns or resizes while the panel is open).
const pinFilters = ({type}) => {
  const search = document.querySelector(".guide-search")
  if (!search) return
  if (type === "guide:pin-filters" && !document.querySelector(".guide-filters-open")) {
    const lift = search.getBoundingClientRect().top - parseFloat(getComputedStyle(search).insetBlockStart)
    if (lift > 0) window.scrollBy({top: lift, behavior: "instant"})
  }
  document.documentElement.style.setProperty("--guide-filters-top", `${Math.round(search.getBoundingClientRect().bottom)}px`)
}
window.addEventListener("guide:pin-filters", pinFilters)
window.addEventListener("resize", e => { if (document.querySelector(".guide-filters-open")) pinFilters(e) })

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
initAnalytics()
liveSocket.connect()

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
