// Load the hosted SDK without adding a Node build step to the Phoenix release.
// PostHog's CDN bundle exposes window.posthog, also without the snippet's queue.
//
// Events come from three places, all captured here in the visitor's own
// (cookieless, in-browser) session:
//   * the LiveViews' `TcgCheapWeb.Analytics.track/3`, pushed as "track";
//   * clicks on elements with `data-track="event"`, whose `data-track-*`
//     attributes (and those of the closest `[data-track-context]`) become
//     properties, plus `position` inside a `[data-track-positions]` list;
//   * `track/2` from hooks (colocated ones dispatch "phx:track" themselves).
const SEARCH_SETTLE_MS = 1500

// Until the SDK loads (or forever, without PostHog configured) events wait
// here with the time they happened.
let posthog
let queue = null
let pendingSearch = null
// Whether this page sent a search since the field was last cleared.
let searchSent = false

const pageType = path => {
  if (path === "/") return "home"
  if (path.startsWith("/produkty/")) return "product"
  if (path.startsWith("/cards/")) return "card"
  if (path === "/trade") return "trade"
  return "other"
}

// Whether a location is set, never which: the hook keeps it in localStorage.
const hasLocation = () => {
  try {
    return Boolean(localStorage.getItem("tcg:location"))
  } catch {
    return false
  }
}

// Read when the event happens: a queued or held one is captured later,
// possibly after a navigation.
const pageContext = () => ({
  $current_url: window.location.href,
  $pathname: window.location.pathname,
  page_type: pageType(window.location.pathname),
  locale: document.documentElement.lang,
  has_location: hasLocation(),
})

const send = (event, properties, options) => {
  if (posthog) posthog.capture(event, properties, options)
  else queue?.push([event, properties, options])
}

const dropSearch = () => {
  clearTimeout(pendingSearch?.timer)
  pendingSearch = null
}

// Leaving the page sends with a beacon, which outlives it.
const flushSearch = ({leaving = false} = {}) => {
  if (!pendingSearch) return
  const {properties, timestamp} = pendingSearch
  dropSearch()
  searchSent = true
  send("search_performed", properties, leaving ? {timestamp, transport: "sendBeacon"} : {timestamp})
}

// Search runs as the visitor types, so only the query they stop at counts:
// one that settles, or the last one before they act or leave. Clearing only
// a query that never settled is no event at all.
export function track(event, properties = {}) {
  if (!queue && !posthog) return
  properties = {...pageContext(), ...properties}
  const timestamp = new Date()

  if (event === "search_performed") {
    dropSearch()
    pendingSearch = {properties, timestamp, timer: setTimeout(() => flushSearch(), SEARCH_SETTLE_MS)}
  } else if (event === "search_cleared" && pendingSearch && !searchSent) {
    dropSearch()
  } else if (event === "search_cleared") {
    dropSearch()
    searchSent = false
    send(event, properties, {timestamp})
  } else {
    flushSearch()
    if (event === "$pageview") searchSent = false
    send(event, properties, {timestamp})
  }
}

const propertyName = key =>
  key.slice("track".length).replace(/^./, c => c.toLowerCase()).replace(/[A-Z]/g, c => `_${c.toLowerCase()}`)

const propertyValue = value => {
  if (value === "true" || value === "false") return value === "true"
  if (/^-?\d+(\.\d+)?$/.test(value)) return Number(value)
  return value === "" ? null : value
}

const dataProperties = el => {
  const properties = {}
  for (const [key, value] of Object.entries(el?.dataset || {})) {
    if (key.startsWith("track") && !["track", "trackContext", "trackPositions"].includes(key))
      properties[propertyName(key)] = propertyValue(value)
  }
  return properties
}

// A click or middle click on a tracked element.
const captureClick = event => {
  if (event.type === "auxclick" && event.button !== 1) return
  const el = event.target.closest?.("[data-track]")
  if (!el) return
  // A toggle counts when it opens; this runs before the click changes it.
  if (el.getAttribute("aria-expanded") === "true" || (el.tagName === "SUMMARY" && el.parentElement.open)) return

  const properties = {...dataProperties(el.closest("[data-track-context]")), ...dataProperties(el)}
  const item = el.closest("[data-track-positions] > li")
  if (item) {
    const items = [...item.parentElement.children].filter(li => !li.classList.contains("guide-empty"))
    properties.position = items.indexOf(item) + 1
  }
  if (el.href && el.host !== window.location.host) properties.offer_url = el.href
  track(el.dataset.track, properties)
}

export default function initAnalytics() {
  const config = document.querySelector("meta[name='posthog']")
  if (!config) return
  queue = []

  let lastPath
  const capturePageview = () => {
    const path = window.location.pathname
    if (path === "/admin" || path.startsWith("/admin/") || path === lastPath) return

    lastPath = path
    track("$pageview")
  }

  capturePageview()
  // LiveView emits this for initial joins, patches and navigations.
  // Dedupe by pathname so filters, forms and reconnects aren't pageviews.
  window.addEventListener("phx:page-loading-stop", capturePageview)
  window.addEventListener("phx:track", ({detail}) => track(detail.event, detail.properties))
  document.addEventListener("click", captureClick)
  document.addEventListener("auxclick", captureClick)
  window.addEventListener("pagehide", () => flushSearch({leaving: true}))
  document.addEventListener("visibilitychange", () => document.hidden && flushSearch({leaving: true}))

  const paths = JSON.parse(config.dataset.proxyPaths)
  const script = document.createElement("script")
  script.src = `${paths["/static/"]}array.js`
  script.async = true
  script.crossOrigin = "anonymous"
  script.referrerPolicy = "no-referrer"
  script.onload = () => {
    // The site has no accounts or personal data, so events keep the SDK's full
    // properties (URL, referrer, UTM, clicks). Cookieless in-memory tracking
    // without person profiles needs no consent banner. The audience is in the
    // EU, so browsers sending DNT or GPC are counted too.
    window.posthog.init(config.content, {
      api_host: window.location.origin,
      rewriteRequestPath: url => {
        const entry = Object.entries(paths).find(([path]) => url.pathname.startsWith(path))
        if (entry) url.pathname = entry[1] + url.pathname.slice(entry[0].length)
        return url
      },
      defaults: "2026-01-30",
      cookieless_mode: "always",
      persistence: "memory",
      person_profiles: "never",
      autocapture: true,
      capture_pageview: false,
      capture_pageleave: true,
      disable_session_recording: true,
      disable_surveys: true,
      advanced_disable_flags: true,
      disable_external_dependency_loading: true,
      respect_dnt: false,
      loaded: instance => {
        posthog = instance
        for (const [event, properties, options] of queue) posthog.capture(event, properties, options)
        queue = null
      },
    })
  }
  // Defer the SDK until after load and an idle slot (or the bounded timeout).
  const load = () => document.head.appendChild(script)
  const whenIdle = () =>
    "requestIdleCallback" in window ? requestIdleCallback(load, {timeout: 5000}) : setTimeout(load, 2000)
  if (document.readyState === "complete") whenIdle()
  else window.addEventListener("load", whenIdle, {once: true})
}
