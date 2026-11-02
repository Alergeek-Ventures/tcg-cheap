// Load the hosted SDK without adding a Node build step to the Phoenix release.
// PostHog's CDN bundle exposes window.posthog, also without the snippet's queue.
export default function initAnalytics() {
  const config = document.querySelector("meta[name='posthog']")
  if (!config || navigator.doNotTrack === "1" || navigator.globalPrivacyControl) return

  const paths = JSON.parse(config.dataset.proxyPaths)
  const script = document.createElement("script")
  script.src = `${paths["/static/"]}array.js`
  script.async = true
  script.crossOrigin = "anonymous"
  script.referrerPolicy = "no-referrer"
  script.onload = () => {
    const posthog = window.posthog
    let lastPath

    const capturePageview = () => {
      const path = window.location.pathname
      if (path === "/admin" || path.startsWith("/admin/") || path === lastPath) return

      lastPath = path
      posthog.capture("$pageview")
    }

    // A "Do sklepu" link opened with a click or a middle click.
    const captureShopClick = event => {
      if (event.type === "auxclick" && event.button !== 1) return
      const link = event.target.closest?.("a.offer-link[data-shop]")
      if (!link) return

      posthog.capture("shop_link_clicked", {
        shop: link.dataset.shop,
        in_stock: link.dataset.inStock === "true",
        offer_url: link.href,
      })
    }

    // The site has no accounts or personal data, so events keep the SDK's full
    // properties (URL, referrer, UTM, clicks). Cookieless in-memory tracking
    // without person profiles needs no consent banner.
    posthog.init(config.content, {
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
      respect_dnt: true,
      loaded: () => {
        capturePageview()
        // LiveView emits this for initial joins, patches and navigations.
        // Dedupe by pathname so filters, forms and reconnects aren't pageviews.
        window.addEventListener("phx:page-loading-stop", capturePageview)
        document.addEventListener("click", captureShopClick)
        document.addEventListener("auxclick", captureShopClick)
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
