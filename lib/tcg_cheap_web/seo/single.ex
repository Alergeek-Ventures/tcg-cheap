defmodule TcgCheapWeb.SEO.Single do
  @moduledoc """
  Search metadata of a card's page. `social_image` is the designed
  link-preview card (`TcgCheapWeb.SocialImage.Single`), not the card's
  picture, which stays in the structured data.
  """

  use TcgCheapWeb, :verified_routes
  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Cards
  alias TcgCheapWeb.{Format, Paths, Region, RegionText, SEO, SocialImage, VerdictComponents}

  @doc "`page` is `TcgCheap.Cards.Guide.page/4`."
  @spec metadata(map()) :: SEO.t()
  def metadata(page) do
    card = page.card
    number = Cards.Guide.printed_number(card)
    canonical = Paths.url(page.path)
    answer = Enum.find(page.answers, & &1.cheapest)
    description = description(page, answer, number)
    card_name = "#{card.name} #{number} #{page.expansion_name}"
    short_name = "#{card.name} #{card.number} #{page.expansion_name}"
    singles? = Region.singles?(Region.current())

    SEO.compose(
      # A long name drops the set total ("014/159" → "014") before it drops
      # "cena karty Pokémon".
      SEO.fit_title([
        RegionText.card_title(card_name),
        gettext("%{card} – cena karty Pokémon", card: card_name),
        gettext("%{card} – cena karty Pokémon", card: short_name),
        card_name
      ]),
      description,
      canonical,
      # Matches Cards.Guide.sitemap_cards/1: a card without an offer leaves the
      # index until one returns. A region without singles shops has only
      # Cardmarket's price to show, so its card pages stay out of search, with
      # the home page's link preview.
      robots: if(answer && singles?, do: "index, follow", else: "noindex, follow"),
      social_image:
        if(singles?,
          do: SEO.social_image(page.path, SocialImage.Single.version(page)),
          else: SEO.home_image()
        ),
      social_image_alt: if(singles?, do: card_name, else: SEO.home_image_alt()),
      structured_data:
        SEO.json_ld(
          List.wrap(product_node(page, answer, description, canonical)) ++
            [
              SEO.breadcrumbs([
                SEO.all_products_crumb(),
                {page.expansion_name,
                 SEO.Expansion.url(card.tcgdex_set.cardmarket_expansion_id, page.expansion_name)},
                {card.name, canonical}
              ])
            ]
        )
    )
  end

  defp description(page, answer, number) do
    card = page.card

    cond do
      not Region.singles?(Region.current()) ->
        # Without singles shops the page shows Cardmarket's price alone.
        gettext("%{name} %{number}: cena na Cardmarket i warianty karty.",
          name: card.name,
          number: number
        )

      answer ->
        SEO.fit_description([
          card_description(page, card.name, number, answer),
          verdict_sentence(answer.verdict),
          gettext("Ceny, stan i warianty karty.")
        ])

      true ->
        gettext(
          "%{name} %{number}: brak ofert bez gradingu na stanie w sklepach. Sprawdź referencję Cardmarket i pozostałe oferty.",
          name: card.name,
          number: number
        )
    end
  end

  # A card no shop at home sells is priced without delivery: no "delivering
  # to <country>" where shops at home sell singles.
  defp card_description(page, name, number, answer) do
    price = Format.price(answer.cheapest.price)

    if page.abroad_only? and Region.own_singles?(Region.current()),
      do:
        gettext("%{name} %{number}: od %{price} bez dostawy.",
          name: name,
          number: number,
          price: price
        ),
      else: RegionText.card_description(name, number, price)
  end

  # "Za mało sklepów." would read as "not available" in a snippet.
  defp verdict_sentence(:few_shops), do: nil
  defp verdict_sentence(verdict), do: VerdictComponents.single_verdict_label(verdict) <> "."

  # Like a sealed product's: only current, in-stock, ungraded offers at their
  # compared price in the region's currency (a shop only listed has none), and
  # only the answer's variant, so the price range starts at the "od"
  # price the description and the page's answer state. Without an answer there's no
  # Product block, as Google requires offers on one.
  defp product_node(_page, nil, _description, _canonical), do: nil

  defp product_node(page, answer, description, canonical) do
    offers =
      for offer <- page.offers,
          offer.in_stock and is_nil(offer.grading) and offer.variant == answer.variant,
          price = page.compared[offer.id],
          do: %{offer | price: price}

    product = %{
      "@type" => "Product",
      "name" =>
        "#{page.card.name} #{Cards.Guide.printed_number(page.card)} #{page.expansion_name}",
      "description" => description,
      "url" => canonical,
      "category" => gettext("Karta Pokémon TCG"),
      "offers" => SEO.aggregate_offer(offers, page.market.currency, canonical)
    }

    # The card picture the page shows, from our own mirror.
    if page.image,
      do:
        Map.put(
          product,
          "image",
          unverified_url(TcgCheapWeb.Endpoint, Cards.Image.detail_url(page.image))
        ),
      else: product
  end
end
