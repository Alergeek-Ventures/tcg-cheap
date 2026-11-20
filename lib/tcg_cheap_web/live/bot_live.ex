defmodule TcgCheapWeb.BotLive do
  @moduledoc """
  For shop owners: what TCG Cheap's bot reads, how to recognise it (user
  agent, Web Bot Auth signature and key directory, `TcgCheap.WebBotAuth`),
  what the guide does with the data and how to stop it. Shopify's bot
  registration links here as the bot's public documentation.
  """

  use TcgCheapWeb, :live_view

  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.SiteComponents

  alias TcgCheap.Sealed.Shops
  alias TcgCheapWeb.{Format, Paths, SEO}

  @contact "franek@alergeek.ventures"

  @impl true
  def mount(_params, _session, socket) do
    seo = SEO.Bot.metadata()

    {:ok,
     assign(socket,
       seo: seo,
       page_title: seo.page_title,
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
        <.site_header
          region={@region}
          locale={@locale}
          current_path={@current_path}
          region_hint={@region_hint}
        />
        <main id="bot" class="guide-main bot-page" data-guide-url={@current_path}>
          <.link id="bot-back" data-guide-back navigate={Paths.home()} class="guide-back">
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
                <strong>{Format.number(@shop_count)}</strong>
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

          <%!-- Plain English text, on purpose: the registries that review the bot read English,
               and the gettext catalogues of every language would need the same long text. --%>
          <section id="bot-policy" aria-labelledby="bot-policy-title" lang="en">
            <h2 id="bot-policy-title">Bot policy (English)</h2>
            <dl class="bot-facts">
              <dt>Operator</dt>
              <dd>
                Alergeek Ventures, the operator of tcg.cheap. Contact: <a href={"mailto:#{@contact}"}>{@contact}</a>.
              </dd>
              <dt>User-Agent</dt>
              <dd>
                <code>TcgCheap/1.0 (buying guide)</code>, robots.txt token <code>TcgCheap</code>.
              </dd>
              <dt>Signatures</dt>
              <dd>
                Every request the bot makes to a shop (product feeds, store APIs, category and product pages),
                to a wholesaler's price list, to robots.txt itself and for product and card images is signed
                with Web Bot Auth (HTTP Message Signatures, RFC 9421, Ed25519) and carries <code>Signature-Agent: "https://tcg.cheap"</code>. The public key is published at <a href={
                  ~p"/.well-known/http-message-signatures-directory"
                }>
                  <code>{url(~p"/.well-known/http-message-signatures-directory")}</code>
                </a>.
              </dd>
            </dl>

            <h3>robots.txt</h3>
            <ul class="bot-points">
              <li>
                <.fluent_icon name={:eye} />
                <span>
                  Before the bot reads a host it fetches <code>https://&lt;host&gt;/robots.txt</code>
                  (signed, with the same User-Agent) and requests only paths the rules allow. The bot
                  does not read a host or a path robots.txt disallows.
                </span>
              </li>
              <li>
                <.fluent_icon name={:tag} />
                <span>
                  The bot uses the group whose user-agent token is <code>TcgCheap</code>
                  (compared
                  case-insensitively) and, only if there is none, the <code>*</code>
                  group. Within the
                  group the longest matching <code>Allow</code>
                  or <code>Disallow</code>
                  pattern wins and <code>Allow</code>
                  wins a tie; <code>*</code>
                  and a final <code>$</code>
                  in a pattern
                  work as RFC 9309 describes.
                </span>
              </li>
              <li>
                <.fluent_icon name={:hourglass} />
                <span>
                  A <code>Crawl-delay</code> in that group is a minimum pause between requests to the
                  host: the larger of it and the bot's own pause, counted from the last request to that
                  host of any kind. A long Crawl-delay is a pause, not a refusal: the bot waits up to
                  five minutes in place; for a longer one it continues later, after the pause, and gives
                  the read up if the pause would end after the next nightly run.
                </span>
              </li>
              <li>
                <.fluent_icon name={:shield} />
                <span>
                  The status of robots.txt follows RFC 9309. A 2xx answer is parsed (the first 512 KiB
                  are read, the rest is ignored). Any 4xx answer other than 429 (404, 410, and also 401
                  and 403) means there are no rules: everything is allowed. A challenge response in
                  place of robots.txt means the host refuses the bot: it is not read. When robots.txt
                  cannot be read (a 429 or 5xx answer, a timeout, a network error, any other status),
                  the rules fetched earlier are used for up to 24 hours after they were fetched, and the
                  bot asks again after the <code>Retry-After</code>
                  or an hour; without such rules the host is not read, and the read is tried again later that night. Rules are fetched again
                  at most once an hour.
                </span>
              </li>
            </ul>

            <h3>Failures, refusals and pacing</h3>
            <ul class="bot-points">
              <li>
                <.fluent_icon name={:shield} />
                <span>
                  After a 401, a 403 or a challenge response (for example Cloudflare's <code>cf-mitigated: challenge</code>) the bot stops reading that shop at once. It does
                  not repeat the request, does not try another host, address or identity, and asks
                  again only at the next regular run. A host that refuses an image is not asked for
                  another image for an hour, and a redirect an image request meets is checked against
                  the robots.txt rules of its target before it is followed.
                </span>
              </li>
              <li>
                <.fluent_icon name={:arrow_clockwise} />
                <span>
                  <code>Retry-After</code>
                  on a 429 or 503 is honoured in full. A short one (up to 10 seconds,
                  a minute for Shopify) is waited out and the request is repeated once; with a longer one the
                  bot does not ask the host again before the time has passed, and gives the read up if that
                  time is after the next nightly run. A 429 without <code>Retry-After</code>
                  is repeated once
                  after 10 seconds, then after about 20 and 40 minutes.
                </span>
              </li>
              <li>
                <.fluent_icon name={:hourglass} />
                <span>
                  Requests to one shop are made one at a time, at least one second apart (15 seconds on
                  Shopify, 5 seconds for the wholesaler's price list), counted from the last request to
                  that host of any kind, and a read runs once a day. Images are downloaded one by one,
                  spaced by the host's Crawl-delay where robots.txt names one, and never closer to a
                  shop request than its pause.
                </span>
              </li>
            </ul>

            <h3>What is stored</h3>
            <ul class="bot-points">
              <li>
                <.fluent_icon name={:image} />
                <span>
                  Product titles, prices, availability, barcodes where the shop gives them, product page
                  addresses and product images (resized copies on our storage). The bot does not log in,
                  does not use carts or checkout and does not read personal data.
                </span>
              </li>
            </ul>

            <h3>Blocking the bot</h3>
            <ul class="bot-points">
              <li>
                <.fluent_icon name={:mail} />
                <span>
                  Add <code>User-agent: TcgCheap</code>
                  with <code>Disallow: /</code>
                  to robots.txt, or
                  write to <a href={"mailto:#{@contact}"}>{@contact}</a>. The bot checks robots.txt before
                  every run.
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
