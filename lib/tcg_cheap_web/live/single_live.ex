defmodule TcgCheapWeb.SingleLive do
  @moduledoc "A single English card, its delivered reference and current Polish shop offers."
  use TcgCheapWeb, :live_view
  use Gettext, backend: TcgCheapWeb.Gettext
  import TcgCheapWeb.GuideComponents
  alias TcgCheap.Sealed.{CardGuide, CardImage, CardReference, Guide, Matcher}
  alias TcgCheapWeb.{Polish, SEO, VisitorLocation}

  defmodule NotFound do
    @moduledoc false
    defexception message: "card not found", plug_status: 404
  end

  @impl true
  def mount(%{"slug" => set, "card_slug" => slug}, _session, socket) do
    case CardGuide.find(set, slug) do
      {:ok, card, name, path} ->
        page = CardGuide.page(card, name, path)
        seo = SEO.single(page)
        groups = Enum.group_by(page.offers, &group/1)

        {:ok,
         socket
         |> assign(
           primary: Enum.find(page.answers, & &1.cheapest) || hd(page.answers),
           page: page,
           seo: seo,
           page_title: seo.title,
           counts: Map.new(groups, fn {k, v} -> {k, length(v)} end)
         )
         |> VisitorLocation.assign_location()
         |> stream(:raw, Map.get(groups, :raw, []))
         |> stream(:unavailable, Map.get(groups, :unavailable, []))
         |> stream(:graded, Map.get(groups, :graded, []))
         |> stream(:graded_out, Map.get(groups, :graded_out, []))}

      :error ->
        raise NotFound
    end
  end

  defp group(%{grading: grade, in_stock: false}) when is_binary(grade), do: :graded_out
  defp group(%{grading: grade}) when is_binary(grade), do: :graded
  defp group(%{in_stock: true}), do: :raw
  defp group(_), do: :unavailable

  defp reference_line(price, variant) do
    trend = if variant == :reverse, do: price && price.trend_holo, else: price && price.trend
    delivered = CardReference.delivered_eur(trend)

    if delivered do
      shipping = Decimal.sub(delivered, trend)

      source =
        if Decimal.gt?(trend, 25),
          do: gettext("list polecony z Polski"),
          else: gettext("list z Niemiec")

      gettext("trend Cardmarket %{trend} + wysyłka %{shipping} (%{source})",
        trend: Polish.eur(trend),
        shipping: Polish.eur(shipping),
        source: source
      )
    end
  end

  @impl true
  def handle_event("location-" <> _ = event, params, socket) do
    socket = VisitorLocation.handle_event(event, params, socket)
    groups = Enum.group_by(socket.assigns.page.offers, &group/1)

    socket =
      Enum.reduce([:raw, :unavailable, :graded, :graded_out], socket, fn key, acc ->
        stream(acc, key, Map.get(groups, key, []), reset: true)
      end)

    {:noreply, socket}
  end

  defp pattern_label(title) do
    text = Matcher.normalize(title)

    Enum.find_value(
      [
        {~r/\bmaster\s*ball\b/, "Master Ball"},
        {~r/\b(poke\s*ball|ball pattern)\b/, "Poké Ball"},
        {~r/\bquick\s*ball\b/, "Quick Ball"},
        {~r/\bdusk\s*ball\b/, "Dusk Ball"},
        {~r/\benergy (reverse|pattern|symbol)\b/, "Energy"},
        {~r/\b(rocket reverse|team rocket s reverse)\b/, "Team Rocket"},
        {~r/\b(galaxy|galactic)\b/, "Galaxy"},
        {~r/\b(cosmos|cosmic)\b/, "Cosmos"}
      ],
      card_variant_label(:special),
      fn {pattern, label} ->
        if Regex.match?(pattern, text), do: label
      end
    )
  end

  defp condition(:mint), do: "Mint"
  defp condition(:near_mint), do: "Near Mint"
  defp condition(:excellent), do: "Excellent"
  defp condition(:good), do: "Good"
  defp condition(:light_played), do: "Light Played"
  defp condition(:played), do: "Played"
  defp condition(:poor), do: "Poor"

  defp offer_tags(offer) do
    [
      case offer.variant do
        :normal -> nil
        :reverse -> "reverse holo"
        :special -> "wzór: #{pattern_label(offer.title)}"
      end,
      offer.condition && condition(offer.condition),
      offer.grading
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp cm_product(page) do
    %{
      cardmarket_id: page.card.cardmarket_id,
      cardmarket_trend: page.price && page.price.trend,
      cardmarket_price_updated_on: page.price && page.price.priced_on,
      cardmarket_added_on: nil
    }
  end

  defp reverse_trend(page),
    do: if("reverse" in page.card.variants && page.price, do: page.price.trend_holo)

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
        <main id="single-page" class="guide-main product-page single-page">
          <.link
            id="single-set-link"
            navigate={
              SEO.expansion_path(@page.card.tcgdex_set.cardmarket_expansion_id, @page.expansion_name)
            }
            class="guide-back"
          ><.fluent_icon name={:arrow_left} />{@page.expansion_name}</.link>
          <div class="product-top">
            <div class="product-image product-hero-image single-image">
              <img
                :if={@page.image}
                src={CardImage.detail_url(@page.image)}
                alt={@page.card.name}
                width="300"
                height="420"
              />
              <svg
                :if={!@page.image}
                class="single-image-fallback"
                viewBox="0 0 100 140"
                aria-hidden="true"
              ><rect x="10" y="5" width="80" height="130" rx="4" /><rect
                x="20"
                y="22"
                width="60"
                height="50"
              /><path d="M20 90h60M20 103h45M20 116h30" /></svg>
            </div>
            <section class="product-identity single-identity" aria-labelledby="single-name">
              <h1 id="single-name">{@page.card.name}</h1>
              <p class="product-facts">
                {@page.card.rarity || gettext("Rzadkość nieznana")} · {@page.card.number}/{@page.card.tcgdex_set.official_card_count ||
                  "?"} ·
                <.link navigate={
                  SEO.expansion_path(
                    @page.card.tcgdex_set.cardmarket_expansion_id,
                    @page.expansion_name
                  )
                }>{@page.expansion_name}</.link>
              </p>
            </section>
            <.verdict_panel id="single-verdict" status={single_verdict_status(@primary.verdict)}>
              <:header>
                <span class={[
                  "verdict-badge",
                  "verdict-badge-large",
                  "verdict-#{single_verdict_status(@primary.verdict)}"
                ]}>
                  {if(@primary.cheapest,
                    do: single_verdict_label(@primary.verdict),
                    else: gettext("Brak na stanie w polskich sklepach")
                  )}<.verdict_icon status={single_verdict_status(@primary.verdict)} />
                </span>
              </:header>
              <p :if={@primary.variant != :normal} class="guide-note">
                {card_variant_label(@primary.variant)}
              </p>
              <.verdict_now :if={@primary.cheapest} offer={@primary.cheapest} prefix="single" />
              <p :if={!@primary.cheapest} id="single-empty" class="sr-only">
                {gettext("Brak na stanie w polskich sklepach")}
              </p>
              <p :if={@primary.reference} class="verdict-cardmarket">
                <.cardmarket_price
                  price={@primary.reference}
                  href={cardmarket_url(@page.card.cardmarket_id)}
                  shipping={true}
                /><span>{gettext("na Cardmarket z wysyłką")}</span>
              </p>
              <div class="verdict-more">
                <.verdict_method id="single-method">
                  <p>
                    {gettext(
                      "Cenę w Polsce porównujemy z trendem Cardmarket i wysyłką jednej karty, z tolerancją ±15%. Ceny sklepów są bez dostawy."
                    )}
                  </p>
                  <p :if={@primary.reference}>
                    {reference_line(@page.price, @primary.variant)} = {Polish.zloty(
                      @primary.reference
                    )}.
                  </p>
                  <p :if={@primary.verdict == :pennies}>
                    {gettext(
                      "Grosze w obu miejscach: karta w Polsce kosztuje najwyżej 3 zł, a wysyłka z Cardmarket więcej niż sama karta."
                    )}
                  </p>
                  <p :if={@primary.variant == :special}>
                    {gettext("Wzory specjalne nie mają wspólnej ceny referencyjnej.")}
                  </p>
                  <p :if={"firstEdition" in @page.card.variants}>
                    {gettext(
                      "Cardmarket nie rozdziela edycji. Nie wystawiamy werdyktu dla pierwszej edycji."
                    )}
                  </p>
                  <p>{gettext("Porównujemy karty bez oceny. Sprawdź wariant i stan w sklepie.")}</p>
                  <p :if={@page.rate}>
                    {gettext("Kurs NBP %{rate} zł z %{date}.",
                      rate: Polish.rate(@page.rate.rate),
                      date: Polish.date(@page.rate.date)
                    )}
                  </p>
                </.verdict_method>
              </div>
            </.verdict_panel>
          </div>
          <section id="single-offers" class="product-section" aria-labelledby="single-offers-title">
            <.offers_heading id="single-offers-title" count={@counts[:raw] || 0} />
            <ul
              id="single-raw-offers"
              class="offer-list ph-no-capture"
              phx-update="stream"
              data-track-positions
            >
              <li :if={!@counts[:raw]} id="single-offers-empty" class="guide-empty">
                {gettext("Teraz żaden sklep nie ma tej karty na stanie.")}
              </li>
              <.offer
                :for={{id, offer} <- @streams.raw}
                id={id}
                offer={offer}
                tags={offer_tags(offer)}
                location={@location}
                today={Date.utc_today()}
              />
            </ul>
            <.offers_disclosure
              :if={@counts[:unavailable]}
              id="single-unavailable"
              label={
                gettext("Bez towaru: %{offers}",
                  offers: Polish.plural(@counts.unavailable, "oferta", "oferty", "ofert")
                )
              }
            >
              <ul id="single-unavailable-offers" class="offer-list ph-no-capture" phx-update="stream">
                <.offer
                  :for={{id, offer} <- @streams.unavailable}
                  id={id}
                  offer={offer}
                  tags={offer_tags(offer)}
                  location={@location}
                  today={Date.utc_today()}
                />
              </ul>
            </.offers_disclosure>
            <.offers_disclosure
              :if={@counts[:graded] || @counts[:graded_out]}
              id="single-graded"
              label={
                gettext("Karty z oceną (PSA, CGC): %{count}",
                  count: (@counts[:graded] || 0) + (@counts[:graded_out] || 0)
                )
              }
            >
              <ul id="single-graded-offers" class="offer-list ph-no-capture" phx-update="stream">
                <.offer
                  :for={{id, offer} <- @streams.graded}
                  id={id}
                  offer={offer}
                  tags={offer_tags(offer)}
                  location={@location}
                  today={Date.utc_today()}
                />
              </ul>
              <ul id="single-graded-out-offers" class="offer-list ph-no-capture" phx-update="stream">
                <.offer
                  :for={{id, offer} <- @streams.graded_out}
                  id={id}
                  offer={offer}
                  tags={offer_tags(offer)}
                  location={@location}
                  today={Date.utc_today()}
                />
              </ul>
            </.offers_disclosure>
            <.offer_disclaimer id="single-disclaimer" />
          </section>
          <.cardmarket_reference
            id="single-cardmarket"
            product={cm_product(@page)}
            cardmarket_pln={Guide.to_pln(@page.price && @page.price.trend, @page.rate)}
            eur_pln={@page.rate}
            reverse={reverse_trend(@page)}
            reverse_pln={Guide.to_pln(reverse_trend(@page), @page.rate)}
          />
        </main>
        <.site_footer />
      </div>
    </Layouts.app>
    """
  end
end
