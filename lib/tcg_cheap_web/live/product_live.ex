defmodule TcgCheapWeb.ProductLive do
  @moduledoc """
  One catalogue product: today's verdict, how its price compares with other
  shops today and with its own 90 days of prices, and the offers behind it.
  """

  use TcgCheapWeb, :live_view
  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.GuideComponents
  import TcgCheapWeb.SetComponents

  alias TcgCheap.Sealed.CardImage
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

        %{in_stock: in_stock, preorder: preorder, out_of_stock: out_of_stock} =
          offer_groups(page.offers)

        {:ok,
         socket
         |> assign(seo: seo, page_title: seo.title)
         |> assign(:page, page)
         |> assign(:in_stock_count, length(in_stock))
         |> assign(:preorder_count, length(preorder))
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
      preorder: page.preorder?,
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

  # Offers with stock are the list, pre-orders follow in their own; those
  # without stock wait behind a disclosure.
  defp stream_offers(socket, opts \\ []) do
    groups = offer_groups(socket.assigns.page.offers)

    socket
    |> stream(:offers, groups.in_stock, opts)
    |> stream(:offers_preorder, groups.preorder, opts)
    |> stream(:offers_out_of_stock, groups.out_of_stock, opts)
  end

  defp offer_groups(offers) do
    groups = Enum.group_by(offers, &offer_group/1)
    Map.new([:in_stock, :preorder, :out_of_stock], &{&1, Map.get(groups, &1, [])})
  end

  defp offer_group(%{in_stock: true}), do: :in_stock
  defp offer_group(%{preorder: true}), do: :preorder
  defp offer_group(_offer), do: :out_of_stock

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
          data-guide-url={@locale_return_to}
          data-track-context
          data-track-product-slug={@page.product.slug}
        >
          <.link id="product-back" data-guide-back navigate={~p"/"} class="guide-back">
            <.fluent_icon name={:arrow_left} />{gettext("Wszystkie produkty")}
          </.link>

          <div class="product-top">
            <.product_image
              photo={@page.product.stored_photo_page_url}
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
                > · <.link
                  :if={@page.product.cardmarket_expansion_id}
                  navigate={
                    SEO.expansion_path(@page.product.cardmarket_expansion_id, @page.product.set_name)
                  }
                >{@page.product.set_name}</.link><span :if={!@page.product.cardmarket_expansion_id}>{@page.product.set_name}</span></span><span id="product-region">
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
              <nav
                :if={@page.product.contents || drop_link(@page)}
                id="product-jumps"
                class="product-jumps"
                aria-label={gettext("Na tej stronie")}
              >
                <a :if={drop_link(@page)} href={drop_link(@page)}>
                  <.fluent_icon name={:data_pie} /><span>{gettext("Szansa na drop")}&nbsp;↓</span>
                </a>
                <a
                  :if={@page.product.contents}
                  id="product-inside"
                  href="#product-contents"
                  data-track="product_section_opened"
                  data-track-section="contents"
                ><.fluent_icon name={:box} /><span>{gettext("Co jest w środku")}&nbsp;↓</span></a>
              </nav>
            </section>
            <.verdict_block
              page={@page}
              nearby={if(@location_ready?, do: nearby(@page, @location))}
            />
          </div>

          <section id="product-offers" class="product-section" aria-labelledby="product-offers-title">
            <.offers_heading id="product-offers-title" count={@in_stock_count} />
            <%!-- Distances to pickup stay out of PostHog's autocapture; shop links track themselves. --%>
            <ul
              id="offer-list"
              class="offer-list ph-no-capture"
              phx-update="stream"
              data-track-positions
            >
              <%!-- Rendered only when empty: readers that skip CSS would take it for the answer. --%>
              <li :if={@in_stock_count == 0} id="offer-list-empty" class="guide-empty">
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
            <section
              :if={@preorder_count > 0}
              id="offers-preorder"
              class="offers-preorder"
              aria-labelledby="offers-preorder-title"
            >
              <h3 id="offers-preorder-title">
                {gettext("Przedsprzedaż: %{offers}",
                  offers: Polish.plural(@preorder_count, "oferta", "oferty", "ofert")
                )}
              </h3>
              <ul
                id="offer-list-preorder"
                class="offer-list ph-no-capture"
                phx-update="stream"
                data-track-positions
              >
                <.offer
                  :for={{dom_id, offer} <- @streams.offers_preorder}
                  id={dom_id}
                  offer={offer}
                  location={@location}
                  today={@page.today}
                />
              </ul>
            </section>
            <.offers_disclosure
              :if={@out_of_stock_count > 0}
              id="offers-out-of-stock"
              label={
                gettext("Bez towaru: %{offers}",
                  offers: Polish.plural(@out_of_stock_count, "oferta", "oferty", "ofert")
                )
              }
            >
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
            </.offers_disclosure>
            <.offer_disclaimer />
          </section>

          <%!-- A booster's card list says what it holds better than "we do not know". --%>
          <.contents
            :if={@page.product.contents || is_nil(@page.booster_set)}
            contents={@page.product.contents}
            boosters={@page.boosters}
            odds?={not is_nil(@page.booster_set)}
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
              cards_source_url={@page.booster_set.cards_source_url}
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

  attr :contents, :map, required: true
  attr :boosters, :map, required: true
  attr :odds?, :boolean, default: false, doc: "a single booster's page, whose pull rates follow"

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
      |> Enum.sort_by(fn {item, _index} -> item_rank(item.type, assigns.odds?) end)

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
          <span class="contents-text">
            <span class="contents-quantity">{item.quantity}×</span>
            <span class="contents-label">
              <%= cond do %>
                <% booster = booster(item, @boosters) -> %>
                  <.link navigate={~p"/produkty/#{booster.slug}"}>{item_label(item)}</.link>
                <% @odds? and item.type == :other -> %>
                  <%!-- A single booster holds only its random cards besides energy and a code: their chances are below. --%>
                  <a href="#product-pull-rates">{item_label(item)}</a>
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
              <span :if={item.variants not in [nil, []]} class="contents-card-set">
                {Enum.map_join(item.variants, " · ", & &1.name)}
              </span>
              <a
                :if={has_deck_list?(item)}
                href={"#deck-list-#{index}"}
                class="contents-card-set"
              >
                {cond do
                  item.variants not in [nil, []] -> gettext("listy kart wszystkich talii")
                  item.type == :deck -> gettext("lista kart talii")
                  true -> gettext("lista kart")
                end}
              </a>
            </span>
          </span>
          <%= cond do %>
            <% image_url = CardImage.thumbnail_url(item.image) -> %>
              <a
                href={CardImage.detail_url(item.image)}
                class="contents-photo"
                data-photo-preview
                aria-label={gettext("Zdjęcie: %{item}", item: item_label(item))}
              >
                <img src={image_url} alt="" width="34" height="48" loading="lazy" />
              </a>
            <% photo_url = CardImage.photo_url(item.photo, "thumbnail") -> %>
              <a
                href={CardImage.photo_url(item.photo, "detail")}
                class="contents-photo"
                data-photo-preview
                aria-label={gettext("Zdjęcie: %{item}", item: item_label(item))}
              >
                <img src={photo_url} alt="" height="48" loading="lazy" />
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

  # Fixed and random decks, and fixed cards of a deck-building box, whose
  # lists we know, by their place in the contents.
  defp deck_lists(nil), do: []

  defp deck_lists(contents) do
    for {deck, index} <- Enum.with_index(contents.items),
        has_deck_list?(deck),
        do: {deck, index}
  end

  defp has_deck_list?(item),
    do: item.cards not in [nil, []] or item.variants not in [nil, []]

  attr :deck, :map, required: true
  attr :index, :integer, required: true

  defp deck_list(%{deck: %{variants: [_ | _]}} = assigns) do
    ~H"""
    <section
      id={"deck-list-#{@index}"}
      class="product-section"
      aria-labelledby={"deck-list-#{@index}-title"}
    >
      <div class="product-section-heading">
        <h2 id={"deck-list-#{@index}-title"}>{gettext("Możliwe talie")}</h2>
      </div>
      <p class="guide-note">
        {random_deck_note(@deck)}
      </p>
      <%!-- Ignored by patches, so a rejoin keeps the variant shown. --%>
      <fieldset id={"deck-variants-#{@index}"} class="deck-variants" phx-update="ignore">
        <legend class="sr-only">{gettext("Pokaż skład talii")}</legend>
        <%= for {variant, variant_index} <- Enum.with_index(@deck.variants) do %>
          <input
            type="radio"
            id={"deck-variant-#{@index}-#{variant_index}"}
            name={"deck-variant-#{@index}"}
            value={variant_index}
            checked={variant_index == 0}
            class="deck-variant-radio"
            aria-controls={"deck-variant-#{@index}-#{variant_index}-cards"}
          />
          <label for={"deck-variant-#{@index}-#{variant_index}"} class="deck-variant-label">
            {variant.name}
          </label>
          <div
            id={"deck-variant-#{@index}-#{variant_index}-cards"}
            class="deck-variant-cards"
            role="region"
            aria-labelledby={"deck-variant-#{@index}-#{variant_index}"}
          >
            <.deck_card_list cards={variant.cards} name={variant.name} />
          </div>
        <% end %>
      </fieldset>
    </section>
    """
  end

  defp deck_list(assigns) do
    ~H"""
    <section
      id={"deck-list-#{@index}"}
      class="product-section"
      aria-labelledby={"deck-list-#{@index}-title"}
    >
      <div class="product-section-heading">
        <h2 id={"deck-list-#{@index}-title"}>{deck_title(@deck)}</h2>
        <p>
          {Polish.plural(Enum.sum(Enum.map(@deck.cards, & &1.quantity)), "karta", "karty", "kart")}
        </p>
      </div>
      <.deck_card_list cards={@deck.cards} show_count={false} />
    </section>
    """
  end

  attr :cards, :list, required: true
  attr :name, :string, default: nil
  attr :show_count, :boolean, default: true

  defp deck_card_list(assigns) do
    groups =
      assigns.cards
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
    <div class="deck-card-list">
      <p :if={@show_count} class="deck-variant-count">
        {gettext("Talia %{deck}", deck: @name)} · {Polish.plural(@count, "karta", "karty", "kart")}
      </p>
      <div :for={group <- @groups} class="deck-list-group">
        <h3>
          {category_label(group.category)} <span class="deck-list-count">{group.count}</span>
        </h3>
        <ul class="contents-items" style={"--rows: #{ceil(length(group.cards) / 2)}"}>
          <li :for={card <- group.cards}>
            <span class="contents-text">
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
            </span>
            <%= cond do %>
              <% image_url = CardImage.thumbnail_url(card.image) -> %>
                <a
                  href={CardImage.detail_url(card.image)}
                  class="contents-photo"
                  data-photo-preview
                  aria-label={gettext("Zdjęcie: %{item}", item: card.name)}
                >
                  <img src={image_url} alt="" width="34" height="48" loading="lazy" />
                </a>
              <% photo_url = CardImage.photo_url(card.photo, "thumbnail") -> %>
                <a
                  href={CardImage.photo_url(card.photo, "detail")}
                  class="contents-photo"
                  data-photo-preview
                  aria-label={gettext("Zdjęcie: %{item}", item: card.name)}
                >
                  <img src={photo_url} alt="" width="34" height="48" loading="lazy" />
                </a>
              <% true -> %>
            <% end %>
          </li>
        </ul>
      </div>
      <p class="guide-note">
        {gettext(
          "Karty według listy wydawcy; set, numer i zdjęcie z TCGdex lub innych źródeł, nazwa otwiera kartę na Cardmarket."
        )}
      </p>
    </div>
    """
  end

  defp deck_title(%{type: type}) when type != :deck, do: gettext("Karty w zestawie")
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
      %{stored_photo_small_url: url} when is_binary(url) -> url
      %{stored_photo_card_url: url} when is_binary(url) -> url
      _none -> nil
    end
  end

  # Without a photo of this product's item, a common one of that kind stands
  # in, marked as not this product's.
  @generic_photos ~w(binder booster card_dividers code_card coin condition_markers damage_counters
                     deck_box dice energy_cards player_guide playmat sleeves sticker storage_box)a

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

  defp item_label(%{type: :deck, variants: [_ | _] = variants}),
    do: gettext("talia losowa (1 z %{count})", count: length(variants))

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

  # A box holds one deck the publisher drew; a display holds several, each drawn.
  defp random_deck_note(%{quantity: 1, variants: variants}),
    do:
      gettext(
        "W pudełku jest jedna z tych %{count} talii, wylosowana przez producenta – nie da się jej wybrać. Sprawdź skład każdej:",
        count: length(variants)
      )

  defp random_deck_note(%{quantity: quantity, variants: variants}),
    do:
      gettext(
        "Każda z %{quantity} talii to jedna z tych %{count}, wylosowana przez producenta – nie da się ich wybrać. Sprawdź skład każdej:",
        quantity: quantity,
        count: length(variants)
      )

  # What a buyer opens comes first, the accessories after it.
  @item_order ~w(deck booster promo_card oversize_card card energy_cards)a
  # A single booster lists its random cards first, then the energy and the code.
  defp item_rank(:other, true = _odds?), do: -1

  defp item_rank(type, _odds?),
    do: Enum.find_index(@item_order, &(&1 == type)) || length(@item_order)

  # The jump to the odds: a booster's own, or those of the packs in a box.
  defp drop_link(%{booster_set: nil, booster_odds: []}), do: nil
  defp drop_link(%{booster_set: nil}), do: "#product-booster-odds"
  defp drop_link(%{booster_set: %{pull_rates: nil}}), do: nil
  defp drop_link(_page), do: "#product-pull-rates"

  attr :sets, :list, required: true

  defp booster_odds(assigns) do
    ~H"""
    <section
      id="product-booster-odds"
      class="product-section"
      aria-labelledby="product-booster-odds-title"
    >
      <div class="product-section-heading">
        <h2 id="product-booster-odds-title">{gettext("Szansa na drop")}</h2>
      </div>
      <div :for={set <- @sets} id={"booster-odds-#{set.slug}"} class="booster-odds-set">
        <h3>{set.name}</h3>
        <%= if set.pull_rates do %>
          <.borrowed_note from={set.pull_rates.borrowed_from} />
          <table class="pull-rates">
            <thead>
              <tr>
                <th scope="col">{gettext("Rzadkość")}</th>
                <th scope="col">
                  {ngettext("W %{count} paczce", "W %{count} paczkach", set.count)}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- set.pull_rates.rates}>
                <th scope="row">
                  <%= if row.group do %>
                    <a href={"#booster-odds-#{set.slug}-cards-#{row.group}-list"}>{row.rarity}</a>
                  <% else %>
                    {row.rarity}
                  <% end %>
                  <span :if={row.rate.card} class="pull-rate-detail">
                    {gettext("konkretna karta: %{name}", name: row.rate.card)}
                  </span>
                </th>
                <td class="pull-rate-percent">{combined_chance(row.rate, set.count)}</td>
              </tr>
            </tbody>
          </table>
          <div class="table-notes">
            <p class="guide-note pull-rates-estimate">
              <.fluent_icon name={:info} />
              <span>{gettext("To szacunki społeczności")}</span>
            </p>
            <p class="guide-note table-sources">
              {sources_label(length(set.pull_rates.sources))}
              <%= for {source, index} <- Enum.with_index(set.pull_rates.sources) do %>
                <span :if={index > 0}>·</span>
                <a href={source.url} target="_blank" rel="noopener nofollow">{host(source.url)}</a>
              <% end %>
            </p>
          </div>
        <% else %>
          <p class="guide-note">{gettext("Nie znamy jeszcze szans na drop w tym secie.")}</p>
        <% end %>
        <%= if set.rarities != [] do %>
          <h4 class="booster-odds-cards-title">
            {gettext("Karty do zdobycia")}
            <span class="heading-count">{set_card_count(set.rarities)}</span>
          </h4>
          <.rarity_cards
            id={"booster-odds-#{set.slug}-cards"}
            rarities={set.rarities}
            cards_source_url={set.cards_source_url}
            priced_on={set.priced_on}
            open_first?={false}
          />
        <% end %>
      </div>
    </section>
    """
  end

  defp combined_chance(rate, count) do
    case Rate.across_packs(rate, count) do
      :guaranteed -> gettext("w każdej paczce")
      nil -> gettext("Brak danych")
      value when value > 99 -> "> 99%"
      value when value < 0.01 -> "< " <> Polish.decimal(Decimal.new("0.01")) <> "%"
      value -> "≈ " <> percent(Decimal.from_float(value))
    end
  end

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
          "Cena detaliczna sugerowana w katalogu hurtowni REBEL. Sklepy ustalają ceny same, więc nie bierzemy jej pod uwagę w ocenie."
        )}
      </p>
      <p class="reference-link">
        <a href={@suggested.url} target="_blank" rel="noopener nofollow">
          {gettext("Zobacz w REBEL")} →
        </a>
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
        reason: reason(verdict, past),
        good_bound: good_bound(verdict, assigns.page.cardmarket_delivered_pln)
      )

    ~H"""
    <.verdict_panel id="product-verdict" status={@verdict.status}>
      <:header>
        <.verdict_badge verdict={@verdict} id="verdict-badge" class="verdict-badge-large" />
      </:header>
      <.verdict_now :if={@verdict.cheapest} offer={@verdict.cheapest} preorder?={@page.preorder?} />
      <p :if={@page.preorder?} id="verdict-preorder" class="verdict-preorder-note">
        <.verdict_icon status={:preorder} />
        <span>{preorder_note(@page.premiere, @page.premiere_in)}</span>
      </p>
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
      <p :if={@good_bound} id="verdict-good-bound" class="verdict-reason">{@good_bound}</p>
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
        {if(@page.preorder?,
          do:
            gettext(
              "Ocenę pokażemy, gdy produkt będzie w przedsprzedaży w co najmniej %{count} sklepach.",
              count: PriceGuide.min_shops()
            ),
          else:
            gettext(
              "Ocenę pokażemy, gdy produkt będzie na stanie w co najmniej %{count} sklepach.",
              count: PriceGuide.min_shops()
            )
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
        <.verdict_method id="verdict-method">
          <p>
            {gettext(
              "Typowa cena to środek stawki: z każdego sklepu, który ma produkt na stanie, bierzemy najtańszą ofertę (potrzebujemy co najmniej %{minimum} sklepów).",
              minimum: PriceGuide.min_shops()
            )}
            <span :if={@verdict.typical_source == :cardmarket} id="verdict-method-cardmarket">
              {gettext(
                "Tylu jeszcze nie ma, więc porównujemy z trendem Cardmarket przeliczonym po kursie NBP."
              )}
            </span>
            <span :if={@page.preorder?} id="verdict-method-preorder">
              {gettext(
                "Gdy żaden sklep nie ma produktu na stanie, liczymy tak samo z ofert przedsprzedaży."
              )}
            </span>
          </p>
          <p>
            {gettext(
              "Dobra cena jest co najmniej 5% niższa od typowej, od zwykłej z ostatnich %{window} dni i od Cardmarket z wysyłką. Normalna – najwyżej 10% wyższa od typowej. Wyższa – drogo.",
              window: PriceGuide.window_days()
            )}
          </p>
          <p>
            {gettext(
              "Ceny w sklepach są bez wysyłki. Do Cardmarket doliczamy %{shipping} za paczkę z Niemiec.",
              shipping: Polish.eur(Guide.cardmarket_shipping_eur())
            )}
          </p>
        </.verdict_method>
      </div>
    </.verdict_panel>
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

  defp today_missing(%{shop_prices: shops, cheapest: %{preorder: true}}),
    do:
      gettext(
        "Produkt jest teraz w przedsprzedaży w %{shops}. Porównamy ceny, gdy będzie w co najmniej %{minimum} sklepach.",
        shops: Polish.plural(length(shops), "sklepie", "sklepach", "sklepach"),
        minimum: PriceGuide.min_shops()
      )

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
         gettext("Typowa cena dziś w %{shops}: %{price}",
           shops: Polish.plural(length(verdict.shop_prices), "sklepie", "sklepach", "sklepach"),
           price: Polish.zloty(verdict.typical)
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

  # Buying is a pre-order: the shops ship on the premiere, the same day for all.
  defp preorder_note(nil, nil), do: gettext("To przedsprzedaż: sklep wyśle produkt po premierze.")

  defp preorder_note(premiere, days),
    do:
      gettext("Przedsprzedaż: premiera %{when} (%{date}), wtedy sklepy wyślą zamówienia.",
        when: Polish.days_until(days),
        date: Polish.day_month(premiere)
      )

  # Why the good limit is below the shops' one, when the history or
  # Cardmarket lowers it.
  defp good_bound(%{good_limits: %{shops: shops} = limits, good_max: good_max}, cardmarket)
       when good_max < shops do
    case Enum.find([:past, :cardmarket], &(limits[&1] == good_max)) do
      :past ->
        gettext("Dobra cena: do %{price}, bo w ostatnich %{days} dniach bywało taniej.",
          price: Polish.zloty(good_max),
          days: PriceGuide.window_days()
        )

      :cardmarket ->
        gettext("Dobra cena: do %{price}, bo na Cardmarket z wysyłką wychodzi ok. %{cardmarket}.",
          price: Polish.zloty(good_max),
          cardmarket: Polish.zloty(cardmarket)
        )
    end
  end

  defp good_bound(_verdict, _cardmarket), do: nil

  defp last_known(%{last_known: %{price: price, date: date}}),
    do:
      gettext("Ostatnio najtaniej: %{price} (%{date}).",
        price: Polish.price(price),
        date: Polish.date(date)
      )

  defp last_known(_past), do: nil

  defp usual(_verdict, %{typical: %Decimal{} = typical}),
    do:
      gettext("Zwykle najtaniej %{price} w ostatnich %{days} dniach.",
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
