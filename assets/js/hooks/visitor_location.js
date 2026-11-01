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
    this.status = this.el.querySelector("#visitor-location-status")
    this.handleEvent("location", ({location}) => {
      try {
        if (location) localStorage.setItem(STORAGE_KEY, JSON.stringify(location))
        else localStorage.removeItem(STORAGE_KEY)
      } catch {}
      this.el.querySelector("form")?.reset()
      this.say("")
      this.el.open = false
    })
    this.el.addEventListener("click", event => {
      if (event.target.closest("#visitor-location-device")) this.locate()
    })
  },

  locate() {
    if (!("geolocation" in navigator)) {
      this.say("Ta przeglądarka nie podaje lokalizacji. Wpisz miejscowość.")
      return
    }
    this.say("Ustalam lokalizację…")
    navigator.geolocation.getCurrentPosition(
      ({coords}) => {
        const location = {lat: round(coords.latitude), lon: round(coords.longitude)}
        this.pushEvent("location-coords", {location}, () => this.say(""))
      },
      () => this.say("Nie udało się ustalić lokalizacji. Wpisz miejscowość."),
      {enableHighAccuracy: false, maximumAge: 600000, timeout: 10000},
    )
  },

  say(text) {
    this.status.textContent = text
  },
}

export default VisitorLocation
