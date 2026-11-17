defmodule TcgCheapWeb.ProductLive do
  @moduledoc """
  One catalogue product: today's verdict, how its price compares with other
  shops today and with its own 90 days of prices, and the offers behind it.
  """

  use TcgCheapWeb, :live_view

  use Gettext, backend: TcgCheapWeb.Gettext

  import TcgCheapWeb.ContentsComponents
  import TcgCheapWeb.ListingComponents
  import TcgCheapWeb.OfferComponents
  import TcgCheapWeb.ProductLive.VerdictBlock
  import TcgCheapWeb.RetailComponents
  import TcgCheapWeb.SetComponents
  import TcgCheapWeb.SiteComponents
  import TcgCheapWeb.VerdictComponents

  alias TcgCheap.Sealed.{Editions, Kinds, ProductPage, RetailDeal}
  alias TcgCheapWeb.{Analytics, Format, Languages, Paths, SEO, VisitorLocation}

  defmodule NotFound do
    @moduledoc false
    defexception message: "product not found", plug_status: 404
  end

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    market = socket.assigns.region.market

    case ProductPage.read(slug, DateTime.utc_now(), market) do
      {:ok, page} ->
        seo = SEO.Product.metadata(page)

        %{in_stock: in_stock, preorder: preorder, out_of_stock: out_of_stock} =
          offer_groups(page.offers)

        {:ok,
         socket
         |> assign(seo: seo, page_title: seo.page_title)
         |> assign(:page, page)
         |> assign(:in_stock_count, length(in_stock))
         |> assign(:preorder_count, length(preorder))
         |> assign(:out_of_stock_count, length(out_of_stock))
         |> assign(:from_set, from_set(page.product, in_stock, market))
         |> VisitorLocation.assign_location()
         |> stream_offers()
         |> track_view(page)}

      :error ->
        raise NotFound
    end
  end

  # A product nobody has in stock sends the visitor to what its set has
  # instead, nil when it has nothing or the product names no set.
  defp from_set(%{set_name: name} = product, [], market) when is_binary(name) do
    case ProductPage.in_stock_from_set(product, DateTime.utc_now(), market) do
      %{products: [], cards: 0} -> nil
      from_set -> from_set
    end
  end

  defp from_set(_product, _in_stock, _market), do: nil

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
      # Events name the edition `region`, as they always have.
      region: product.edition,
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
        <.site_header
          region={@region}
          locale={@locale}
          current_path={@current_path}
          region_hint={@region_hint}
        >
          <VisitorLocation.location_control
            :if={VisitorLocation.pickup?()}
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
          data-guide-url={@current_path}
          data-track-context
          data-track-product-slug={@page.product.slug}
        >
          <.link id="product-back" data-guide-back navigate={Paths.products()} class="guide-back">
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
                    SEO.Expansion.path(@page.product.cardmarket_expansion_id, @page.product.set_name)
                  }
                >{@page.product.set_name}</.link><span :if={!@page.product.cardmarket_expansion_id}>{@page.product.set_name}</span></span><span id="product-region">
                  {gettext("· wersja %{edition}",
                    edition:
                      Languages.get(@locale).mid_sentence(Editions.label(@page.product.edition))
                  )}
                </span>
              </p>
              <p :if={@page.suggested_price} id="product-suggested" class="product-facts">
                {gettext("Cena sugerowana (REBEL): %{price}",
                  price: Format.price(@page.suggested_price.price)
                )} ·
                <a
                  href="#product-suggested-price"
                  data-track="product_section_opened"
                  data-track-section="suggested_price"
                >{gettext("skąd ta cena?")}</a>
              </p>
              <p :if={@page.retail_deals != []} id="product-retail-deal" class="product-facts">
                {retail_deal_line(@page.retail_deals)} ·
                <a
                  href="#product-retail-deals"
                  data-track="product_section_opened"
                  data-track-section="retail_deals"
                >{gettext("zobacz")}&nbsp;↓</a>
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
                compared={@page.compared[offer.id]}
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
                  offers: Format.offers(@preorder_count)
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
                  compared={@page.compared[offer.id]}
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
                  offers: Format.offers(@out_of_stock_count)
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
                  compared={@page.compared[offer.id]}
                  location={@location}
                  today={@page.today}
                />
              </ul>
            </.offers_disclosure>
            <.offer_disclaimer />
          </section>

          <section
            :if={@from_set}
            id="product-from-set"
            class="product-section"
            aria-labelledby="product-from-set-title"
          >
            <div class="product-section-heading">
              <h2 id="product-from-set-title">
                {gettext("Na stanie z %{set}", set: @page.product.set_name)}
              </h2>
            </div>
            <ul :if={@from_set.products != []} class="guide-products">
              <li :for={summary <- @from_set.products} class="guide-product">
                <.product_row summary={summary} />
              </li>
            </ul>
            <p :if={@from_set.cards > 0} id="product-from-set-cards" class="product-facts">
              <.link navigate={
                SEO.Expansion.path(@page.product.cardmarket_expansion_id, @page.product.set_name)
              }>
                {gettext("Pojedyncze karty: %{cards}",
                  cards: Format.cards(@from_set.cards)
                )}
              </.link>
            </p>
          </section>

          <.retail_deals
            :if={@page.retail_deals != []}
            id="product-retail-deals"
            title={gettext("W sieciówkach")}
            deals={@page.retail_deals}
          />

          <%!-- A booster's card list says what it holds better than "we do not know". --%>
          <.contents
            :if={@page.product.contents || is_nil(@page.booster_set)}
            contents={@page.product.contents}
            boosters={@page.boosters}
            odds?={not is_nil(@page.booster_set)}
            listed_on={@page.product.cardmarket_added_on}
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
            cardmarket_price={@page.cardmarket_price}
            eur_rate={@page.eur_rate}
          />

          <.suggested_price :if={@page.suggested_price} suggested={@page.suggested_price} />
        </main>
        <.site_footer sets={@footer_sets} />
      </div>
    </Layouts.app>
    """
  end

  # Chain and days first: a leaflet price, not the cheapest price the verdict states.
  defp retail_deal_line([deal]),
    do:
      gettext("%{chain}, %{days}: %{price}",
        chain: RetailDeal.chain_name(deal.chain),
        days: Format.days(deal.starts_on, deal.ends_on),
        price: Format.price(deal.price)
      )

  defp retail_deal_line(deals),
    do:
      gettext("W sieciówkach: %{prices}",
        prices:
          ngettext("%{number} cena z gazetki", "%{number} ceny z gazetek", length(deals),
            number: Format.number(length(deals))
          )
      )

  # The jump to the odds: a booster's own, or those of the packs in a box.
  defp drop_link(%{booster_set: nil, booster_odds: []}), do: nil
  defp drop_link(%{booster_set: nil}), do: "#product-booster-odds"
  defp drop_link(%{booster_set: %{pull_rates: nil}}), do: nil
  defp drop_link(_page), do: "#product-pull-rates"

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
          {gettext("stan na %{date}", date: Format.date(DateTime.to_date(@suggested.last_seen_at)))}
        </p>
      </div>
      <p id="suggested-price" class="cardmarket-trend">
        {gettext("Hurtownia REBEL:")} <strong>{Format.price(@suggested.price)}</strong>
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
end
