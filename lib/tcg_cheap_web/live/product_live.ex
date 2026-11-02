defmodule TcgCheapWeb.ProductLive do
  @moduledoc """
  One catalogue product: today's verdict, how its price compares with other
  shops today and with its own 90 days of prices, and the offers behind it.
  """

  use TcgCheapWeb, :live_view
  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.GuideComponents

  alias TcgCheap.Catalogue.CardImage
  alias TcgCheap.Sealed.{Guide, Kinds, PriceGuide, Regions, Shops}
  alias TcgCheap.Sealed.PullRates.Rate
  alias TcgCheapWeb.{Analytics, Polish, SEO, VisitorLocation}

  defmodule NotFound do
    @moduledoc false
    defexception message: "product not found", plug_status: 404
  end

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Guide.product(slug, DateTime.utc_now()) do
      {:ok, page} ->
        seo = SEO.product(page)

        {in_stock, out_of_stock} = Enum.split_with(page.offers, & &1.in_stock)

        {:ok,
         socket
         |> assign(seo: seo, page_title: seo.title)
         |> assign(:page, page)
         |> assign(:in_stock_count, length(in_stock))
         |> assign(:out_of_stock_count, length(out_of_stock))
         |> VisitorLocation.assign_location()
         |> stream_offers()
         |> track_view(page)}

      :error ->
        raise NotFound
    end
  end

  # Once per visit to the page: a reconnect mounts it again.
  defp track_view(socket, page) do
    if connected?(socket) and get_connect_params(socket)["_mounts"] == 0,
      do: Analytics.track(socket, "product_viewed", viewed_properties(page)),
      else: socket
  end

  defp viewed_properties(%{product: product, verdict: verdict} = page) do
    %{
      product_slug: product.slug,
      product_name: product.name,
      kind: product.kind,
      region: product.region,
      set_name: product.set_name,
      verdict: verdict.status,
      cheapest_price: verdict.cheapest && Decimal.to_float(verdict.cheapest.price),
      cheapest_shop: verdict.cheapest && verdict.cheapest.shop,
      offer_count: length(page.offers),
      in_stock_count: Enum.count(page.offers, & &1.in_stock),
      suggested_price: page.suggested_price && Decimal.to_float(page.suggested_price.price),
      has_contents: product.contents != nil
    }
  end

  @impl true
  def handle_event("location-" <> _ = event, params, socket) do
    located = VisitorLocation.handle_event(event, params, socket)

    # Offer rows show the distance to pickup, so they re-render with it.
    if located.assigns.location == socket.assigns.location,
      do: {:noreply, located},
      else: {:noreply, stream_offers(located, reset: true)}
  end

  # Offers with stock are the list; those without wait behind a disclosure.
  defp stream_offers(socket, opts \\ []) do
    {in_stock, out_of_stock} = Enum.split_with(socket.assigns.page.offers, & &1.in_stock)

    socket
    |> stream(:offers, in_stock, opts)
    |> stream(:offers_out_of_stock, out_of_stock, opts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <SEO.sync seo={@seo} />
      <div class="guide-world">
        <.site_header locale={@locale} return_to={@locale_return_to}>
          <VisitorLocation.location_control
            location={@location}
            ready={@location_ready?}
            form={@town_form}
            matches={@town_matches}
            error={@location_error}
          />
        </.site_header>
        <main
          id="product-main"
          class="guide-main product-page"
          data-track-context
          data-track-product-slug={@page.product.slug}
        >
          <.link id="product-back" navigate={~p"/"} class="guide-back">
            <.fluent_icon name={:arrow_left} />{gettext("Wszystkie produkty")}
          </.link>

          <div class="product-top">
            <.product_image
              photo={@page.product.photo_page_url}
              blur={@page.product.photo_placeholder}
              kind={@page.product.kind}
              alt={@page.product.name}
              class="product-hero-image"
              loading="eager"
            />
            <section id="product-identity" class="product-identity" aria-labelledby="product-name">
              <h1 id="product-name">{@page.product.name}</h1>
              <p class="product-facts">
                <span id="product-kind">{Kinds.label(@page.product.kind)}</span><span
                  :if={@page.product.set_name}
                  id="product-set"
                > · {@page.product.set_name}</span><span id="product-region">
                  {gettext("· wersja %{edition}",
                    edition:
                      if(@locale == "pl",
                        do: String.downcase(Regions.label(@page.product.region)),
                        else: Regions.label(@page.product.region)
                      )
                  )}
                </span>
              </p>
              <p :if={@page.suggested_price} id="product-suggested" class="product-facts">
                {gettext("Cena sugerowana (REBEL): %{price}",
                  price: Polish.price(@page.suggested_price.price)
                )} ·
                <a
                  href="#product-suggested-price"
                  data-track="product_section_opened"
                  data-track-section="suggested_price"
                >{gettext("skąd ta cena?")}</a>
              </p>
              <p :if={@page.product.contents} id="product-inside" class="product-facts">
                <a
                  href="#product-contents"
                  data-track="product_section_opened"
                  data-track-section="contents"
                >{gettext("Co jest w środku")} ↓</a>
              </p>
              <p
                :if={booster_links(@page) != []}
                id="product-booster-links"
                class="product-facts"
              >
                <%= for {{href, label}, index} <- Enum.with_index(booster_links(@page)) do %>
                  <span :if={index > 0}>·</span> <a href={href}>{label} ↓</a>
                <% end %>
              </p>
            </section>
            <.verdict_block
              page={@page}
              nearby={if(@location_ready?, do: nearby(@page, @location))}
            />
          </div>

          <section id="product-offers" class="product-section" aria-labelledby="product-offers-title">
            <div class="product-section-heading">
              <h2 id="product-offers-title">{gettext("Oferty w sklepach")}</h2>
              <p :if={@in_stock_count > 0}>
                {gettext("%{offers} na stanie",
                  offers: Polish.plural(@in_stock_count, "oferta", "oferty", "ofert")
                )}
              </p>
            </div>
            <%!-- Distances to pickup stay out of PostHog's autocapture; shop links track themselves. --%>
            <ul
              id="offer-list"
              class="offer-list ph-no-capture"
              phx-update="stream"
              data-track-positions
            >
              <li id="offer-list-empty" class="guide-empty hidden only:block">
                {gettext("Teraz żaden sklep nie ma tego produktu na stanie.")}
              </li>
              <.offer
                :for={{dom_id, offer} <- @streams.offers}
                id={dom_id}
                offer={offer}
                location={@location}
                today={@page.today}
              />
            </ul>
            <details
              :if={@out_of_stock_count > 0}
              id="offers-out-of-stock"
              class="verdict-method offers-out"
            >
              <summary data-track="product_section_opened" data-track-section="out_of_stock_offers">
                {gettext("Bez towaru: %{offers}",
                  offers: Polish.plural(@out_of_stock_count, "oferta", "oferty", "ofert")
                )}<.fluent_icon name={:chevron_down} class="verdict-method-chevron" />
              </summary>
              <ul
                id="offer-list-out"
                class="offer-list ph-no-capture"
                phx-update="stream"
                data-track-positions
              >
                <.offer
                  :for={{dom_id, offer} <- @streams.offers_out_of_stock}
                  id={dom_id}
                  offer={offer}
                  location={@location}
                  today={@page.today}
                />
              </ul>
            </details>
            <p id="offer-disclaimer" class="guide-note offer-disclaimer">
              <.fluent_icon name={:shield_error} />
              {gettext(
                "Jesteśmy niezależnym agregatorem: nie sprzedajemy produktów i nie weryfikujemy sklepów. Zanim zapłacisz, sprawdź sklep – opinie, dane firmy i regulamin."
              )}
            </p>
          </section>

          <%!-- A booster's card list says what it holds better than "we do not know". --%>
          <.contents
            :if={@page.product.contents || is_nil(@page.booster_set)}
            contents={@page.product.contents}
            boosters={@page.boosters}
          />

          <.deck_list
            :for={{deck, index} <- deck_lists(@page.product.contents)}
            deck={deck}
            index={index}
          />

          <%= if @page.booster_set do %>
            <.pull_rates
              pull_rates={@page.booster_set.pull_rates}
              standard_pack_size={@page.booster_set.standard_pack_size}
              smaller_pack?={@page.booster_set.smaller_pack?}
            />
            <.set_cards
              rarities={@page.booster_set.rarities}
              cards_per_pack={@page.booster_set.cards_per_pack}
              priced_on={@page.booster_set.priced_on}
              logo_url={@page.booster_set.logo_url}
            />
          <% end %>

          <.booster_odds :if={@page.booster_odds != []} sets={@page.booster_odds} />

          <.cardmarket_reference
            product={@page.product}
            cardmarket_pln={@page.cardmarket_pln}
            eur_pln={@page.eur_pln}
          />

          <.suggested_price :if={@page.suggested_price} suggested={@page.suggested_price} />
        </main>
        <.site_footer />
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :offer, :map, required: true
  attr :location, :map, default: nil
  attr :today, Date, required: true

  # One shop's offer. In stock is the default, so a row only says when it is
  # not, and when it was checked if that was not today.
  defp offer(assigns) do
    assigns = assign(assigns, :checked_on, DateTime.to_date(assigns.offer.last_seen_at))

    ~H"""
    <li id={@id} class={["offer", !@offer.in_stock && "offer-unavailable"]}>
      <.shop_logo shop={@offer.shop} />
      <div class="offer-shop">
        <strong>{shop_name(@offer)}</strong>
        <.offer_delivery offer={@offer} location={@location} />
      </div>
      <p class="offer-price">
        <strong>{Polish.price(@offer.price)}</strong>
        <span :if={!@offer.in_stock or @checked_on != @today} class="offer-checked">
          {offer_note(@offer.in_stock, @checked_on, @today)}
        </span>
      </p>
      <a
        href={@offer.url}
        target="_blank"
        rel="noopener nofollow"
        class="offer-link"
        data-track="shop_link_clicked"
        data-track-placement="offers"
        data-track-shop={@offer.shop}
        data-track-price={@offer.price}
        data-track-in-stock={to_string(@offer.in_stock)}
        aria-label={
          gettext("%{shop}: przejdź do sklepu (otwiera się w nowej karcie)", shop: shop_name(@offer))
        }
      >{gettext("Do sklepu")}</a>
    </li>
    """
  end

  defp offer_note(true, checked_on, today),
    do: gettext("sprawdzono %{when}", when: Polish.days_ago(checked_on, today))

  defp offer_note(false, today, today), do: gettext("brak na stanie")

  defp offer_note(false, checked_on, today),
    do: gettext("brak na stanie, sprawdzono %{when}", when: Polish.days_ago(checked_on, today))

  attr :offer, :map, required: true
  attr :location, :map, default: nil

  # What delivery adds to an offer, from the shop's published terms:
  # "dostawa od 14,99 zł · darmowa od 400 zł · odbiór osobisty: Kraków (491 km)".
  # Pickup within the radius stands out on a line of its own.
  defp offer_delivery(assigns) do
    {shop, km} =
      case Shops.fetch(assigns.offer.shop) do
        {:ok, shop} -> {shop, VisitorLocation.pickup_km(shop.key, assigns.location)}
        :error -> {nil, nil}
      end

    near? = km != nil and km <= VisitorLocation.radius_km()

    assigns =
      assign(assigns,
        shop: shop,
        km: km,
        near?: near?,
        terms: if(shop, do: delivery_terms(shop, assigns.offer.price, km, near?), else: [])
      )

    # A no-break space keeps each "·" at the end of a line, never at the start.
    ~H"""
    <span :if={@terms != []} class="offer-delivery">{Enum.join(@terms, "\u00A0· ")}</span>
    <span :if={@near?} class="offer-pickup-near">
      <.fluent_icon name={:location} />{gettext("odbiór: %{city}, %{distance}",
        city: @shop.pickup_city,
        distance: VisitorLocation.km(@km)
      )}
    </span>
    """
  end

  defp delivery_terms(shop, price, km, near?) do
    threshold = shop.free_shipping_from
    shipping = shipping(shop, price)

    # The threshold stays visible: shops often grant it for some carriers only.
    cost =
      case shipping do
        :free -> gettext("darmowa dostawa od %{amount}", amount: amount(threshold))
        {:from, from} -> gettext("dostawa od %{amount}", amount: amount(from))
        :unknown -> gettext("koszt dostawy w koszyku")
      end

    [
      cost,
      threshold && shipping != :free && gettext("darmowa od %{amount}", amount: amount(threshold)),
      pickup_term(shop.pickup_city, km, near?)
    ]
    |> Enum.filter(&is_binary/1)
  end

  # Pickup within the radius is shown on its own line instead.
  defp pickup_term(nil, _km, _near?), do: nil
  defp pickup_term(_city, _km, true), do: nil
  defp pickup_term(city, nil, false), do: gettext("odbiór osobisty: %{city}", city: city)

  defp pickup_term(city, km, false),
    do:
      gettext("odbiór osobisty: %{city} (%{distance})",
        city: city,
        distance: VisitorLocation.km(km)
      )

  defp shipping(shop, price) do
    threshold = shop.free_shipping_from

    cond do
      threshold != nil and not Decimal.lt?(price, threshold) -> :free
      shop.shipping_from -> {:from, shop.shipping_from}
      true -> :unknown
    end
  end

  # Pickup next to the verdict once the visitor has set a location in the
  # header: the cheapest in-stock pickup within the radius, or else that
  # delivery is needed and what the cheapest offer's shop charges for it.
  defp nearby(_page, nil), do: nil
  defp nearby(%{verdict: %{cheapest: nil}}, _location), do: nil

  defp nearby(%{offers: offers, verdict: %{cheapest: cheapest}}, location) do
    case offers |> Enum.filter(& &1.in_stock) |> VisitorLocation.cheapest_pickup(location) do
      %{} = pickup ->
        Map.put(pickup, :extra, Decimal.sub(pickup.offer.price, cheapest.price))

      nil ->
        delivery =
          case Shops.fetch(cheapest.shop) do
            {:ok, shop} -> shipping(shop, cheapest.price)
            :error -> :unknown
          end

        %{delivery: delivery, shop_name: Shops.name(cheapest.shop)}
    end
  end

  defp amount(value),
    do: if(Decimal.integer?(value), do: Polish.zloty(value), else: Polish.price(value))

  attr :product, :map, required: true
  attr :cardmarket_pln, :any, required: true
  attr :eur_pln, :map, default: nil

  defp cardmarket_reference(assigns) do
    ~H"""
    <section
      id="product-cardmarket"
      class="product-section cardmarket-reference"
      aria-labelledby="product-cardmarket-title"
    >
      <div class="product-section-heading">
        <h2 id="product-cardmarket-title" class="cardmarket-title">
          <img src={~p"/images/cardmarket.png"} alt="" width="24" height="24" />{gettext(
            "Cena na Cardmarket"
          )}
        </h2>
        <p :if={@product.cardmarket_price_updated_on}>
          {gettext("z %{date}", date: Polish.date(@product.cardmarket_price_updated_on))}
        </p>
      </div>
      <%= if @product.cardmarket_trend do %>
        <p id="cardmarket-trend" class="cardmarket-trend">
          {gettext("Trend:")} <strong>{Polish.eur(@product.cardmarket_trend)}</strong>
          <span :if={@cardmarket_pln}>· {Polish.zloty(@cardmarket_pln)}</span>
          ·
          <a href={cardmarket_url(@product.cardmarket_id)} target="_blank" rel="noopener nofollow">{gettext(
            "Zobacz na Cardmarket"
          )}</a>
        </p>
        <p class="guide-note">
          {gettext("Europejska giełda, bez wysyłki z innych krajów")}<span :if={@eur_pln}>{gettext("; kurs NBP %{rate} zł z %{date}" , rate: Polish.rate(@eur_pln.rate), date: Polish.date(@eur_pln.date))}</span>.
          <span :if={@product.cardmarket_added_on} id="product-added">
            {gettext("Na Cardmarket od %{date}.", date: Polish.date(@product.cardmarket_added_on))}
          </span>
        </p>
      <% else %>
        <p id="cardmarket-none" class="guide-note">
          {gettext("Cardmarket nie podaje jeszcze ceny tego produktu.")}
        </p>
      <% end %>
    </section>
    """
  end

  attr :contents, :map, required: true
  attr :boosters, :map, required: true

  defp contents(%{contents: nil} = assigns) do
    ~H"""
    <section id="product-contents" class="product-section" aria-labelledby="product-contents-title">
      <div class="product-section-heading">
        <h2 id="product-contents-title">{gettext("Co jest w środku")}</h2>
      </div>
      <p id="contents-unknown" class="guide-note">
        {gettext("Nie znamy jeszcze zawartości tego produktu.")}
      </p>
    </section>
    """
  end

  defp contents(assigns) do
    items =
      assigns.contents.items
      |> Enum.with_index()
      |> Enum.sort_by(fn {item, _index} -> item_rank(item.type) end)

    assigns =
      assign(assigns,
        items: items,
        rows: ceil(length(items) / 2)
      )

    ~H"""
    <section id="product-contents" class="product-section" aria-labelledby="product-contents-title">
      <div class="product-section-heading">
        <h2 id="product-contents-title">{gettext("Co jest w środku")}</h2>
        <p>{gettext("sprawdzono %{date}", date: Polish.date(@contents.checked_on))}</p>
      </div>
      <ul id="contents-items" class="contents-items" style={"--rows: #{@rows}"}>
        <li :for={{item, index} <- @items}>
          <span class="contents-quantity">{item.quantity}×</span>
          <span class="contents-label">
            <%= cond do %>
              <% booster = booster(item, @boosters) -> %>
                <.link navigate={~p"/produkty/#{booster.slug}"}>{item_label(item)}</.link>
              <% item.cardmarket_id -> %>
                <a
                  href={cardmarket_url(item.cardmarket_id)}
                  target="_blank"
                  rel="noopener nofollow"
                >{item_label(item)}</a>
              <% true -> %>
                {item_label(item)}
            <% end %>
            <span :if={item.set} class="contents-card-set">{item.set} {item.number}</span>
            <a
              :if={item.cards not in [nil, []]}
              href={"#deck-list-#{index}"}
              class="contents-card-set"
            >
              {gettext("lista kart talii")}
            </a>
          </span>
          <%= cond do %>
            <% image_url = CardImage.thumbnail_url(item.image) -> %>
              <img src={image_url} alt="" width="34" height="48" loading="lazy" />
            <% photo_url = CardImage.photo_url(item.photo, "thumbnail") -> %>
              <a
                href={CardImage.photo_url(item.photo, "detail")}
                class="contents-photo"
                data-photo-preview
                aria-label={gettext("Zdjęcie: %{item}", item: item_label(item))}
              >
                <img src={photo_url} alt="" height="48" loading="lazy" />
              </a>
            <% stock_url = stock_photo(item.type) -> %>
              <a
                href={stock_url}
                class="contents-photo"
                data-photo-preview
                title={gettext("Przykładowe zdjęcie")}
                aria-label={gettext("Przykładowe zdjęcie: %{item}", item: item_label(item))}
              >
                <img src={stock_url} alt="" height="48" loading="lazy" />
              </a>
            <% booster_photo = booster_photo(item, @boosters) -> %>
              <%!-- The name beside it is the link people and screen readers use. --%>
              <.link
                navigate={~p"/produkty/#{booster(item, @boosters).slug}"}
                class="contents-photo contents-photo-page"
                tabindex="-1"
                aria-hidden="true"
              >
                <img src={booster_photo} alt="" height="48" loading="lazy" />
              </.link>
            <% generic_url = generic_photo(item) -> %>
              <a
                href={generic_url}
                class="contents-photo contents-photo-generic"
                data-photo-preview
                title={gettext("Zdjęcie poglądowe z innego produktu")}
                aria-label={gettext("Zdjęcie poglądowe: %{item}", item: item_label(item))}
              >
                <img src={generic_url} alt="" height="48" loading="lazy" />
                <span class="contents-photo-note">{gettext("zdjęcie poglądowe")}</span>
              </a>
            <% true -> %>
              <span class="contents-photo-missing">{gettext("brak zdjęcia")}</span>
          <% end %>
        </li>
      </ul>
      <p class="guide-note">
        {sources_label(length(@contents.sources))}
        <%= for {url, index} <- Enum.with_index(@contents.sources) do %>
          <span :if={index > 0}>·</span>
          <a href={url} target="_blank" rel="noopener nofollow">{host(url)}</a>
        <% end %>
      </p>
      <%!-- The links stay plain links; with JavaScript their photo opens over the page. --%>
      <div id="photo-preview" phx-hook=".PhotoPreview" phx-update="ignore">
        <dialog id="photo-preview-dialog" class="photo-preview">
          <img id="photo-preview-image" alt="" />
          <button id="photo-preview-close" type="button">{gettext("Zamknij")}</button>
        </dialog>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".PhotoPreview">
        export default {
          mounted() {
            this.dialog = this.el.querySelector("dialog")
            this.image = this.dialog.querySelector("img")
            this.open = event => {
              const link = event.target.closest("a[data-photo-preview]")
              if (!link || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
              event.preventDefault()
              this.image.src = link.href
              this.image.alt = link.getAttribute("aria-label") ?? ""
              this.dialog.showModal()
            }
            document.addEventListener("click", this.open)
            // Any click closes it: on the photo, around it or on the button.
            this.dialog.addEventListener("click", () => this.dialog.close())
            this.dialog.addEventListener("close", () => this.image.removeAttribute("src"))
          },
          destroyed() { document.removeEventListener("click", this.open) }
        }
      </script>
    </section>
    """
  end

  # Fixed decks whose card list we know, by their place in the contents.
  defp deck_lists(nil), do: []

  defp deck_lists(contents) do
    for {%{type: :deck, cards: [_card | _more]} = deck, index} <- Enum.with_index(contents.items),
        do: {deck, index}
  end

  attr :deck, :map, required: true
  attr :index, :integer, required: true

  defp deck_list(assigns) do
    groups =
      assigns.deck.cards
      |> Enum.group_by(& &1.category)
      |> Enum.sort_by(fn {category, _cards} -> category_rank(category) end)
      |> Enum.map(fn {category, cards} ->
        %{category: category, cards: cards, count: cards |> Enum.map(& &1.quantity) |> Enum.sum()}
      end)

    assigns =
      assign(assigns,
        groups: groups,
        count: groups |> Enum.map(& &1.count) |> Enum.sum()
      )

    ~H"""
    <section
      id={"deck-list-#{@index}"}
      class="product-section"
      aria-labelledby={"deck-list-#{@index}-title"}
    >
      <div class="product-section-heading">
        <h2 id={"deck-list-#{@index}-title"}>{deck_title(@deck)}</h2>
        <p>{Polish.plural(@count, "karta", "karty", "kart")}</p>
      </div>
      <div :for={group <- @groups} class="deck-list-group">
        <h3>
          {category_label(group.category)} <span class="deck-list-count">{group.count}</span>
        </h3>
        <ul class="contents-items" style={"--rows: #{ceil(length(group.cards) / 2)}"}>
          <li :for={card <- group.cards}>
            <span class="contents-quantity">{card.quantity}×</span>
            <span class="contents-label">
              <a
                :if={card.cardmarket_id}
                href={cardmarket_url(card.cardmarket_id)}
                target="_blank"
                rel="noopener nofollow"
              >{card.name}</a>
              <span :if={!card.cardmarket_id}>{card.name}</span>
              <span :if={card.set} class="contents-card-set">{card.set} {card.number}</span>
            </span>
            <a
              :if={image_url = CardImage.thumbnail_url(card.image)}
              href={CardImage.detail_url(card.image)}
              class="contents-photo"
              data-photo-preview
              aria-label={gettext("Zdjęcie: %{item}", item: card.name)}
            >
              <img src={image_url} alt="" width="34" height="48" loading="lazy" />
            </a>
            <span :if={!card.image} class="contents-photo-missing">{gettext("brak zdjęcia")}</span>
          </li>
        </ul>
      </div>
      <p class="guide-note">
        {gettext(
          "Karty według listy wydawcy; set, numer i zdjęcie z TCGdex, nazwa otwiera kartę na Cardmarket."
        )}
      </p>
    </section>
    """
  end

  defp deck_title(%{name: nil}), do: gettext("Karty w talii")
  defp deck_title(%{name: deck}), do: gettext("Karty w talii %{deck}", deck: deck)

  @category_order ["Pokemon", "Trainer", "Energy"]
  defp category_rank(category),
    do: Enum.find_index(@category_order, &(&1 == category)) || length(@category_order)

  defp category_label("Pokemon"), do: gettext("Pokémon")
  defp category_label("Trainer"), do: gettext("Karty Trenera")
  defp category_label("Energy"), do: gettext("Energia")
  defp category_label(_other), do: gettext("Inne karty")

  # A booster of a named set links to our page for that set's single booster.
  defp booster(%{type: :booster, name: set}, boosters) when is_binary(set), do: boosters[set]
  defp booster(_item, _boosters), do: nil

  defp booster_photo(item, boosters) do
    case booster(item, boosters) do
      %{photo_card_url: url} when is_binary(url) -> url
      _none -> nil
    end
  end

  # Items that look the same in every product show one example picture.
  defp stock_photo(:code_card), do: ~p"/images/contents/code_card.webp"
  defp stock_photo(_type), do: nil

  # Without a photo of this product's item, a common one of that kind stands
  # in, marked as not this product's.
  @generic_photos ~w(binder booster card_dividers coin condition_markers damage_counters deck_box
                     dice energy_cards player_guide playmat sleeves sticker storage_box)a

  # A named booster's example would show another set's logo.
  defp generic_photo(%{type: :booster, name: set}) when is_binary(set), do: nil

  defp generic_photo(%{type: type}) when type in @generic_photos,
    do: ~p"/images/contents/#{"#{type}.webp"}"

  defp generic_photo(_item), do: nil

  defp item_label(%{type: :booster, name: nil}), do: gettext("booster")
  defp item_label(%{type: :booster, name: set}), do: gettext("booster %{set}", set: set)
  defp item_label(%{type: :promo_card, name: nil}), do: gettext("karta promo")

  defp item_label(%{type: :promo_card, name: card}),
    do: gettext("karta promo %{card}", card: card)

  defp item_label(%{type: :oversize_card, name: nil}), do: gettext("duża karta")

  defp item_label(%{type: :oversize_card, name: card}),
    do: gettext("duża karta %{card}", card: card)

  defp item_label(%{type: :card, name: nil}), do: gettext("karta")
  defp item_label(%{type: :card, name: card}), do: gettext("karta %{card}", card: card)
  defp item_label(%{type: :deck, name: nil}), do: gettext("talia gotowa do gry")
  defp item_label(%{type: :deck, name: deck}), do: gettext("talia %{deck}", deck: deck)
  defp item_label(%{type: :sleeves}), do: gettext("koszulki na karty")
  defp item_label(%{type: :energy_cards}), do: gettext("karty energii")
  defp item_label(%{type: :dice}), do: gettext("kość do gry")
  defp item_label(%{type: :damage_counters}), do: gettext("kości do liczenia obrażeń")
  defp item_label(%{type: :coin}), do: gettext("moneta")
  defp item_label(%{type: :condition_markers}), do: gettext("znaczniki stanów")
  defp item_label(%{type: :deck_box}), do: gettext("pudełko na talię")
  defp item_label(%{type: :storage_box}), do: gettext("pudełko na karty")
  defp item_label(%{type: :card_dividers}), do: gettext("przekładki")
  defp item_label(%{type: :player_guide}), do: gettext("przewodnik gracza")
  defp item_label(%{type: :rule_sheet}), do: gettext("zasady gry")
  defp item_label(%{type: :code_card}), do: gettext("karta z kodem do Pokémon TCG Live")
  defp item_label(%{type: :sticker}), do: gettext("naklejki")
  defp item_label(%{type: :pin}), do: gettext("przypinka")
  defp item_label(%{type: :figure}), do: gettext("figurka")
  defp item_label(%{type: :binder}), do: gettext("album")
  defp item_label(%{type: :playmat}), do: gettext("mata do gry")
  defp item_label(%{type: :other, name: name}), do: name

  # What a buyer opens comes first, the accessories after it.
  @item_order ~w(deck booster promo_card oversize_card card energy_cards)a
  defp item_rank(type), do: Enum.find_index(@item_order, &(&1 == type)) || length(@item_order)

  # Jumps to the booster sections that have something to show.
  defp booster_links(%{booster_set: nil, booster_odds: []}), do: []

  defp booster_links(%{booster_set: nil}),
    do: [{"#product-booster-odds", gettext("Szanse w całym produkcie")}]

  defp booster_links(%{booster_set: booster_set}) do
    [
      booster_set.pull_rates && {"#product-pull-rates", gettext("Szansa na drop")},
      booster_set.rarities != [] && {"#product-cards", gettext("Karty do zdobycia")}
    ]
    |> Enum.filter(& &1)
  end

  attr :pull_rates, :map, required: true
  attr :standard_pack_size, :integer, default: nil
  attr :smaller_pack?, :boolean, default: false

  defp pull_rates(%{pull_rates: nil} = assigns) do
    ~H"""
    <section
      id="product-pull-rates"
      class="product-section"
      aria-labelledby="product-pull-rates-title"
    >
      <div class="product-section-heading">
        <h2 id="product-pull-rates-title">{gettext("Szansa na drop")}</h2>
      </div>
      <.standard_pack_note count={@standard_pack_size} smaller?={@smaller_pack?} />
      <p id="pull-rates-unknown" class="guide-note">
        {gettext("Nie znamy jeszcze szans na drop w tym secie.")}
      </p>
    </section>
    """
  end

  defp pull_rates(assigns) do
    ~H"""
    <section
      id="product-pull-rates"
      class="product-section"
      aria-labelledby="product-pull-rates-title"
    >
      <div class="product-section-heading">
        <h2 id="product-pull-rates-title">{gettext("Szansa na drop")}</h2>
        <p>{gettext("sprawdzono %{date}", date: Polish.date(@pull_rates.checked_on))}</p>
      </div>
      <.standard_pack_note count={@standard_pack_size} smaller?={@smaller_pack?} />
      <p id="pull-rates-estimate" class="guide-note pull-rates-estimate">
        <.fluent_icon name={:info} />
        <span>
          {gettext("To szacunki społeczności z otwierania paczek, nie oficjalne dane wydawcy.")}
          <%= if !@smaller_pack? do %>
            {gettext("Szansa dotyczy jednej paczki.")}
          <% end %>
          <%= if Enum.any?(@pull_rates.rates, &shiny_version?/1) do %>
            {gettext("Poké Ball, Master Ball i Reverse to błyszczące wersje kart z listy poniżej.")}
          <% end %>
        </span>
      </p>
      <table id="pull-rates" class="pull-rates">
        <thead>
          <tr>
            <th scope="col">{gettext("Rzadkość")}</th>
            <th scope="col">
              <%= if @smaller_pack? and @standard_pack_size do %>
                {gettext("Szansa w paczce %{count} kart", count: @standard_pack_size)}
              <% else %>
                {gettext("Szansa w paczce")}
              <% end %>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @pull_rates.rates}>
            <th scope="row">
              <%= if row.group do %>
                <a href={"#set-cards-#{row.group}-list"}>{row.rarity}</a>
              <% else %>
                {row.rarity}
              <% end %>
              <span class="pull-rate-detail">{odds(row.rate)}</span>
              <span :if={row.rate.card} class="pull-rate-detail">
                {gettext("konkretna karta: %{name}", name: row.rate.card)}
              </span>
            </th>
            <td class="pull-rate-percent">{chance(row.rate)}</td>
          </tr>
        </tbody>
      </table>
      <p class="guide-note">
        {sources_label(length(@pull_rates.sources))}
        <%= for {source, index} <- Enum.with_index(@pull_rates.sources) do %>
          <span :if={index > 0}>·</span>
          <a href={source.url} target="_blank" rel="noopener nofollow">{host(source.url)}</a>
          <span :if={source_details(source) != []}>({Enum.join(source_details(source), ", ")})</span>
        <% end %>
      </p>
    </section>
    """
  end

  attr :count, :integer, default: nil
  attr :smaller?, :boolean, default: false

  defp standard_pack_note(assigns) do
    ~H"""
    <p :if={@smaller?} id="pull-rates-pack-size" class="guide-note">
      <%= if @count do %>
        {gettext(
          "Te szanse dotyczą zwykłej paczki %{count} kart. W tej paczce jest mniej kart, więc szanse są niższe – o ile, nie wiadomo.",
          count: @count
        )}
      <% else %>
        {gettext(
          "Te szanse dotyczą zwykłej paczki. W tej paczce jest mniej kart, więc szanse są niższe – o ile, nie wiadomo."
        )}
      <% end %>
    </p>
    """
  end

  attr :sets, :list, required: true

  defp booster_odds(assigns) do
    ~H"""
    <section
      id="product-booster-odds"
      class="product-section"
      aria-labelledby="product-booster-odds-title"
    >
      <div class="product-section-heading">
        <h2 id="product-booster-odds-title">{gettext("Szanse w całym produkcie")}</h2>
      </div>
      <p class="guide-note pull-rates-estimate">
        <.fluent_icon name={:info} />
        <span>
          {gettext(
            "Szansa, że trafisz co najmniej jedną kartę danej rzadkości, otwierając wszystkie paczki z tego produktu. To szacunki społeczności, nie dane wydawcy."
          )}
        </span>
      </p>
      <div :for={set <- @sets} id={"booster-odds-#{set.slug}"} class="booster-odds-set">
        <div class="product-section-heading">
          <h3><.link navigate={~p"/produkty/#{set.slug}"}>{set.name}</.link></h3>
        </div>
        <%= if set.pull_rates do %>
          <table class="pull-rates">
            <thead>
              <tr>
                <th scope="col">{gettext("Rzadkość")}</th>
                <th scope="col">
                  {ngettext("Szansa w %{count} paczce", "Szansa w %{count} paczkach", set.count)}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- Enum.reject(set.pull_rates.rates, &near_certain?(&1.rate, set.count))}>
                <th scope="row">
                  {row.rarity}
                  <span :if={row.rate.card} class="pull-rate-detail">
                    {gettext("konkretna karta: %{name}", name: row.rate.card)}
                  </span>
                </th>
                <td class="pull-rate-percent">{combined_chance(row.rate, set.count)}</td>
              </tr>
            </tbody>
          </table>
          <p :if={near_certain(set) != []} class="guide-note">
            {gettext("Prawie na pewno: %{rarities}.", rarities: Enum.join(near_certain(set), ", "))}
          </p>
          <p class="guide-note">
            {sources_label(length(set.pull_rates.sources))}
            <%= for {source, index} <- Enum.with_index(set.pull_rates.sources) do %>
              <span :if={index > 0}>·</span>
              <a href={source.url} target="_blank" rel="noopener nofollow">{host(source.url)}</a>
            <% end %>
          </p>
        <% else %>
          <p class="guide-note">{gettext("Nie znamy jeszcze szans na drop w tym secie.")}</p>
        <% end %>
        <p class="guide-note">
          <.link navigate={~p"/produkty/#{set.slug}" <> "#product-cards"}>
            {gettext("Karty do zdobycia")} →
          </.link>
        </p>
      </div>
    </section>
    """
  end

  # Rarities every buyer gets (in each pack, or over 99% across them all).
  defp near_certain(set),
    do: for(row <- set.pull_rates.rates, near_certain?(row.rate, set.count), do: row.rarity)

  defp near_certain?(rate, count) do
    case Rate.across_packs(rate, count) do
      :guaranteed -> true
      value when is_number(value) -> value > 99
      nil -> false
    end
  end

  defp combined_chance(rate, count) do
    case Rate.across_packs(rate, count) do
      :guaranteed -> gettext("w każdej paczce")
      nil -> gettext("Brak danych")
      value when value > 99 -> "> 99%"
      value when value < 0.01 -> "< 0,01%" |> String.replace(",", decimal_separator())
      value -> "≈ " <> percent(Decimal.from_float(value))
    end
  end

  # Rows such as "Poké Ball Rare" or "Reverse Rare" have no group of their
  # own: they are shiny versions of the cards listed below.
  defp shiny_version?(row), do: is_nil(row.group) and row.rarity =~ ~r/\b(ball|reverse)\b/i

  defp sources_label(count), do: ngettext("Źródło:", "Źródła:", count)

  # "pokebeach.com" for www.pokebeach.com.
  defp host(url), do: url |> URI.parse() |> Map.fetch!(:host) |> String.replace_prefix("www.", "")

  # "dane TCGplayer", "8 000 otwartych paczek".
  defp source_details(source) do
    [
      source.data_from && gettext("dane %{source}", source: source.data_from),
      source.sample_packs &&
        ngettext("%{count} otwarta paczka", "%{count} otwarte paczki", source.sample_packs,
          count: Polish.number(source.sample_packs)
        )
    ]
    |> Enum.filter(& &1)
  end

  # How often, said in the page's language: "1 na 5 paczek", "3 w każdej paczce".
  defp odds(rate) do
    case Rate.odds(rate) do
      {:one_in, packs, _about?} ->
        one_in(packs)

      {:per_pack, cards} ->
        gettext("%{count} w każdej paczce", count: cards)

      {:hits, _percent, hits, packs} ->
        gettext("%{hits} z %{packs} paczek", hits: decimal(hits), packs: decimal(packs))
    end
  end

  # Whole packs from 10 up ("1 na 58 paczek"), one decimal below ("1 na 2,5
  # paczki"). No "ok.": the note above the table says these are estimates.
  defp one_in(packs) do
    packs = Decimal.round(packs, if(Decimal.lt?(packs, 10), do: 1, else: 0))

    if Decimal.integer?(packs) do
      count = Decimal.to_integer(packs)
      ngettext("1 na %{count} paczkę", "1 na %{count} paczki", count, count: Polish.number(count))
    else
      gettext("1 na %{packs} paczki", packs: decimal(packs))
    end
  end

  # The chance of a pack holding the rarity: "20%", "6,5%", "0,73%"; a fixed
  # count per pack as "3×".
  defp chance(rate) do
    case Rate.odds(rate) do
      {:per_pack, cards} -> "#{cards}×"
      _odds -> rate |> Rate.percent() |> percent()
    end
  end

  defp percent(percent) do
    cond do
      Decimal.compare(percent, 10) != :lt -> percent(percent, 0)
      Decimal.compare(percent, 1) != :lt -> percent(percent, 1)
      true -> percent(percent, 2)
    end
  end

  defp percent(percent, places), do: decimal(Decimal.round(percent, places)) <> "%"

  # "1,3" in Polish, "1.3" in English, grouped: "1 081".
  defp decimal(value) do
    case value |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.split(".") do
      [whole] ->
        Polish.number(String.to_integer(whole))

      [whole, fraction] ->
        Polish.number(String.to_integer(whole)) <> decimal_separator() <> fraction
    end
  end

  defp decimal_separator,
    do: if(Gettext.get_locale(TcgCheapWeb.Gettext) == "en", do: ".", else: ",")

  attr :rarities, :list, required: true
  attr :cards_per_pack, :integer, default: nil
  attr :priced_on, Date, default: nil
  attr :logo_url, :string, default: nil

  defp set_cards(%{rarities: []} = assigns) do
    ~H"""
    <section id="product-cards" class="product-section" aria-labelledby="product-cards-title">
      <div class="product-section-heading">
        <h2 id="product-cards-title">{gettext("Karty do zdobycia")}</h2>
        <p :if={@cards_per_pack}>{cards_per_pack(@cards_per_pack)}</p>
      </div>
      <p id="cards-unknown" class="guide-note">
        {gettext("Nie mamy jeszcze listy kart z tego setu.")}
      </p>
    </section>
    """
  end

  defp set_cards(assigns) do
    assigns =
      assign(assigns, :count, assigns.rarities |> Enum.map(&length(&1.cards)) |> Enum.sum())

    ~H"""
    <section id="product-cards" class="product-section" aria-labelledby="product-cards-title">
      <div class="product-section-heading set-cards-heading">
        <h2 id="product-cards-title">{gettext("Karty do zdobycia")}</h2>
        <ul class="set-cards-facts">
          <li :if={@cards_per_pack}>{cards_per_pack(@cards_per_pack)}</li>
          <li>
            {ngettext("%{count} karta w secie", "%{count} karty w secie", @count,
              count: Polish.number(@count)
            )}
          </li>
          <li :if={@priced_on}>{gettext("Ceny: Cardmarket, w €")}</li>
        </ul>
        <img :if={@logo_url} src={@logo_url} alt="" class="set-cards-logo" />
      </div>
      <div id="set-cards" class="set-cards">
        <details
          :for={{group, index} <- Enum.with_index(@rarities)}
          id={"set-cards-#{index}"}
          class="set-cards-group"
          open={index == 0}
        >
          <summary>
            <span class="set-cards-rarity">{group.rarity || gettext("Rzadkość nieznana")}</span>
            <span class="set-cards-count">{length(group.cards)}</span>
            <.fluent_icon name={:chevron_down} class="set-cards-chevron" />
          </summary>
          <ol id={"set-cards-#{index}-list"} class={[length(group.cards) < 6 && "set-cards-short"]}>
            <li :for={card <- group.cards}>
              <span class="set-cards-number">{card.number}</span>
              <span>{card.name}</span>
              <.card_price card={card} />
            </li>
          </ol>
        </details>
      </div>
      <p class="guide-note">
        {gettext("Lista kart według TCGdex, od najrzadszych.")}
        <span :if={@priced_on} id="cards-prices-note">
          {gettext(
            "Ceny to trend na Cardmarket z %{date}, w euro, bez wysyłki z innych krajów; cena otwiera kartę na Cardmarket.",
            date: Polish.date(@priced_on)
          )}
        </span>
      </p>
    </section>
    """
  end

  attr :card, :map, required: true

  # The card's Cardmarket trend, linked to its Cardmarket page when TCGdex
  # gives the product id.
  defp card_price(%{card: %{cardmarket_id: nil}} = assigns) do
    ~H"""
    <span class="set-cards-price set-cards-no-price">{gettext("brak ceny")}</span>
    """
  end

  defp card_price(assigns) do
    price = assigns.card.cardmarket_price
    assigns = assign(assigns, :trend, price && price.trend)

    ~H"""
    <a
      href={"https://www.cardmarket.com/en/Pokemon/Products?idProduct=#{@card.cardmarket_id}"}
      class={["set-cards-price", !@trend && "set-cards-no-price"]}
      target="_blank"
      rel="noopener nofollow"
      aria-label={
        if(@trend,
          do:
            gettext("Trend %{price}: %{card} na Cardmarket (nowa karta)",
              price: Polish.eur(@trend),
              card: @card.name
            ),
          else: gettext("Brak ceny: %{card} na Cardmarket (nowa karta)", card: @card.name)
        )
      }
    >
      {if(@trend, do: Polish.eur(@trend), else: gettext("brak ceny"))}
    </a>
    """
  end

  defp cards_per_pack(count),
    do: ngettext("%{count} karta w paczce", "%{count} karty w paczce", count, count: count)

  attr :suggested, :map, required: true

  defp suggested_price(assigns) do
    ~H"""
    <section
      id="product-suggested-price"
      class="product-section cardmarket-reference"
      aria-labelledby="product-suggested-price-title"
    >
      <div class="product-section-heading">
        <h2 id="product-suggested-price-title">{gettext("Cena sugerowana")}</h2>
        <p>
          {gettext("stan na %{date}", date: Polish.date(DateTime.to_date(@suggested.last_seen_at)))}
        </p>
      </div>
      <p id="suggested-price" class="cardmarket-trend">
        {gettext("Hurtownia REBEL:")} <strong>{Polish.price(@suggested.price)}</strong>
      </p>
      <p class="guide-note">
        {gettext(
          "Cena detaliczna sugerowana w katalogu hurtowni REBEL. Sklepy ustalają ceny same, więc nie bierzemy jej pod uwagę w ocenie. Pokazujemy ją tylko dla porównania."
        )}
      </p>
    </section>
    """
  end

  defp chart_series(page) do
    [
      %{
        key: "shops",
        label: gettext("Najniższa cena w polskich sklepach"),
        class: "shops",
        points: Enum.map(page.history, &{&1.date, &1.lowest_price})
      },
      %{
        key: "cardmarket",
        label: gettext("Cardmarket (w zł)"),
        class: "cardmarket",
        points:
          Enum.map(page.history, &{&1.date, Guide.to_pln(&1.cardmarket_trend, page.eur_pln)})
      }
    ]
  end

  attr :nearby, :any, required: true

  defp nearby_line(%{nearby: %{offer: _offer}} = assigns) do
    ~H"""
    <div id="verdict-nearby" class="verdict-nearby ph-no-capture">
      <p class="verdict-nearby-label">
        {gettext("Najtaniej z odbiorem osobistym do %{radius} km",
          radius: VisitorLocation.radius_km()
        )}
      </p>
      <p class="verdict-nearby-value">
        <a
          href={@nearby.offer.url}
          target="_blank"
          rel="noopener nofollow"
          data-track="shop_link_clicked"
          data-track-placement="nearby"
          data-track-shop={@nearby.offer.shop}
          data-track-price={@nearby.offer.price}
          data-track-in-stock={to_string(@nearby.offer.in_stock)}
        >{@nearby.shop.name}</a>, {@nearby.shop.pickup_city} ·
        <strong>{VisitorLocation.km(@nearby.km)}</strong>
        · <strong>{Polish.price(@nearby.offer.price)}</strong>
        <%= if Decimal.gt?(@nearby.extra, 0) do %>
          (+{extra_zloty(@nearby.extra)})
        <% else %>
          {gettext("– najtaniej")}
        <% end %>
      </p>
    </div>
    """
  end

  defp nearby_line(assigns) do
    ~H"""
    <div id="verdict-nearby" class="verdict-nearby ph-no-capture">
      <p class="verdict-nearby-label">{gettext("Odbiór osobisty")}</p>
      <p class="verdict-nearby-value verdict-nearby-none">
        {gettext("brak do %{radius} km – potrzebna dostawa", radius: VisitorLocation.radius_km())}
      </p>
      <p :if={@nearby.delivery != :unknown} class="guide-note">
        {gettext("W %{shop} %{delivery}",
          shop: @nearby.shop_name,
          delivery: delivery_note(@nearby.delivery)
        )}
      </p>
    </div>
    """
  end

  defp delivery_note({:from, from}), do: gettext("dostawa od %{amount}", amount: amount(from))
  defp delivery_note(:free), do: gettext("dostawa gratis")

  # Whole złoty, at least 1: "+110 zł".
  defp extra_zloty(extra),
    do: extra |> Decimal.round(0) |> Decimal.to_integer() |> max(1) |> Polish.zloty()

  attr :page, :map, required: true
  attr :nearby, :any, default: nil

  # The whole answer in one place, the way flight search does it: the
  # verdict, today's price marked on a bar of the good, normal and expensive
  # ranges, one line on how it compares with the product's history, and the
  # history chart and the method behind a click.
  defp verdict_block(assigns) do
    %{verdict: verdict, past: past} = assigns.page

    assigns =
      assign(assigns,
        verdict: verdict,
        past: past,
        range: price_range(verdict),
        reason: reason(verdict, past)
      )

    ~H"""
    <section
      id="product-verdict"
      class={["verdict-block", "verdict-block-#{@verdict.status}"]}
      aria-labelledby="product-verdict-title"
    >
      <h2 id="product-verdict-title" class="sr-only">{gettext("Ocena ceny")}</h2>
      <.verdict_badge verdict={@verdict} id="verdict-badge" class="verdict-badge-large" />
      <div class="verdict-body">
        <div :if={@verdict.cheapest} class="verdict-now">
          <div>
            <p id="verdict-price" class="verdict-price">{Polish.price(@verdict.cheapest.price)}</p>
            <p id="verdict-shop" class="verdict-shop">
              {gettext("najtaniej teraz w")} <strong>{shop_name(@verdict.cheapest)}</strong>
            </p>
          </div>
          <a
            id="verdict-go"
            href={@verdict.cheapest.url}
            target="_blank"
            rel="noopener nofollow"
            class="verdict-go"
            data-track="shop_link_clicked"
            data-track-placement="verdict"
            data-track-shop={@verdict.cheapest.shop}
            data-track-price={@verdict.cheapest.price}
            data-track-in-stock="true"
          >
            {gettext("Do sklepu")}<span class="sr-only">{gettext("(otwiera się w nowej karcie)")}</span>
          </a>
        </div>
        <div :if={@range} id="verdict-range" class="verdict-range" aria-hidden="true">
          <div class="verdict-range-bar">
            <span class="verdict-range-good" style={"--to: #{@range.good_at}%"}></span>
            <span
              class="verdict-range-normal"
              style={"--from: #{@range.good_at}%; --to: #{@range.normal_at}%"}
            ></span>
            <span class="verdict-range-expensive" style={"--from: #{@range.normal_at}%"}></span>
            <span class="verdict-range-now" style={"--at: #{@range.cheapest_at}%"}></span>
          </div>
          <div class="verdict-range-limits">
            <span style={"--at: #{@range.good_at}%"}>{Polish.zloty(@verdict.good_max)}</span>
            <span style={"--at: #{@range.normal_at}%"}>{Polish.zloty(@verdict.normal_max)}</span>
          </div>
        </div>
        <p :if={@reason} id="verdict-reason" class="verdict-reason">{@reason}</p>
        <p :if={@verdict.status == :cardmarket} id="verdict-cardmarket" class="verdict-cardmarket">
          <.cardmarket_price
            price={@verdict.typical}
            href={cardmarket_url(@page.product.cardmarket_id)}
          />
          <span>{gettext("na Cardmarket, bez wysyłki")}</span>
        </p>
        <p
          :if={@past.status in [:low, :usual, :high]}
          id="verdict-past"
          class={["verdict-past", "verdict-past-#{@past.status}"]}
        >
          <.verdict_icon status={past_tone(@past.status)} />
          <span>
            <strong>{past_label(@past.status)}</strong>
            {gettext("(zwykle %{price})", price: Polish.zloty(@past.typical))}
          </span>
        </p>
        <p :if={@verdict.status == :cardmarket} id="verdict-pending" class="guide-note">
          {gettext(
            "Ocenę pokażemy, gdy produkt będzie na stanie w co najmniej %{count} sklepach.",
            count: PriceGuide.min_shops()
          )}
        </p>
        <.nearby_line :if={@nearby} nearby={@nearby} />
        <div class="verdict-more">
          <details id="verdict-history" class="verdict-method">
            <summary data-track="product_section_opened" data-track-section="price_history">
              {gettext("Historia cen")}<.fluent_icon
                name={:chevron_down}
                class="verdict-method-chevron"
              />
            </summary>
            <.price_chart
              id="price-history"
              series={chart_series(@page)}
              from={Date.add(@page.today, -(Guide.history_days() - 1))}
              to={@page.today}
              typical={@past.typical}
            />
          </details>
          <details id="verdict-method" class="verdict-method">
            <summary data-track="product_section_opened" data-track-section="verdict_method">
              {gettext("Jak liczymy?")}<.fluent_icon
                name={:chevron_down}
                class="verdict-method-chevron"
              />
            </summary>
            <p>
              {gettext(
                "Typowa cena to mediana cen w polskich sklepach, które mają produkt na stanie (z każdego sklepu jego najtańsza oferta); potrzebujemy co najmniej %{minimum} sklepów.",
                minimum: PriceGuide.min_shops()
              )}
              <span :if={@verdict.typical_source == :cardmarket} id="verdict-method-cardmarket">
                {gettext(
                  "Tylu jeszcze nie ma, więc porównujemy z trendem Cardmarket przeliczonym po kursie NBP."
                )}
              </span>
              {gettext(
                "Dobra cena to do 95% typowej, normalna – do 110%, wyższa – drogo. Progi zaokrąglamy w dół do pełnych złotych. Ceny nie obejmują wysyłki."
              )}
            </p>
            <p>
              {gettext(
                "Historia: tę samą cenę porównujemy z medianą najniższych cen z ostatnich %{window} dni, w których produkt był dostępny (co najmniej %{minimum} takich dni), z tymi samymi progami. To tylko tło: nie zmienia dzisiejszej oceny.",
                window: PriceGuide.window_days(),
                minimum: PriceGuide.min_days_with_stock()
              )}
            </p>
          </details>
        </div>
      </div>
    </section>
    """
  end

  # Where the bar's limits and today's price sit, in % of the bar: every
  # range stays wide enough to read.
  defp price_range(%{typical_source: :shops, cheapest: %{price: cheapest}} = verdict) do
    margin = (verdict.normal_max - verdict.good_max) / 2
    low = min(Decimal.to_float(cheapest), verdict.good_max - margin)
    high = max(verdict.normal_max + margin, low + 1)
    pad = (high - low) * 0.06
    {low, high} = {low - pad, high + pad}
    at = &Float.round((&1 - low) / (high - low) * 100, 2)

    %{
      good_at: at.(verdict.good_max),
      normal_at: at.(verdict.normal_max),
      cheapest_at: at.(Decimal.to_float(cheapest))
    }
  end

  defp price_range(_verdict), do: nil

  defp today_missing(%{shop_prices: []}),
    do: gettext("Teraz żaden sklep nie ma tego produktu na stanie.")

  defp today_missing(%{shop_prices: shops}),
    do:
      gettext(
        "Produkt jest teraz na stanie w %{shops}. Porównamy ceny, gdy będzie w co najmniej %{minimum} sklepach.",
        shops: Polish.plural(length(shops), "sklepie", "sklepach", "sklepach"),
        minimum: PriceGuide.min_shops()
      )

  defp past_tone(:low), do: :good
  defp past_tone(:usual), do: :normal
  defp past_tone(:high), do: :expensive

  defp past_label(status) do
    days = PriceGuide.window_days()

    case status do
      :low -> gettext("Taniej niż w ostatnich %{days} dniach", days: days)
      :usual -> gettext("Tyle co w ostatnich %{days} dniach", days: days)
      :high -> gettext("Drożej niż w ostatnich %{days} dniach", days: days)
    end
  end

  defp reason(%{status: status, typical_source: :shops} = verdict, _past)
       when status in [:good, :normal, :expensive],
       do:
         gettext("Zwykle %{low}–%{high} w %{shops}",
           low: Polish.number(verdict.good_max),
           high: Polish.zloty(verdict.normal_max),
           shops: Polish.plural(length(verdict.shop_prices), "sklepie", "sklepach", "sklepach")
         )

  # Shown as the Cardmarket price with its logo instead.
  defp reason(%{status: :cardmarket}, _past), do: nil

  defp reason(%{status: :insufficient_data} = verdict, _past) do
    today_missing(verdict) <>
      " " <>
      gettext("Cardmarket nie podaje ceny tego produktu, więc na razie go nie oceniamy.")
  end

  defp reason(%{status: :out_of_stock} = verdict, past) do
    [
      gettext("Teraz żaden sklep nie ma tego produktu na stanie."),
      last_known(past),
      usual(verdict, past)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp last_known(%{last_known: %{price: price, date: date}}),
    do:
      gettext("Ostatnio najtaniej: %{price} (%{date}).",
        price: Polish.price(price),
        date: Polish.date(date)
      )

  defp last_known(_past), do: nil

  defp usual(_verdict, %{typical: %Decimal{} = typical}),
    do:
      gettext("Zwykle najtaniej %{price} (mediana z ostatnich %{days} dni).",
        price: Polish.zloty(typical),
        days: PriceGuide.window_days()
      )

  defp usual(%{typical: %Decimal{} = typical, typical_source: :cardmarket}, _past),
    do: cardmarket_typical(typical)

  defp usual(_verdict, %{last_known: nil}), do: gettext("Nie znamy jeszcze jego ceny.")
  defp usual(_verdict, _past), do: nil

  defp cardmarket_typical(typical),
    do:
      gettext("Na Cardmarket %{price} (bez wysyłki).",
        price: Polish.zloty(typical)
      )
end
