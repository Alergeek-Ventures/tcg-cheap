export default {
  mounted() {
    this.composing = false
    this.timer = null
    this.scrollFrame = null

    this.schedule = () => {
      clearTimeout(this.timer)
      if (!this.composing) {
        this.timer = setTimeout(() => {
          this.pushEvent("search", {search: {query: this.el.value}})
        }, 250)
      }
    }

    this.onInput = () => this.schedule()
    this.onCompositionStart = () => {
      this.composing = true
      clearTimeout(this.timer)
    }
    this.onCompositionEnd = () => {
      this.composing = false
      this.schedule()
    }
    this.onKeydown = event => {
      if (this.composing || event.isComposing) return

      const open = this.el.getAttribute("aria-expanded") === "true"
      if (event.key === "Escape") {
        clearTimeout(this.timer)
        this.timer = null
        if (open) {
          event.preventDefault()
          this.pushEvent("autocomplete_key", {key: event.key})
        }
      } else if (["ArrowDown", "ArrowUp"].includes(event.key) && open) {
        event.preventDefault()
        this.pushEvent("autocomplete_key", {key: event.key})
      } else if (event.key === "Enter") {
        event.preventDefault()
        clearTimeout(this.timer)
        this.timer = null
        if (open) this.pushEvent("autocomplete_key", {key: "Enter", query: this.el.value})
      }
    }

    this.el.addEventListener("input", this.onInput)
    this.el.addEventListener("compositionstart", this.onCompositionStart)
    this.el.addEventListener("compositionend", this.onCompositionEnd)
    this.el.addEventListener("keydown", this.onKeydown)
  },
  updated() {
    if (this.scrollFrame) cancelAnimationFrame(this.scrollFrame)

    const activeOptionId = this.el.getAttribute("aria-activedescendant")
    if (activeOptionId) {
      this.scrollFrame = requestAnimationFrame(() => {
        document.getElementById(activeOptionId)?.scrollIntoView({block: "nearest"})
        this.scrollFrame = null
      })
    } else {
      this.scrollFrame = null
    }
  },
  destroyed() {
    clearTimeout(this.timer)
    if (this.scrollFrame) cancelAnimationFrame(this.scrollFrame)
    this.el.removeEventListener("input", this.onInput)
    this.el.removeEventListener("compositionstart", this.onCompositionStart)
    this.el.removeEventListener("compositionend", this.onCompositionEnd)
    this.el.removeEventListener("keydown", this.onKeydown)
  }
}
