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

// LiveView owns navigation, history and scroll restoration. Keep document patches
// synchronous: capturing the detached incoming view showed the outgoing page
// underneath it during the old View Transition.
let shownPath = location.pathname
let returnTo = null
// How much of a list is shown (rows loaded, sections open), kept in its
// history entry so going back restores it. It is saved whenever it changes,
// not only on leaving: an entry reached by history traversal is left by
// traversal too, when this entry can no longer be written.
const listShown = () => document.querySelector("#guide-products, #product-cards")
// The page on screen is the entry's own page only once LiveView has rendered
// it: during history traversal the old page stays shown under the new URL.
const pageIsEntry = () =>
  document.querySelector("main[data-guide-url]")?.dataset.guideUrl === location.pathname + location.search
const saveList = () => {
  if (!listShown()) return
  const list = document.querySelector("#guide-products")
  history.replaceState({...history.state, guideList: {
    url: location.pathname + location.search,
    loaded: list?.querySelectorAll(".guide-product").length || 0,
    outLoaded: document.querySelectorAll("#guide-cards-out-list .guide-card").length,
    open: [...document.querySelectorAll("main details[open][id]")].map(el => el.id),
  }}, "")
}
// While another page is on its way the old one stays on screen, but the
// history entry is already the new page's: changes then must not be saved.
let leaving = false
let saveQueued = false
const queueSave = () => {
  if (saveQueued || leaving || !pageIsEntry()) return
  saveQueued = true
  requestAnimationFrame(() => { saveQueued = false; if (!leaving && pageIsEntry()) saveList() })
}
new MutationObserver(records => {
  if (records.some(r => r.target.closest?.("#guide-products, #guide-cards-out-list"))) queueSave()
}).observe(document.documentElement, {childList: true, subtree: true})
document.addEventListener("toggle", e => e.target.matches?.("main details[id]") && queueSave(), true)
window.addEventListener("phx:before-navigate", ({detail}) => {
  returnTo = null
  if (!detail.pop && !detail.patch && listShown()) {
    returnTo = location.href
    saveList()
  }
  leaving = true
})
// A new page has joined; a patch keeps the page (and history traversal of a
// patch reports no loading), so it ends the wait at once.
window.addEventListener("phx:page-loading-stop", () => { leaving = false })
window.addEventListener("phx:navigate", ({detail}) => {
  if (detail.patch) leaving = false
  if (!detail.pop && !detail.patch && returnTo) {
    history.replaceState({...history.state, guideReturnTo: returnTo}, "")
  }
  returnTo = null
  // Set pages share HomeLive. Entering or closing a set is a page change,
  // whereas filters retain scroll; history traversal uses LiveView's scroll.
  if (!detail.pop && detail.patch && shownPath !== location.pathname) {
    window.scrollTo({top: 0, behavior: "instant"})
  }
  shownPath = location.pathname
})
// This entry's origin survives forward navigation and reloads. Direct links
// retain the server-rendered fallback (the set for cards, home for products).
document.addEventListener("click", e => {
  if (!history.state?.guideReturnTo || !e.target.closest?.("[data-guide-back]") || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
  e.preventDefault()
  e.stopPropagation()
  history.back()
})

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const connectParams = backpexParams({_csrf_token: csrfToken})
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  // No visitor location here: these params also go into the socket URL, which
  // proxies log. The VisitorLocation hook sends it as an event instead.
  params: () => ({...connectParams(), _guide_list: history.state?.guideList}),
  hooks: {...colocatedHooks, VisitorLocation, LiveToast: createLiveToastHook(), ...BackpexHooks},
  dom: {
    onNodeAdded(el) {
      const saved = history.state?.guideList
      if (el.matches?.("details[id]") && saved?.url === location.pathname + location.search) el.open = saved.open.includes(el.id)
    },
    // A loaded photo stays shown when LiveView patches it (the mark is set in the root layout).
    onBeforeElUpdated(from, to) {
      if (from.hasAttribute("data-loaded") && from.getAttribute("src") === to.getAttribute("src")) to.setAttribute("data-loaded", from.getAttribute("data-loaded"))
    },
  },
})

// A banner's card rests on the sticky search bar. Scrolling down lifts it off
// the bar; once it has gone under the header, it settles back as it comes
// into view again on the way up (site.css).
let lastScrollY = window.scrollY
let cardAway = false
// Whether the card shows below the header; null on a page without one.
const cardInView = () => {
  const card = document.querySelector(".set-chase-art")
  if (card === null) return null
  const headerBottom = document.querySelector(".site-header")?.getBoundingClientRect().bottom ?? 0
  return card.getBoundingClientRect().bottom > headerBottom
}
const markCardLifted = () => {
  const y = window.scrollY
  const inView = cardInView()
  if (inView === false) cardAway = true
  if (y === 0 || (cardAway && inView && y < lastScrollY)) {
    document.documentElement.removeAttribute("data-card-lifted")
    cardAway = false
  } else if (inView !== null && y > lastScrollY) {
    document.documentElement.setAttribute("data-card-lifted", "")
  }
  lastScrollY = y
}
// A new page starts from where its card is: out of view, it is lifted. A
// patch (filters) keeps the state the scrolling gave it.
const resetCardLifted = () => {
  cardAway = cardInView() === false
  document.documentElement.toggleAttribute("data-card-lifted", cardAway)
  lastScrollY = window.scrollY
}
window.addEventListener("scroll", markCardLifted, {passive: true})
window.addEventListener("phx:page-loading-stop", e => e.detail?.kind === "patch" || resetCardLifted())
resetCardLifted()

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
// The search bar's menu opens right under it: opening it first glides the bar
// up to its sticky place, so the menu gets the screen below it.
window.addEventListener("guide:pin-filters", () => {
  const search = document.querySelector(".guide-search")
  if (!search || document.querySelector(".guide-pop[open]")) return
  const lift = search.getBoundingClientRect().top - parseFloat(getComputedStyle(search).insetBlockStart)
  const behavior = matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth"
  if (lift > 0) window.scrollBy({top: lift, behavior})
})
// A menu closes on a click outside it, or on Escape (focus back on its button).
document.addEventListener("click", e => {
  for (const menu of document.querySelectorAll(".guide-pop[open]")) if (!menu.contains(e.target)) menu.open = false
})
document.addEventListener("keydown", e => {
  const menu = e.key === "Escape" && document.querySelector(".guide-pop[open]")
  if (!menu) return
  menu.open = false
  menu.querySelector("summary").focus()
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Search engines read the server-rendered page, which already holds all of it.
// Their renderers keep no WebSocket, so a live connection falls back to
// long-polling, and those polls were 73 % of Googlebot's requests to the site
// (Search Console crawl stats, week to 2026-11-07), crawl budget the pages
// themselves did not get.
const searchCrawler = /Googlebot|Google-InspectionTool|AdsBot-Google|Storebot-Google|bingbot|Applebot|YandexBot|DuckDuckBot|Baiduspider|PetalBot|SeznamBot/i.test(navigator.userAgent)

// connect if there are any LiveViews on the page
initAnalytics()
if (!searchCrawler) liveSocket.connect()

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
