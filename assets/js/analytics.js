// Load the hosted SDK without adding a Node build step to the Phoenix release.
// PostHog's CDN bundle exposes window.posthog, also without the snippet's queue.
//
// Events come from three places, all captured here in the visitor's own
// session:
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

// Pages by kind, whatever their region (TcgCheapWeb.Paths): /pl/produkty/… and
// /hu/termekek/… are both products.
const pageType = path => {
  const page = path.replace(/^\/(pl|hu)(?=\/|$)/, "")
  if (page === "" || page === "/") return "home"
  if (page === "/karty" || page === "/kartyak") return "cards"
  if (/^\/(produkty|termekek)\//.test(page)) return "product"
  if (page === "/ile-kosztuje-booster-pokemon") return "booster_prices"
  if (/^\/(rozszerzenia\/[^/]+\/karty|szettek\/[^/]+\/kartyak)\//.test(page)) return "card"
  if (/^\/(rozszerzenia|szettek)\//.test(page)) return "set"
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
  // The site region (which shops and currency) and language (the text) are
  // separate. `market`, not `region`: events already use `region` for a
  // product's edition (en, ja, …).
  market: document.documentElement.dataset.region || null,
  language: document.documentElement.lang,
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

// A phone keyboard covers the bottom of the screen without resizing the page
// (iOS Safari, Chrome on Android), so while the form is open site.css keeps it
// within the part the keyboard leaves visible.
const keepAboveKeyboard = form => {
  const viewport = window.visualViewport
  if (!viewport) return

  const fit = () => {
    const covered = window.innerHeight - viewport.offsetTop - viewport.height
    form.style.setProperty("--report-keyboard", `${Math.max(0, Math.round(covered))}px`)
    form.style.setProperty("--report-room", `${Math.round(viewport.height)}px`)
    form.style.setProperty("--report-top", `${Math.round(viewport.offsetTop)}px`)
  }
  form.addEventListener("toggle", event => {
    const listen = event.newState === "open" ? "addEventListener" : "removeEventListener"
    viewport[listen]("resize", fit)
    viewport[listen]("scroll", fit)
    if (event.newState === "open") fit()
  })
}

// Each report opens a new ticket in PostHog's support inbox, through the
// conversations API; app.css hides PostHog's own chat widget.
const initReportForm = () => {
  const report = document.getElementById("report")
  if (!report) return

  const form = document.getElementById("report-panel")
  const status = document.getElementById("report-status")
  const submit = document.getElementById("report-submit")
  report.hidden = false
  keepAboveKeyboard(form)
  form.addEventListener("submit", async event => {
    event.preventDefault()
    const message = form.elements.message.value.trim()
    const email = form.elements.email.value.trim()
    if (!message) return

    status.textContent = report.dataset.sending
    submit.disabled = true
    try {
      if (!posthog.conversations.isAvailable()) throw new Error("conversations unavailable")
      await posthog.conversations.sendMessage(message, email ? {email} : undefined, true)
      form.reset()
      status.textContent = report.dataset.sent
    } catch {
      status.textContent = report.dataset.failed
    } finally {
      submit.disabled = false
    }
  })
}

// Cookies stay on until the visitor rejects them. Rejecting stops capture,
// drops PostHog's cookie and removes the report form with its session.
const initCookieNotice = () => {
  const notice = document.getElementById("cookie-notice")
  if (!notice || posthog.get_explicit_consent_status() !== "pending") return

  notice.hidden = false
  notice.addEventListener("click", event => {
    const button = event.target.closest("button")
    if (!button) return

    if (button.id === "cookie-notice-reject") {
      posthog.opt_out_capturing()
      posthog.set_config({disable_conversations: true})
      posthog.conversations.reset()
      document.getElementById("report-panel")?.hidePopover()
      const report = document.getElementById("report")
      if (report) report.hidden = true
    } else {
      posthog.opt_in_capturing({captureEventName: false})
    }
    notice.hidden = true
  })
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
    // properties (URL, referrer, UTM, clicks). The audience is in the EU, so
    // browsers sending DNT or GPC are counted too. The project's remote config
    // turns on conversations (support tickets) and loads their script; PostHog
    // refuses them in cookieless mode, so the SDK keeps its default persistence.
    window.posthog.init(config.content, {
      api_host: window.location.origin,
      rewriteRequestPath: url => {
        const entry = Object.entries(paths).find(([path]) => url.pathname.startsWith(path))
        if (entry) url.pathname = entry[1] + url.pathname.slice(entry[0].length)
        return url
      },
      defaults: "2026-01-30",
      person_profiles: "never",
      autocapture: true,
      capture_pageview: false,
      capture_pageleave: true,
      disable_session_recording: true,
      disable_surveys: true,
      advanced_disable_feature_flags: true,
      opt_out_persistence_by_default: true,
      respect_dnt: false,
      loaded: instance => {
        posthog = instance
        // Remote config enables conversations after init, so this still applies.
        // Capture is a no-op once the visitor has opted out.
        if (posthog.has_opted_out_capturing()) posthog.set_config({disable_conversations: true})
        else initReportForm()
        initCookieNotice()
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
