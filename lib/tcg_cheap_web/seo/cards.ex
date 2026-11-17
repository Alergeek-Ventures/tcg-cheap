defmodule TcgCheapWeb.SEO.Cards do
  @moduledoc """
  Search metadata of the card list. It stands beside the products list as
  its equal: people search for card prices as much as for boosters. Narrowed
  by a search or an expansion it stays out of search, as the products list
  does.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{Format, Paths, RegionText, SEO, SocialImage}

  @doc """
  `market` is the region's singles market (`TcgCheap.Cards.SinglesBanner.market/1`);
  nil for a chosen expansion's list, which has no market of its own, and in
  a region without singles shops.
  """
  @spec metadata(map(), map() | nil) :: SEO.t()
  def metadata(params, market) do
    canonical = Paths.url(Paths.cards())

    SEO.compose(
      RegionText.cards_title(),
      SEO.fit_description(answer(market)),
      canonical,
      social_image:
        if(market && SEO.polish?(),
          do: SEO.social_image(Paths.cards(), SocialImage.Cards.version(market)),
          else: SEO.home_image()
        ),
      social_image_alt:
        if(market && SEO.polish?(),
          do: gettext("Ceny kart Pokémon w polskich sklepach"),
          else: SEO.home_image_alt()
        ),
      alternates: SEO.alternates(:cards),
      robots:
        if(Enum.any?(~w(q rozszerzenie), &Map.has_key?(params, &1)),
          do: "noindex, follow",
          else: "index, follow"
        ),
      structured_data:
        SEO.json_ld(%{
          "@type" => "CollectionPage",
          "name" => RegionText.cards_title(),
          "url" => canonical
        })
    )
  end

  defp answer(nil),
    do: [RegionText.cards_answer()]

  defp answer(market) do
    [
      RegionText.cards_in_stock(Format.cards(market.in_stock)),
      market.cheaper > 0 &&
        gettext("%{count} z nich taniej niż na Cardmarket z przesyłką.",
          count: Format.number(market.cheaper)
        ),
      gettext("Najniższa cena i ocena każdej karty.")
    ]
    |> Enum.filter(&is_binary/1)
  end
end
