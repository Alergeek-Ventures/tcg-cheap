defmodule TcgCheapWeb.SEO.CardValue do
  @moduledoc "Search metadata of the card value guide."

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{Format, Paths, SEO, SocialImage}

  @doc "`guide` is `TcgCheap.Cards.Value.guide/0`."
  @spec metadata(map()) :: SEO.t()
  def metadata(%{spread: spread} = guide) do
    canonical = Paths.url(Paths.page(:card_value))
    title = gettext("Jak sprawdzić wartość karty Pokémon")

    SEO.compose(
      gettext("Jak sprawdzić wartość karty Pokémon – ile jest warta twoja karta"),
      SEO.fit_description(
        [
          gettext(
            "Wpisz nazwę albo numer z dołu karty Pokémon i sprawdź, ile kosztuje w sklepach."
          ),
          spread &&
            gettext("Połowa kart kosztuje do %{median} – sprawdź, czy twoja jest wyjątkiem.",
              median: Format.whole_price_ceiling(spread.median)
            ),
          gettext("Do tego grading: kiedy się opłaca.")
        ]
        |> Enum.filter(&is_binary/1)
      ),
      canonical,
      social_image:
        SEO.social_image(Paths.page(:card_value), SocialImage.CardValue.version(guide)),
      social_image_alt:
        gettext("Ile jest warta twoja karta Pokémon: ceny kart w polskich sklepach"),
      structured_data:
        SEO.json_ld([
          SEO.article(title, spread && spread.on, canonical),
          SEO.breadcrumbs([SEO.cards_crumb(), {title, canonical}])
        ])
    )
  end
end
