defmodule TcgCheapWeb.SEO.ExpensiveCards do
  @moduledoc """
  Search metadata of the expensive cards article. "najdroższe karty pokemon"
  is asked about the records and about what costs most today: the description
  answers both. A filtered ranking is the same article: canonical to it and
  not indexed on its own.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{CardRecords, Format, Paths, SEO, SocialImage}

  @doc """
  `overview` is `TcgCheap.Cards.Expensive.overview/0`, `records` the
  records ranking and `filters` the page's chosen set and stock filter.
  """
  @spec metadata(map(), [map(), ...], map()) :: SEO.t()
  def metadata(overview, records, filters) do
    canonical = Paths.url(Paths.page(:expensive_cards))
    filtered? = filters != %{set: nil, stock: :all}

    SEO.compose(
      gettext("Najdroższe karty Pokémon – rekordy i ceny dziś"),
      SEO.fit_description(answer(overview, hd(records))),
      canonical,
      robots: if(filtered?, do: "noindex, follow", else: "index, follow"),
      social_image:
        SEO.social_image(
          Paths.page(:expensive_cards),
          SocialImage.ExpensiveCards.version(overview)
        ),
      social_image_alt: gettext("Najdroższe karty Pokémon: rekordy aukcji i ceny dziś"),
      structured_data:
        SEO.json_ld([
          SEO.article(gettext("Najdroższe karty Pokémon"), overview.priced_on, canonical),
          SEO.breadcrumbs([SEO.cards_crumb(), {gettext("Najdroższe karty Pokémon"), canonical}])
        ])
    )
  end

  defp answer(overview, record) do
    [
      gettext("Najdroższa karta Pokémon w historii to %{card}: %{price} (%{grade}, %{year}).",
        card: record.name,
        price: CardRecords.usd(record.usd),
        grade: record.grade,
        year: elem(record.sold, 0)
      ),
      case overview.highlights do
        [top | _] ->
          gettext("Najdroższa karta dziś na Cardmarket: %{card}, %{value}.",
            card: top.card.name,
            value: Format.whole_price(top.value)
          )

        [] ->
          nil
      end,
      gettext("Rekordy aukcji i ceny w polskich sklepach.")
    ]
    |> Enum.filter(&is_binary/1)
  end
end
