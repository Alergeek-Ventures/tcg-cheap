// Marks a sticky element with `data-stuck` while it rests at its sticky
// offset, so the stylesheet can fold what it does not need there. Without
// JavaScript nothing folds. The element keeps the attribute through LiveView
// patches with `JS.ignore_attributes(["data-stuck"])`.
//
// The offset is read again on every check: the stylesheet makes the element
// sticky only on some screens, and a turned phone can cross into another one.
export default {
  mounted() {
    let queued = false

    this.check = () => {
      if (queued) return
      queued = true

      requestAnimationFrame(() => {
        queued = false
        const style = getComputedStyle(this.el)
        const offset = parseFloat(style.insetBlockStart)
        const stuck =
          style.position === "sticky" &&
          scrollY > 0 &&
          this.el.getBoundingClientRect().top <= offset + 1

        this.el.toggleAttribute("data-stuck", stuck)
      })
    }

    addEventListener("scroll", this.check, {passive: true})
    addEventListener("resize", this.check, {passive: true})
    this.check()
  },

  destroyed() {
    removeEventListener("scroll", this.check)
    removeEventListener("resize", this.check)
  }
}
