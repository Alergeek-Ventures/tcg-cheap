const TradeShare = {
  mounted() {
    this.copyInFlight = false
    this.isDestroyed = false
    this.copy = async () => {
      if (this.copyInFlight || this.isDestroyed) return
      this.copyInFlight = true
      let copied = false
      let path

      try {
        path = this.el?.dataset?.tradePath
        if (typeof path !== "string" || !path.startsWith("/trade")) return
        const value = new URL(path, window.location.origin).href

        try {
          if (navigator.clipboard?.writeText) {
            await navigator.clipboard.writeText(value)
            copied = true
          }
        } catch (_error) {}

        if (!copied) {
          const textarea = document.createElement("textarea")
          const previousActiveElement = document.activeElement
          textarea.value = value
          textarea.setAttribute("readonly", "")
          textarea.setAttribute("aria-hidden", "true")
          textarea.style.position = "fixed"
          textarea.style.opacity = "0"
          try {
            document.body.appendChild(textarea)
            textarea.select()
            copied = document.execCommand("copy")
          } catch (_error) {
            copied = false
          } finally {
            textarea.remove()
            if (previousActiveElement && typeof previousActiveElement.focus === "function") {
              previousActiveElement.focus()
            }
          }
        }
      } finally {
        if (!this.isDestroyed) {
          this.pushEvent("trade_share_result", {status: copied ? "copied" : "failed", path})
        }
        this.copyInFlight = false
      }
    }
    this.el.addEventListener("click", this.copy)
  },

  destroyed() {
    this.isDestroyed = true
    this.el.removeEventListener("click", this.copy)
  }
}

export default TradeShare
