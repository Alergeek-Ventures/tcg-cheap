defmodule TcgCheapWeb.SEO.BoosterPrices do
  @moduledoc """
  Search metadata of the booster price page. People ask what a booster
  costs, also in the chains ("ile kosztuje booster pokemon w żabce"): the
  answer is today's cheapest English booster.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.{Format, OfferComponents, Paths, SEO, SocialImage}

  @doc "`page` is `TcgCheap.Sealed.Guide.booster_prices/1`."
  @spec metadata(map()) :: SEO.t()
  def metadata(page) do
    canonical = Paths.url(Paths.page(:booster_prices))

    SEO.compose(
      gettext("Ile kosztuje booster Pokémon? Ceny w Polsce"),
      SEO.fit_description(
        List.insert_at(
          answer(page),
          1,
          gettext("Co jest w ETB, blistrach i puszkach i ile dopłacasz za dodatki.")
        )
      ),
      canonical,
      social_image:
        SEO.social_image(Paths.page(:booster_prices), SocialImage.BoosterPrices.version(page)),
      social_image_alt: gettext("Ile kosztuje booster Pokémon: najtańsze boostery w sklepach"),
      structured_data:
        SEO.json_ld([
          SEO.article(gettext("Ile kosztuje booster Pokémon?"), page.today, canonical),
          SEO.breadcrumbs([
            SEO.all_products_crumb(),
            {gettext("Ile kosztuje booster"), canonical}
          ])
        ])
    )
  end

  @doc """
  The page's answer, in sentences: the cheapest booster of the recent English
  sets in a Polish shop today and the newest set's booster. The chains'
  prices stay in their own list: they are not all boosters.
  """
  @spec answer(%{
          :boosters => list(),
          :cheapest => map() | nil,
          optional(atom()) => any()
        }) :: [String.t()]
  def answer(%{cheapest: nil}),
    do: [gettext("Teraz żaden polski sklep nie ma angielskiego boostera na stanie.")]

  def answer(%{boosters: [newest | _], cheapest: cheapest}) do
    [
      gettext(
        "Booster z ostatnich angielskich setów kosztuje dziś od %{price} (%{product}, %{shop}).",
        price: Format.price(cheapest.verdict.cheapest.price),
        product: cheapest.product.name,
        shop: OfferComponents.priced_shop_name(cheapest.verdict.cheapest)
      ),
      gettext("Najnowszy set w sklepach, %{set}: od %{price}.",
        set: newest.product.set_name,
        price: Format.price(newest.verdict.cheapest.price)
      )
    ]
  end
end
