defmodule TcgCheapWeb.BrowseLive.Banners do
  @moduledoc "The banners that open the buying guide's lists: a set page's top and the whole guide's numbers for sealed products and singles."

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.BrowseLive.ChaseBanners

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

  attr :shops?, :boolean,
    required: true,
    doc: "shops sell singles in the region (`Region.singles?/1`), so cards have their prices"

  # A set page's top: the set's most valuable card, what pulling it from packs
  # costs on average against buying it, and the next three cards the same way;
  # a set without card prices shows its single booster instead.
  def set_intro(assigns) do
    set = assigns.page.set

    assigns =
      assign(assigns,
        logo_url: set && set.logo_url,
        # The cards' prices are the region's shops' and Cardmarket's in its currency.
        top_cards: if(set && assigns.shops?, do: set.top_cards, else: []),
        card_count: if(set, do: set.card_count, else: 0)
      )

    ~H"""
    <section id="set-intro" class="guide-intro set-intro" aria-labelledby="guide-title">
      <.set_title name={@name} logo_url={@logo_url} close={@close} />
      <%= cond do %>
        <% @singles? and @shops? -> %>
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
            <p id="guide-promise">{Enum.join(SEO.Expansion.answer(@name, @page), " ")}</p>
          <% end %>
      <% end %>
    </section>
    """
  end

  attr :filters, :map, required: true

  # The list without an expansion opens with our title and promise where a set
  # page has its logo, then the search: the home page carries today's deals and
  # numbers, so the list itself starts with what it lists.
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
    </section>
    """
  end

  attr :singles, :map, default: nil
  attr :top, :map, default: nil
  attr :cards_href, :string, required: true

  # The singles banner: the set's best deal in the region's shops against its
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
            {gettext("Najlepsza okazja w secie")}
          </p>
          <h2 class="set-chase-name">
            <.link
              navigate={Paths.localize(deal.path)}
              data-track="card_clicked"
            >{deal.card.name}</.link>
          </h2>
          <p class="set-chase-meta">
            {chase_identity(deal.card)}
          </p>
        </div>
        <div class="set-chase-pair">
          <p id="set-chase-pull" class="set-chase-side set-chase-pull">
            <span class="set-chase-label">{gettext("Na Cardmarket")}</span>
            <strong>{Format.price(deal.trend)}</strong>
            <span class="set-chase-detail">{RegionText.cardmarket_card_delivery()}</span>
          </p>
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
        <li :if={@top}>
          <strong>{Format.price(@top.price)}</strong>
          <span>{gettext("najcenniejsza: %{card}", card: @top.card.name)}</span>
        </li>
        <li class={@singles.set_price && "set-chase-fact-extra"}>
          <strong>{Format.number(@singles.cheaper)}</strong>
          <span>{gettext("taniej niż na Cardmarket z wysyłką")}</span>
        </li>
      </ul>
      <p class="set-chase-foot">
        <span>{RegionText.singles_prices_note()}</span>
        <a href={@cards_href}>{gettext("Zobacz karty")}</a>
      </p>
    </div>
    """
  end
end
