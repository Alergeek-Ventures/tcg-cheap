defmodule TcgCheapWeb.BrowseLive.Banners do
  @moduledoc "The banners that open the buying guide's lists: a set page's top and the whole guide's numbers for sealed products and singles."

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.BrowseLive.ChaseBanners
  import TcgCheapWeb.RetailComponents

  alias TcgCheap.Sealed.Kinds
  alias TcgCheapWeb.{Format, Paths, RegionText, SEO}

  attr :name, :string, required: true
  attr :logo_url, :string, default: nil
  attr :close, :string, required: true

  # The set's logo carries its name, so the name is only visible without one;
  # with a logo it stays in the heading's text for screen readers and search.
  defp set_title(assigns) do
    ~H"""
    <div class="set-title">
      <h1 id="guide-title">
        <img :if={@logo_url} src={@logo_url} alt="" class="set-logo" />
        <span :if={@logo_url} class="sr-only">{@name}</span>
        <%= if !@logo_url do %>
          {@name}
        <% end %>
      </h1>
      <.link
        id="set-close"
        patch={@close}
        class="set-close"
        aria-label={gettext("Zamknij set i wyczyść filtry")}
      >
        <.fluent_icon name={:dismiss} />
      </.link>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :page, :map, required: true
  attr :close, :string, required: true
  attr :cards_href, :string, default: "#product-cards"
  attr :singles?, :boolean, default: false
  attr :polish?, :boolean, required: true

  # A set page's top: the set's most valuable card, what pulling it from packs
  # costs on average against buying it, and the next three cards the same way;
  # a set without card prices shows its single booster instead.
  def set_intro(assigns) do
    set = assigns.page.set

    assigns =
      assign(assigns,
        logo_url: set && set.logo_url,
        # The cards' prices are Polish shops' and Cardmarket's in złoty.
        top_cards: if(set && assigns.polish?, do: set.top_cards, else: []),
        card_count: if(set, do: set.card_count, else: 0)
      )

    ~H"""
    <section id="set-intro" class="guide-intro set-intro" aria-labelledby="guide-title">
      <.set_title name={@name} logo_url={@logo_url} close={@close} />
      <%= cond do %>
        <% @singles? and @polish? -> %>
          <.set_singles
            singles={@page.set && @page.set.singles}
            top={List.first(@top_cards)}
            cards_href={@cards_href}
          />
        <% @top_cards != [] -> %>
          <.set_chase
            top={hd(@top_cards)}
            next={tl(@top_cards)}
            booster={@page.booster}
            count={@card_count}
            cards_href={@cards_href}
          />
        <% @page.booster -> %>
          <.set_booster
            booster={@page.booster}
            set={@page.set}
            cardmarket={@page.cardmarket}
            count={@card_count}
            cards_href={@cards_href}
          />
        <% true -> %>
          <%= if @card_count > 0 do %>
            <div id="set-chase" class="set-chase set-chase-empty">
              <.chase_foot count={@card_count} priced?={false} href={@cards_href} />
            </div>
          <% else %>
            <p id="guide-promise">{Enum.join(SEO.expansion_answer(@name, @page), " ")}</p>
          <% end %>
      <% end %>
    </section>
    """
  end

  attr :filters, :map, required: true
  attr :market, :map, default: nil, doc: "the banner's figures, nil where there are none"

  # The list without an expansion opens like a set page: our title and promise
  # where the set's logo goes, then the whole guide's numbers for singles or
  # sealed products, so choosing a set swaps the content, not the layout.
  def site_intro(assigns) do
    ~H"""
    <section id="set-intro" class="guide-intro set-intro" aria-labelledby="guide-title">
      <div class="set-title site-title">
        <div class="site-title-text">
          <%!-- The card list's own question, as the products list asks its own. --%>
          <h1 id="guide-title">
            {if(@filters.mode == :cards,
              do: gettext("Ile kosztuje ta karta?"),
              else: gettext("Czy to dobra cena?")
            )}
          </h1>
          <p id="guide-promise">
            {if(@filters.mode == :cards,
              do: RegionText.cards_promise(),
              else: RegionText.products_promise()
            )}
          </p>
        </div>
      </div>
      <%= cond do %>
        <% !@market -> %>
        <% @filters.mode == :cards -> %>
          <.set_singles
            singles={@market}
            top={@market.top}
            cards_href="#guide-results-title"
            all?={true}
          />
        <% true -> %>
          <.sealed_market market={@market} />
      <% end %>
    </section>
    """
  end

  attr :deals, :list, required: true

  # Retail chains' prices running today, announced as news under the banner;
  # the booster price page lists them all. Without one, a link to that page.
  def retail_news(%{deals: []} = assigns) do
    ~H"""
    <p id="home-booster-prices" class="reference-link">
      <.link navigate={Paths.page(:booster_prices)}>{gettext("Ile kosztuje booster? Ceny boosterów")}&nbsp;→</.link>
    </p>
    """
  end

  def retail_news(assigns) do
    ~H"""
    <section id="home-booster-prices" aria-labelledby="home-retail-news-title">
      <div class="retail-news-head">
        <h2 id="home-retail-news-title">{gettext("Okazje w sieciówkach")}</h2>
        <.link navigate={Paths.page(:booster_prices)}>{gettext("Wszystkie ceny boosterów")}&nbsp;→</.link>
      </div>
      <.retail_clips id="home-retail-deal" deals={@deals} products? />
    </section>
    """
  end

  attr :market, :map, required: true

  # The sealed banner: the product a Polish shop sells furthest under the
  # typical shop price today, then the product market in numbers.
  def sealed_market(assigns) do
    ~H"""
    <div id="set-chase" class={["set-chase", !@market.deal && "set-chase-empty"]}>
      <%= if deal = @market.deal do %>
        <%!-- One product: what it holds above, the box itself below, in a card's shape. --%>
        <.link
          class="set-chase-art set-chase-products"
          navigate={Paths.product(deal.product.slug)}
          tabindex="-1"
          aria-hidden="true"
        >
          <span :if={deal.contents_photos != []} class="set-chase-contents">
            <img :for={photo <- deal.contents_photos} src={photo} alt="" loading="eager" />
          </span>
          <img
            :if={deal.product.stored_photo_card_url}
            src={deal.product.stored_photo_card_url}
            alt=""
            loading="eager"
            fetchpriority="high"
            class="set-chase-box"
          />
        </.link>
        <div class="set-chase-head">
          <p class="set-chase-kicker">{gettext("Najlepsza okazja teraz")}</p>
          <h2 class="set-chase-name">
            <.link navigate={Paths.product(deal.product.slug)}>{deal.product.name}</.link>
          </h2>
          <p class="set-chase-meta">{Kinds.label(deal.product.kind)}</p>
        </div>
        <div class="set-chase-pair">
          <p id="set-chase-pull" class="set-chase-side set-chase-pull">
            <span class="set-chase-label">{gettext("Zwykle w sklepach")}</span>
            <strong>{Format.price(deal.typical)}</strong>
            <span class="set-chase-detail">{ngettext(
              "mediana z %{count} sklepu",
              "mediana z %{count} sklepów",
              deal.shops
            )}</span>
          </p>
          <span class="set-chase-or">{"−#{deal.percent}%"}</span>
          <.link
            id="set-chase-buy"
            class="set-chase-side set-chase-buy"
            navigate={Paths.product(deal.product.slug)}
          >
            <span class="set-chase-label">{gettext("Kupisz za")}</span>
            <strong>{Format.price(deal.price)}</strong>
            <span class="set-chase-detail">{chase_source({:shop, deal.shop})}</span>
          </.link>
        </div>
      <% end %>
      <ul id="sealed-market-facts" class="set-chase-facts">
        <li>
          <strong>{Format.number(@market.in_stock)}</strong>
          <span>{ngettext(
            "produkt na stanie w sklepach",
            "produkty na stanie w sklepach",
            @market.in_stock
          )}</span>
        </li>
        <li>
          <strong>{Format.number(@market.good)}</strong>
          <span>{gettext("w dobrej cenie dziś")}</span>
        </li>
        <li>
          <strong>{Format.number(@market.shops)}</strong>
          <span>{ngettext(
            "sklep z produktami na stanie",
            "sklepy z produktami na stanie",
            @market.shops
          )}</span>
        </li>
        <li class="set-chase-fact-extra">
          <strong>{Format.number(@market.offers)}</strong>
          <span>{ngettext("oferta na stanie", "oferty na stanie", @market.offers)}</span>
        </li>
      </ul>
      <p class="set-chase-foot">
        <span>{gettext("Ceny bez dostawy.")}</span>
        <a href="#guide-results-title">{gettext("Zobacz produkty")}</a>
      </p>
    </div>
    """
  end

  attr :singles, :map, default: nil
  attr :top, :map, default: nil
  attr :cards_href, :string, required: true
  attr :all?, :boolean, default: false

  # The singles banner: the set's best deal in a Polish shop against its
  # Cardmarket trend, then what the set's singles market looks like in numbers.
  def set_singles(assigns) do
    ~H"""
    <div
      :if={@singles}
      id="set-chase"
      class={["set-chase", !@singles.deal && "set-chase-empty"]}
      data-track-context
      data-track-placement="banner"
      data-track-card={@singles.deal && @singles.deal.card.id}
      data-track-card-name={@singles.deal && @singles.deal.card.name}
    >
      <%= if deal = @singles.deal do %>
        <.link
          class="set-chase-art"
          navigate={Paths.localize(deal.path)}
          data-track="card_clicked"
          tabindex="-1"
          aria-hidden="true"
        >
          <.chase_art top={deal} hero?={true} />
        </.link>
        <div class="set-chase-head">
          <p class="set-chase-kicker">
            {if(@all?,
              do: gettext("Najlepsza okazja teraz"),
              else: gettext("Najlepsza okazja w secie")
            )}
          </p>
          <h2 class="set-chase-name">
            <.link
              navigate={Paths.localize(deal.path)}
              data-track="card_clicked"
            >{deal.card.name}</.link>
          </h2>
          <p class="set-chase-meta">
            {if(@all?,
              do:
                gettext("nr %{number} · %{expansion}",
                  number: deal.card.number,
                  expansion: deal.card.expansion_name
                ),
              else: chase_identity(deal.card)
            )}
          </p>
        </div>
        <div class="set-chase-pair">
          <p id="set-chase-pull" class="set-chase-side set-chase-pull">
            <span class="set-chase-label">{gettext("Na Cardmarket")}</span>
            <strong>{Format.price(deal.trend)}</strong>
            <span class="set-chase-detail">{gettext("z wysyłką do Polski")}</span>
          </p>
          <span class="set-chase-or">{"−#{deal.percent}%"}</span>
          <.link
            id="set-chase-buy"
            class="set-chase-side set-chase-buy"
            navigate={Paths.localize(deal.path)}
            data-track="card_clicked"
          >
            <span class="set-chase-label">{gettext("Kupisz ją za")}</span>
            <strong>{Format.price(deal.price)}</strong>
            <span class="set-chase-detail">{chase_source({:shop, deal.shop})}</span>
          </.link>
        </div>
      <% end %>
      <ul id="set-singles-facts" class="set-chase-facts">
        <li>
          <strong>{Format.number(@singles.in_stock)}</strong>
          <span>{gettext("z %{total} kart na stanie w sklepach", total: Format.number(@singles.total))}</span>
        </li>
        <li :if={@singles.set_price}>
          <strong>{Format.about(@singles.set_price)}</strong>
          <span>{gettext("cały set, najtaniej")}</span>
        </li>
        <li :if={@all?}>
          <strong>{Format.number(@singles.cheaper)}</strong>
          <span>{gettext("taniej niż na Cardmarket z wysyłką")}</span>
        </li>
        <%!-- The whole guide's numbers match the products list's: in stock, cheaper, shops; the dearest card rounds out the phone grid. --%>
        <li :if={@all?}>
          <strong>{Format.number(@singles.shops)}</strong>
          <span>{ngettext(
            "sklep z kartami na stanie",
            "sklepy z kartami na stanie",
            @singles.shops
          )}</span>
        </li>
        <li :if={@top} class={@all? && "set-chase-fact-extra"}>
          <strong>{Format.price(@top.price)}</strong>
          <span>{if(@all?,
            do: gettext("najcenniejsza na stanie: %{card}", card: @top.card.name),
            else: gettext("najcenniejsza: %{card}", card: @top.card.name)
          )}</span>
        </li>
        <li :if={!@all?} class={@singles.set_price && "set-chase-fact-extra"}>
          <strong>{Format.number(@singles.cheaper)}</strong>
          <span>{gettext("taniej niż na Cardmarket z wysyłką")}</span>
        </li>
      </ul>
      <p class="set-chase-foot">
        <span>{gettext("Ceny bez dostawy. Z zagranicy: z wysyłką do Polski.")}</span>
        <a href={@cards_href}>{gettext("Zobacz karty")}</a>
      </p>
    </div>
    """
  end
end
