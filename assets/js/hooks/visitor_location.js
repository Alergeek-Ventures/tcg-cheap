// The visitor's location is kept only in this browser: coordinates rounded to
// 0.01° (about 1 km) and a town name, sent to the LiveView when it connects.
// The server pushes "location" when the visitor sets or clears it.
const STORAGE_KEY = "tcg:location"

export function storedLocation() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY)) ?? undefined
  } catch {
    return undefined
  }
}

const round = degrees => Math.round(degrees * 100) / 100

const VisitorLocation = {
  mounted() {
    this.summary = this.el.querySelector("summary")
    this.handleEvent("location", ({location}) => {
      try {
        if (location) localStorage.setItem(STORAGE_KEY, JSON.stringify(location))
        else localStorage.removeItem(STORAGE_KEY)
      } catch {}
      this.el.querySelector("form")?.reset()
      this.say("")
      this.close()
      this.announce(location
        ? `Lokalizacja: ${location.label}. Pokazujemy odległości do odbioru osobistego.`
        : "Lokalizacja usunięta.")
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

  destroyed() {
    document.removeEventListener("pointerdown", this.onPointerDown)
    document.removeEventListener("keydown", this.onKeyDown)
  },

  close() {
    this.el.open = false
    this.summary.focus()
  },

  locate() {
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
    this.say("Ustalam lokalizację…")
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
        this.fail()
      },
      {enableHighAccuracy: false, maximumAge: 600000, timeout: 10000},
    )
  },

  fail() {
    this.say("Przeglądarka nie udostępniła lokalizacji. Wpisz miejscowość poniżej.", true)
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
