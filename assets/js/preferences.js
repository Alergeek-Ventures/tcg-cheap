// The visitor's language: localStorage keeps it and the `lang` cookie mirrors
// it, so the server renders it on the first response (TcgCheapWeb.Locale).
// The language links go through /lang/:locale, which sets the cookie and
// works without JavaScript; this keeps localStorage in step and restores the
// cookie from it when the browser dropped only the cookie.
const KEY = "tcg:language"
// A language code; the server ignores one it does not render in.
const LANGUAGE = /^[a-z]{2}$/
const YEAR = 365 * 24 * 60 * 60

const stored = () => {
  try {
    return localStorage.getItem(KEY)
  } catch {
    return null
  }
}

const store = language => {
  try {
    localStorage.setItem(KEY, language)
  } catch {
    // Private mode or blocked storage: the cookie still carries the choice.
  }
}

const cookie = () => document.cookie.match(/(?:^|;\s*)lang=([^;]*)/)?.[1]

export default function initPreferences() {
  const language = stored()
  if (LANGUAGE.test(language ?? "") && !cookie())
    document.cookie = `lang=${language}; Path=/; Max-Age=${YEAR}; SameSite=Lax`

  document.addEventListener("click", event => {
    const link = event.target.closest?.("a[data-language]")
    if (link && LANGUAGE.test(link.dataset.language)) store(link.dataset.language)
  })
}
