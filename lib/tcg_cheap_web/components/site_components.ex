defmodule TcgCheapWeb.SiteComponents do
  @moduledoc "The public pages' chrome: the masthead with its region and language controls, the footer, the cookie notice and the report form."

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{Format, Paths, Region, SEO}

  @doc """
  The public masthead: the wordmark, linking to the region's guide, the
  region and language control and optional controls; under it, the region
  hint (`TcgCheapWeb.Locale`) when there is one.
  """
  attr :id, :string, default: "site-header"
  attr :region, Region, default: nil
  attr :locale, :string, default: nil
  attr :current_path, :string, default: "/"
  attr :region_hint, :string, default: nil
  slot :inner_block

  def site_header(assigns) do
    ~H"""
    <header id={@id} class="site-header">
      <.link id="site-wordmark" class="site-wordmark" navigate={Paths.home()}>
        <img src={~p"/images/tcg-cheap.webp"} alt="TCG Cheap" width="135" height="32" />
      </.link>
      <.locale_control
        :if={@region && @locale}
        region={@region}
        locale={@locale}
        current_path={@current_path}
      />
      {render_slot(@inner_block)}
    </header>
    <.region_hint
      :if={@region && @region_hint}
      region={@region}
      suggested={Region.fetch!(@region_hint)}
      current_path={@current_path}
    />
    """
  end

  attr :region, Region, required: true
  attr :locale, :string, required: true
  attr :current_path, :string, required: true

  # The region (which shops, prices and delivery) and the language (only the
  # text) are chosen apart. Each option is a link, so both work without
  # JavaScript; preferences.js also keeps the language in localStorage.
  defp locale_control(assigns) do
    ~H"""
    <details
      id="guide-locale"
      class="guide-locale"
      phx-mounted={JS.ignore_attributes(["open"])}
    >
      <summary
        id="guide-locale-summary"
        class="guide-locale-summary"
        aria-label={
          gettext("Kraj i język: %{region}, %{language}",
            region: country_name(@region.code),
            language: language_name(@locale)
          )
        }
      >
        <img src={flag(@region.code)} alt="" width="21" height="14" />{String.upcase(@locale)}
      </summary>
      <div class="guide-locale-panel">
        <nav id="guide-region" aria-labelledby="guide-region-title">
          <h2 id="guide-region-title">{gettext("Kraj")}</h2>
          <p class="guide-note">{gettext("Sklepy, ceny i dostawa")}</p>
          <ul>
            <li :for={region <- Region.all()}>
              <a
                id={"region-#{region.code}"}
                href={~p"/region/#{region.code}?#{[path: @current_path]}"}
                rel="nofollow"
                aria-current={if(region.code == @region.code, do: "true")}
                data-track="region_changed"
                data-track-to={region.code}
              >
                <img src={flag(region.code)} alt="" width="21" height="14" />
                <span class="guide-locale-name">
                  {country_name(region.code)}
                  <span class="guide-locale-currency">
                    · {Format.currency_symbol(region.market.currency)}
                  </span>
                </span>
                <.fluent_icon
                  :if={region.code == @region.code}
                  name={:checkmark_circle}
                  class="guide-locale-check"
                />
              </a>
            </li>
          </ul>
        </nav>
        <nav id="guide-language" aria-labelledby="guide-language-title">
          <h2 id="guide-language-title">{gettext("Język strony")}</h2>
          <ul>
            <li :for={language <- Region.languages()}>
              <a
                id={"language-#{language}"}
                href={~p"/lang/#{language}?#{[return_to: @current_path]}"}
                rel="nofollow"
                lang={language}
                hreflang={language}
                aria-current={if(language == @locale, do: "true")}
                data-language={language}
                data-track="language_changed"
                data-track-to={language}
              >
                <span class="guide-locale-name">{language_name(language)}</span>
                <.fluent_icon
                  :if={language == @locale}
                  name={:checkmark_circle}
                  class="guide-locale-check"
                />
              </a>
            </li>
          </ul>
        </nav>
      </div>
    </details>
    """
  end

  attr :region, Region, required: true
  attr :suggested, Region, required: true
  attr :current_path, :string, required: true

  # In the suggested region's language: the visitor may not read this one.
  # Staying chooses the current region, which ends the hint.
  defp region_hint(assigns) do
    assigns =
      Gettext.with_locale(TcgCheapWeb.Gettext, assigns.suggested.language, fn ->
        assign(assigns,
          text: region_hint_text(assigns.suggested.code),
          switch: region_hint_switch(assigns.suggested.code),
          stay: gettext("Zostań tutaj"),
          country: country_name(assigns.suggested.code)
        )
      end)

    ~H"""
    <aside
      id="region-hint"
      class="region-hint"
      lang={@suggested.language}
      aria-label={@country}
    >
      <p>
        <img src={flag(@suggested.code)} alt="" width="21" height="14" />{@text}
      </p>
      <a
        id="region-hint-switch"
        class="region-hint-switch"
        href={~p"/region/#{@suggested.code}?#{[path: @current_path]}"}
        rel="nofollow"
        data-track="region_hint_followed"
        data-track-to={@suggested.code}
      >{@switch}</a>
      <a
        id="region-hint-stay"
        class="region-hint-stay"
        href={~p"/region/#{@region.code}?#{[path: @current_path]}"}
        rel="nofollow"
        data-track="region_hint_dismissed"
      >{@stay}</a>
    </aside>
    """
  end

  defp region_hint_text("hu"), do: gettext("Wygląda na to, że jesteś na Węgrzech.")
  defp region_hint_text("pl"), do: gettext("Wygląda na to, że jesteś w Polsce.")
  defp region_hint_switch("hu"), do: gettext("Przejdź do wersji węgierskiej")
  defp region_hint_switch("pl"), do: gettext("Przejdź do wersji polskiej")

  # Countries in the page language ("Węgry", "Hungary"); languages under
  # their own names.
  defp country_name("pl"), do: gettext("Polska")
  defp country_name("hu"), do: gettext("Węgry")

  # Each language under its own name.
  defp language_name("pl"), do: "Polski"
  defp language_name("en"), do: "English"
  defp language_name("hu"), do: "Magyar"

  defp flag(code), do: ~p"/images/flags/#{code <> ".svg"}"

  attr :sets, :list, required: true, doc: "the newest sets (`TcgCheapWeb.SiteFooter`)"

  @doc """
  The public footer: the newest sets and the guide's own pages, so every page
  leads to them, then who built it.
  """
  def site_footer(assigns) do
    ~H"""
    <footer id="site-footer" class="site-footer">
      <div class="site-footer-columns">
        <nav :if={@sets != []} id="site-footer-sets" aria-labelledby="site-footer-sets-title">
          <h2 id="site-footer-sets-title">{gettext("Najnowsze sety")}</h2>
          <ul class="site-footer-links site-footer-sets">
            <li :for={set <- @sets}>
              <.link navigate={SEO.expansion_path(set.id, set.name)}>{set.name}</.link>
            </li>
          </ul>
        </nav>
        <nav id="site-footer-pages" aria-labelledby="site-footer-pages-title">
          <h2 id="site-footer-pages-title">{gettext("Ważne linki")}</h2>
          <ul class="site-footer-links">
            <li><.link navigate={Paths.home()}>{gettext("Ceny produktów")}</.link></li>
            <li><.link navigate={Paths.cards()}>{gettext("Ceny kart")}</.link></li>
            <%!-- The articles and the bot page are Polish only. --%>
            <li :if={Paths.page(:booster_prices)}>
              <.link navigate={Paths.page(:booster_prices)}>
                {gettext("Ile kosztuje booster Pokémon?")}
              </.link>
            </li>
            <li :if={Paths.page(:expensive_cards)}>
              <.link navigate={Paths.page(:expensive_cards)}>
                {gettext("Najdroższe karty Pokémon")}
              </.link>
            </li>
            <li :if={Paths.page(:card_value)}>
              <.link navigate={Paths.page(:card_value)}>
                {gettext("Ile jest warta twoja karta?")}
              </.link>
            </li>
            <li :if={Paths.page(:bot)}>
              <.link navigate={Paths.page(:bot)}>{gettext("Dla sklepów: nasz bot")}</.link>
            </li>
          </ul>
        </nav>
      </div>
      <%!-- Visitors abroad buy from shops in another country: say once we are none of them. --%>
      <p :if={!Region.poland?(Region.current())} id="site-footer-about" class="site-footer-about">
        {gettext("Niezależna porównywarka cen, nie sklep.")}
      </p>
      <p>
        built with
        <svg class="site-footer-ball" viewBox="0 0 16 16" role="img" aria-label="Poké Ball">
          <circle cx="8" cy="8" r="7" fill="#fff" />
          <path d="M1 8a7 7 0 0 1 14 0z" fill="#d23c2a" />
          <circle cx="8" cy="8" r="7" fill="none" stroke="currentColor" stroke-width="1.2" />
          <path d="M1 8h14" stroke="currentColor" stroke-width="1.2" />
          <circle cx="8" cy="8" r="2.4" fill="#fff" stroke="currentColor" stroke-width="1" />
        </svg>
        by <a href="https://alergeek.ventures" title="Alergeek
          Ventures">Alergeek Ventures</a>
      </p>
    </footer>
    """
  end

  @doc "The cookie notice; analytics.js shows it until the visitor closes it or rejects cookies."
  def cookie_notice(assigns) do
    ~H"""
    <aside id="cookie-notice" class="cookie-notice" aria-label={gettext("Cookies")} hidden>
      <p>{gettext("Używamy cookies do statystyk odwiedzin i formularza zgłoszeń.")}</p>
      <div class="cookie-notice-actions">
        <button id="cookie-notice-reject" type="button">{gettext("Odrzuć")}</button>
        <button id="cookie-notice-accept" type="button">{gettext("Zamknij")}</button>
      </div>
    </aside>
    """
  end

  @doc """
  The report form. analytics.js shows it and sends each report as a new
  PostHog support ticket; rejecting cookies hides it.
  """
  def report_form(assigns) do
    ~H"""
    <div
      id="report"
      class="report"
      data-sending={gettext("Wysyłam…")}
      data-sent={gettext("Dzięki! Zgłoszenie dotarło.")}
      data-failed={gettext("Nie udało się wysłać. Spróbuj jeszcze raz.")}
      hidden
    >
      <button id="report-toggle" type="button" popovertarget="report-panel">
        {gettext("Zgłoś problem")}
      </button>
      <form id="report-panel" popover aria-labelledby="report-title">
        <h2 id="report-title">{gettext("Zgłoś problem")}</h2>
        <p>{gettext("Zła cena, brakujący produkt albo coś nie działa? Napisz, sprawdzimy.")}</p>
        <label for="report-message">{gettext("Co się stało?")}</label>
        <textarea id="report-message" name="message" required autofocus></textarea>
        <label for="report-email">{gettext("E-mail, jeśli chcesz odpowiedź")}</label>
        <input id="report-email" name="email" type="email" autocomplete="email" />
        <div class="report-actions">
          <p id="report-status" role="status"></p>
          <button
            id="report-cancel"
            type="button"
            popovertarget="report-panel"
            popovertargetaction="hide"
          >
            {gettext("Anuluj")}
          </button>
          <button id="report-submit" type="submit">{gettext("Wyślij")}</button>
        </div>
      </form>
    </div>
    """
  end
end
