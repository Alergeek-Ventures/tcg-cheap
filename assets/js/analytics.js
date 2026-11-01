// Load the hosted SDK without adding a Node build step to the Phoenix release.
// PostHog's CDN bundle exposes window.posthog, also without the snippet's queue.
export default function initAnalytics() {
  const config = document.querySelector("meta[name='posthog']")
  if (!config || navigator.doNotTrack === "1" || navigator.globalPrivacyControl) return

  const script = document.createElement("script")
  script.src = `${config.dataset.assetHost}/static/array.js`
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
      posthog.capture("$pageview", {
        $current_url: window.location.origin + path,
        $pathname: path,
      })
    }

    posthog.init(config.content, {
      api_host: config.dataset.apiHost,
      defaults: "2026-01-30",
      cookieless_mode: "always",
      persistence: "memory",
      person_profiles: "never",
      autocapture: false,
      capture_pageview: false,
      capture_pageleave: false,
      capture_performance: false,
      capture_exceptions: false,
      capture_dead_clicks: false,
      disable_session_recording: true,
      disable_surveys: true,
      advanced_disable_flags: true,
      disable_external_dependency_loading: true,
      respect_dnt: true,
      save_campaign_params: false,
      save_referrer: false,
      // Keep only pageview metadata: SDK defaults can otherwise include the
      // full initial URL/referrer, search terms, location or shared trade data.
      before_send: event => {
        if (event.event !== "$pageview") return null

        const allowed = [
          "$current_url", "$pathname", "$host", "$browser", "$browser_version",
          "$os", "$os_version", "$device_type", "$screen_height", "$screen_width",
          "$viewport_height", "$viewport_width", "$lib", "$lib_version",
          "token", "distinct_id", "$cookieless_mode", "$insert_id", "$time",
          "$session_id", "$window_id", "$process_person_profile",
          "$timezone", "$timezone_offset",
        ]
        event.properties = Object.fromEntries(
          Object.entries(event.properties).filter(([key]) => allowed.includes(key))
        )
        return event
      },
      loaded: () => {
        capturePageview()
        // LiveView emits this for initial joins, patches and navigations.
        // Dedupe by pathname so filters, forms and reconnects aren't pageviews.
        window.addEventListener("phx:page-loading-stop", capturePageview)
      },
    })
  }
  document.head.appendChild(script)
}
