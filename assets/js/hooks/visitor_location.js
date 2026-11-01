// The visitor's location is kept only in this browser: coordinates rounded to
// 0.01° (about 1 km) and a town name, sent to the LiveView as an event once it
// connects (never in the socket URL). The server pushes "location" when the
// visitor sets or clears it.
const STORAGE_KEY = "tcg:location"
// Set once the device location was asked for on entry in this browser session.
const ASKED_KEY = "tcg:location-asked"

function storedLocation() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY))
  } catch {
    return null
  }
}

const round = degrees => Math.round(degrees * 100) / 100

const VisitorLocation = {
  mounted() {
    this.summary = this.el.querySelector("summary")
    this.restore()
    this.askOnEntry()
    this.handleEvent("location", ({location}) => {
      try {
        if (location) localStorage.setItem(STORAGE_KEY, JSON.stringify(location))
        else localStorage.removeItem(STORAGE_KEY)
      } catch {}
      if (location) this.hideInvite()
      this.el.querySelector("form")?.reset()
      this.say("")
      // Set on entry the panel is closed; leave the focus where it is.
      if (this.el.open) this.close()
      this.announce(location
        ? this.el.dataset.located.replace("%{town}", location.label)
        : this.el.dataset.cleared)
    })
    this.el.addEventListener("click", event => {
      if (event.target.closest("#visitor-location-device")) this.locate()
    })
    // Opened from elsewhere on the page, e.g. "Podaj miejscowość" by the verdict.
    this.el.addEventListener("location:open", () => {
      this.el.open = true
      this.el.scrollIntoView({block: "nearest"})
      this.el.querySelector("#visitor-location-town")?.focus()
    })
    this.onPointerDown = event => {
      if (this.el.open && !this.el.contains(event.target)) this.el.open = false
    }
    this.onKeyDown = event => {
      if (event.key === "Escape" && this.el.open) this.close()
    }
    document.addEventListener("pointerdown", this.onPointerDown)
    document.addEventListener("keydown", this.onKeyDown)
  },

  // A reconnect starts a new LiveView process without the location.
  reconnected() {
    this.restore()
  },

  // Always sent, also without a stored location: the page shows its location
  // parts only after this answer, so they never flash the wrong state.
  restore() {
    this.pushEvent("location-restore", {location: storedLocation()})
  },

  // Without a remembered location, explain once per browser session (not on
  // every page) why we ask; the browser's own prompt follows only "Zgadzam się".
  // An earlier grant needs no prompt, a refusal is respected.
  async askOnEntry() {
    if (storedLocation() || !("geolocation" in navigator)) return
    let state
    try {
      if (sessionStorage.getItem(ASKED_KEY)) return
      sessionStorage.setItem(ASKED_KEY, "1")
      ;({state} = await navigator.permissions.query({name: "geolocation"}))
    } catch {}
    if (!this.el.isConnected || storedLocation()) return
    if (state === "denied") return
    if (state === "granted") return this.locate({quiet: true})
    this.invite = document.getElementById("visitor-location-invite")
    if (!this.invite) return
    // Through this.js() so LiveView patches keep it shown or hidden.
    this.js().removeAttribute(this.invite, "hidden")
    this.onLater = () => this.hideInvite()
    this.onAllow = () => {
      this.hideInvite()
      this.el.open = true
      this.locate()
    }
    this.invite.querySelector("#visitor-location-later").addEventListener("click", this.onLater)
    this.invite.querySelector("#visitor-location-allow").addEventListener("click", this.onAllow)
  },

  hideInvite() {
    if (!this.invite) return
    if (this.invite.contains(document.activeElement)) this.summary.focus()
    this.js().setAttribute(this.invite, "hidden", "")
  },

  destroyed() {
    document.removeEventListener("pointerdown", this.onPointerDown)
    document.removeEventListener("keydown", this.onKeyDown)
    this.invite?.querySelector("#visitor-location-later").removeEventListener("click", this.onLater)
    this.invite?.querySelector("#visitor-location-allow").removeEventListener("click", this.onAllow)
  },

  close() {
    this.el.open = false
    this.summary.focus()
  },

  // Quiet when asked on entry: a refusal shows no error and moves no focus.
  locate({quiet = false} = {}) {
    if (!("geolocation" in navigator)) {
      this.fail()
      return
    }
    const button = this.el.querySelector("#visitor-location-device")
    // Through this.js() so LiveView patches keep the attributes.
    const busy = on => {
      for (const [attr, value] of [["disabled", ""], ["aria-busy", "true"]]) {
        if (on) this.js().setAttribute(button, attr, value)
        else this.js().removeAttribute(button, attr)
      }
    }
    busy(true)
    if (!quiet) this.say(this.el.dataset.locating)
    navigator.geolocation.getCurrentPosition(
      ({coords}) => {
        const location = {lat: round(coords.latitude), lon: round(coords.longitude)}
        this.pushEvent("location-coords", {location}, () => {
          busy(false)
          this.say("")
        })
      },
      () => {
        busy(false)
        if (!quiet) this.fail()
      },
      {enableHighAccuracy: false, maximumAge: 600000, timeout: 10000},
    )
  },

  fail() {
    this.say(this.el.dataset.failed, true)
    this.el.querySelector("#visitor-location-town")?.focus()
  },

  // The status element is ignored by LiveView patches, so its content is ours.
  say(text, error = false) {
    const status = this.el.querySelector("#visitor-location-status")
    const line = document.createElement("span")
    line.textContent = text
    if (error) line.className = "visitor-location-error"
    status.replaceChildren(...(text ? [line] : []))
  },

  announce(text) {
    const region = document.getElementById("visitor-location-announce")
    if (region) region.textContent = text
  },
}

export default VisitorLocation
