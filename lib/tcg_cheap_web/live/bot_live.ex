defmodule TcgCheapWeb.BotLive do
  @moduledoc """
  For shop owners: what TCG Cheap's bot reads, how to recognise it (user
  agent, Web Bot Auth signature and key directory, `TcgCheap.WebBotAuth`),
  what the guide does with the data and how to stop it. Shopify's bot
  registration links here as the bot's public documentation.
  """

  use TcgCheapWeb, :live_view
  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Sealed.Shops
  alias TcgCheapWeb.{Polish, SEO}

  @contact "franek@alergeek.ventures"

  @impl true
  def mount(_params, _session, socket) do
    seo = SEO.bot()

    {:ok,
     assign(socket,
       seo: seo,
       page_title: seo.title,
       contact: @contact,
       shop_count: length(Shops.all())
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <SEO.sync seo={@seo} />
      <div class="guide-world">
        <.site_header locale={@locale} return_to={@locale_return_to} />
        <main id="bot" class="guide-main bot-page" data-guide-url={@locale_return_to}>
          <.link id="bot-back" data-guide-back navigate={~p"/"} class="guide-back">
            <.fluent_icon name={:arrow_left} />{gettext("Wszystkie produkty")}
          </.link>

          <%!-- The one object with an ink shadow: what the bot reads prices of, on a sheet
               like the guide's product photos; the rest is flat paper. --%>
          <section class="bot-intro" aria-labelledby="bot-title">
            <div class="bot-intro-art">
              <img
                src={~p"/images/contents/booster.webp"}
                alt=""
                width="800"
                height="782"
                loading="eager"
              />
            </div>
            <h1 id="bot-title">{gettext("Bot TCG Cheap")}</h1>
            <p class="bot-lead">
              {gettext(
                "TCG Cheap porównuje ceny produktów Pokémon TCG w polskich sklepach internetowych i w kilku sklepach za granicą. Nasz bot czyta publiczne listy produktów tych sklepów, żeby pokazać ich ceny i dostępność, zawsze z linkiem do strony produktu w sklepie."
              )}
            </p>
            <ul id="bot-numbers" class="set-chase-facts">
              <li>
                <strong>{Polish.number(@shop_count)}</strong>
                <span>{ngettext("sklep", "sklepy", @shop_count)}</span>
              </li>
              <li>
                <strong>2:30</strong>
                <span>{gettext("UTC, raz na dobę")}</span>
              </li>
              <li>
                <strong>15 s</strong>
                <span>{gettext("przerwy na Shopify")}</span>
              </li>
            </ul>
          </section>

          <section id="bot-identity" class="bot-card" aria-labelledby="bot-identity-title">
            <h2 id="bot-identity-title">{gettext("Jak go rozpoznać")}</h2>
            <dl class="bot-facts">
              <dt>User-Agent</dt>
              <dd><code>TcgCheap/1.0 (buying guide)</code></dd>
              <dt>{gettext("Podpis Web Bot Auth")}</dt>
              <dd>
                <code>Signature-Agent: "https://tcg.cheap"</code>
                <span>{gettext("przy czytaniu list produktów ze sklepów na Shopify")}</span>
              </dd>
              <dt>{gettext("Klucze publiczne")}</dt>
              <dd>
                <a href={~p"/.well-known/http-message-signatures-directory"}>
                  <.fluent_icon name={:key} />
                  <code>{url(~p"/.well-known/http-message-signatures-directory")}</code>
                </a>
              </dd>
            </dl>
          </section>

          <section id="bot-reading" aria-labelledby="bot-reading-title">
            <h2 id="bot-reading-title">{gettext("Co i jak często czyta")}</h2>
            <ul class="bot-points">
              <li>
                <.fluent_icon name={:clock} />
                <span>
                  {gettext(
                    "Listy produktów czyta raz na dobę, w nocy (od 2:30 UTC), czasem też w dzień, gdy sprawdzamy poprawkę."
                  )}
                </span>
              </li>
              <li>
                <.fluent_icon name={:hourglass} />
                <span>
                  {gettext(
                    "Do każdego sklepu jedno żądanie naraz, z przerwą przed każdym: co najmniej pół sekundy, zwykle sekunda, w sklepach na Shopify 15 sekund."
                  )}
                </span>
              </li>
              <li>
                <.fluent_icon name={:arrow_clockwise} />
                <span>
                  {gettext(
                    "Gdy sklep odpowie 429 (za dużo żądań), bot raz odczekuje krótki Retry-After (do 10 sekund, na Shopify do minuty), a potem wraca najwyżej dwa razy, po około 20 i 40 minutach. Później czeka już do następnej nocy."
                  )}
                </span>
              </li>
              <li>
                <.fluent_icon name={:eye} />
                <span>
                  {gettext(
                    "Czyta tylko publiczne listy produktów (feed produktów, API sklepu albo strony kategorii). Zdjęcia produktów pobiera osobno, po jednym. Nie loguje się, nie dodaje nic do koszyka i nie składa zamówień."
                  )}
                </span>
              </li>
            </ul>
          </section>

          <section id="bot-data" aria-labelledby="bot-data-title">
            <h2 id="bot-data-title">{gettext("Co robimy z danymi")}</h2>
            <ul class="bot-points">
              <li>
                <.fluent_icon name={:tag} />
                <span>
                  {gettext(
                    "Bierzemy nazwę produktu, cenę, dostępność, kod EAN (gdy sklep go podaje) i adres strony produktu, i pokazujemy je obok tego samego produktu z innych sklepów, z linkiem do Twojego sklepu."
                  )}
                </span>
              </li>
              <li>
                <.fluent_icon name={:image} />
                <span>
                  {gettext(
                    "Zdjęcia produktów kopiujemy, zmniejszone, na nasz serwer, żeby nasze strony nie pobierały ich z Twojego. Gdy kopia się nie uda, próbujemy ponownie najwyżej raz na godzinę."
                  )}
                </span>
              </li>
              <li>
                <.fluent_icon name={:shield} />
                <span>
                  {gettext("Nie sprzedajemy tych danych ani nie przekazujemy ich innym firmom.")}
                </span>
              </li>
            </ul>
          </section>

          <%!-- A leaflet clip, like the chains' deals: the one thing to do here. --%>
          <section id="bot-contact" class="bot-clip" aria-labelledby="bot-contact-title">
            <h2 id="bot-contact-title">{gettext("Nie chcesz, żebyśmy czytali Twój sklep?")}</h2>
            <p>
              {gettext(
                "Napisz do nas z nazwą sklepu, a przestaniemy go czytać i usuniemy go z porównania. Pod tym adresem odpowiemy też na pytania o bota."
              )}
            </p>
            <p>
              <a id="bot-contact-email" href={"mailto:#{@contact}"}>
                <.fluent_icon name={:mail} />{@contact}
              </a>
            </p>
          </section>
          <p class="guide-note bot-owner">
            {gettext("TCG Cheap prowadzi")}
            <a href="https://alergeek.ventures">Alergeek Ventures</a>.
          </p>
        </main>
        <.site_footer sets={@footer_sets} />
      </div>
    </Layouts.app>
    """
  end
end
