defmodule TcgCheapWeb.SEO.Single do
  @moduledoc """
  Search metadata of a card's page. `social_image` is the designed
  link-preview card (`TcgCheapWeb.SocialImage.Single`), not the card's
  picture, which stays in the structured data.
  """

  use TcgCheapWeb, :verified_routes
  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.{CardGuide, CardImage, Shops}
  alias TcgCheapWeb.{Format, Paths, RegionText, SEO, SocialImage, VerdictComponents}

  @doc "`page` is `TcgCheap.Sealed.CardGuide.page/3`."
  @spec metadata(map()) :: SEO.t()
  def metadata(page) do
    card = page.card
    number = CardGuide.printed_number(card)
    canonical = Paths.url(page.path)
    answer = Enum.find(page.answers, & &1.cheapest)
    description = description(page, answer, number)
    card_name = "#{card.name} #{number} #{page.expansion_name}"
    short_name = "#{card.name} #{card.number} #{page.expansion_name}"

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
      # Matches CardGuide.sitemap_cards/0: a card without an offer leaves the
      # index until one returns. Only Poland has offers of singles: another
      # region's page repeats the card with its Cardmarket trend alone, which
      # would be thousands of thin pages, so it stays out of search.
      robots: if(answer && SEO.polish?(), do: "index, follow", else: "noindex, follow"),
      social_image:
        if(SEO.polish?(),
          do: SEO.social_image(page.path, SocialImage.Single.version(page)),
          else: SEO.home_image()
        ),
      social_image_alt: if(SEO.polish?(), do: card_name, else: SEO.home_image_alt()),
      structured_data:
        SEO.json_ld(
          if(SEO.polish?(),
            do: List.wrap(product_node(page, answer, description, canonical)),
            else: []
          ) ++
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
      not SEO.polish?() ->
        # Singles have shop prices only in Poland: elsewhere the page shows
        # Cardmarket's.
        gettext("%{name} %{number}: cena na Cardmarket i warianty karty.",
          name: card.name,
          number: number
        )

      answer ->
        SEO.fit_description([
          gettext("%{name} %{number}: od %{price} w sklepach wysyłających do Polski.",
            name: card.name,
            number: number,
            price: Format.price(answer.cheapest.price)
          ),
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

  # "Za mało sklepów." would read as "not available" in a snippet.
  defp verdict_sentence(:few_shops), do: nil
  defp verdict_sentence(verdict), do: VerdictComponents.single_verdict_label(verdict) <> "."

  # Like a sealed product's: only current, in-stock, ungraded offers at their
  # compared price, and only the answer's variant, so the price range starts at the "od"
  # price the description and the page's answer state. Without an answer there's no
  # Product block, as Google requires offers on one.
  defp product_node(_page, nil, _description, _canonical), do: nil

  defp product_node(page, answer, description, canonical) do
    offers =
      page.offers
      |> Enum.filter(&(&1.in_stock and is_nil(&1.grading) and &1.variant == answer.variant))
      |> Shops.compared()

    product = %{
      "@type" => "Product",
      "name" => "#{page.card.name} #{CardGuide.printed_number(page.card)} #{page.expansion_name}",
      "description" => description,
      "url" => canonical,
      "category" => gettext("Karta Pokémon TCG"),
      "offers" => SEO.aggregate_offer(offers, "PLN", canonical)
    }

    # The card picture the page shows, from our own mirror.
    if page.image,
      do:
        Map.put(
          product,
          "image",
          unverified_url(TcgCheapWeb.Endpoint, CardImage.detail_url(page.image))
        ),
      else: product
  end
end
