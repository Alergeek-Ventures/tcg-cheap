defmodule TcgCheapWeb.SEO.Product do
  @moduledoc """
  Search metadata of a product's page. Poland indexes every product page;
  another region only a product its shops have in stock now (a page without
  an offer there would be thin), and only then are the two alternates.

  `social_image` is the designed link-preview card
  (`TcgCheapWeb.SocialImage.Product`), not the product photo, which stays in
  the structured data.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.{Guide, Kinds}

  alias TcgCheapWeb.{
    Format,
    OfferComponents,
    Paths,
    Region,
    RegionText,
    SEO,
    SocialImage,
    VerdictComponents
  }

  @doc "`page` is `TcgCheap.Sealed.Guide.product/3`."
  @spec metadata(map()) :: SEO.t()
  def metadata(page) do
    product = page.product
    canonical = Paths.url(Paths.product(product.slug))
    indexed = Enum.filter(Region.all(), &indexed?(&1, page))
    description = description(page)

    SEO.compose(
      SEO.fit_title(titles(page)),
      description,
      canonical,
      social_image:
        SEO.social_image(Paths.product(product.slug), SocialImage.Product.version(page)),
      social_image_alt: product.name <> ". " <> answer(page.verdict),
      robots: if(Region.current() in indexed, do: "index, follow", else: "noindex, follow"),
      alternates: SEO.alternates({:product, product.slug}, indexed),
      structured_data:
        SEO.json_ld(
          List.wrap(product_node(page, description, canonical)) ++
            [SEO.breadcrumbs(crumbs(product, canonical))]
        )
    )
  end

  # Only current, in-stock offers count, at their compared price (a shop abroad's
  # with delivery), never MSRP, Cardmarket or a last-known price. Google requires
  # offers on a Product, so without one there's no Product block.
  defp product_node(page, description, canonical) do
    case in_stock_compared(page) do
      [] ->
        nil

      offers ->
        product = page.product

        %{
          "@type" => "Product",
          "name" => product.name,
          "description" => description,
          "url" => canonical,
          "category" => Kinds.label(product.kind)
        }
        |> put_image(product)
        |> Map.put("offers", SEO.aggregate_offer(offers, page.market.currency, canonical))
    end
  end

  # Our stored copy of the packaging photo when there is one, else none.
  defp put_image(node, %{stored_photo_page_url: url}) when is_binary(url),
    do: Map.put(node, "image", url)

  defp put_image(node, _product), do: node

  # The page's in-stock offers at the prices its verdict compares (with
  # delivery from abroad); a shop only listed has none.
  defp in_stock_compared(page) do
    for offer <- page.offers,
        offer.in_stock,
        %Decimal{} = price <- [page.compared[offer.id]],
        do: %{offer | price: price}
  end

  defp indexed?(%Region{} = region, page) do
    cond do
      Region.poland?(region) -> true
      region.market == page.market -> in_stock_compared(page) != []
      true -> Guide.in_stock?(page.product.id, region.market, DateTime.utc_now())
    end
  end

  # The expansion's list sits between all products and the product.
  defp crumbs(product, canonical) do
    expansion =
      case product do
        %{cardmarket_expansion_id: id, set_name: name} when is_integer(id) and is_binary(name) ->
          [{name, SEO.Expansion.url(id, name)}]

        _no_expansion ->
          []
      end

    [SEO.all_products_crumb()] ++ expansion ++ [{product.name, canonical}]
  end

  # The answer first, as search results and AI assistants quote it: today's
  # cheapest price, where, and how it compares with the other Polish shops.
  defp description(%{product: product, verdict: verdict} = page) do
    lead =
      case {verdict.cheapest, page.preorder?} do
        {nil, _preorder?} ->
          RegionText.product_out_of_stock(product.name)

        {cheapest, true} ->
          gettext("%{name}: przedsprzedaż od %{price} w %{shop}.",
            name: product.name,
            price: Format.price(cheapest.price),
            shop: OfferComponents.priced_shop_name(cheapest)
          )

        {cheapest, false} ->
          gettext("%{name}: najtaniej teraz %{price} w %{shop}.",
            name: product.name,
            price: Format.price(cheapest.price),
            shop: OfferComponents.priced_shop_name(cheapest)
          )
      end

    [lead, comparison(verdict) | set_content(page)]
    |> Enum.reject(&is_nil/1)
    |> SEO.fit_description()
  end

  # A single booster's page also holds its set's pull rates and cards, which
  # people search for by name ("<set> drop rate", "<set> lista kart").
  defp titles(%{booster_set: %{pull_rates: %{}}, product: product}),
    do: [
      gettext("%{name} – cena, drop rate i lista kart", name: product.name),
      gettext("%{name} – cena", name: product.name),
      product.name
    ]

  defp titles(%{booster_set: %{rarities: [_ | _]}, product: product}),
    do: [
      gettext("%{name} – cena i lista kart", name: product.name),
      gettext("%{name} – cena", name: product.name),
      product.name
    ]

  defp titles(%{product: product}),
    do: [
      gettext("%{name} – ceny i oferty Pokémon TCG", name: product.name),
      gettext("%{name} – ceny i oferty", name: product.name),
      product.name
    ]

  defp set_content(%{booster_set: %{rarities: [_ | _] = rarities} = set}) do
    cards = Enum.sum_by(rarities, &length(&1.cards))

    [
      SEO.Expansion.pull_rates_summary(set.pull_rates),
      # "Lista 22 kart": the genitive after "lista", whatever the count.
      gettext("Lista %{count} kart z cenami.", count: Format.number(cards))
    ]
  end

  defp set_content(_page), do: [gettext("Porównanie cen w sklepach i historia cen.")]

  defp comparison(%{status: status, typical: typical, typical_source: :shops} = verdict)
       when status in [:good, :normal, :expensive],
       do:
         gettext("%{verdict} – typowa cena w %{shops} sklepach to %{typical}.",
           verdict: VerdictComponents.verdict_label(verdict),
           typical: Format.limit_price(typical),
           shops: length(verdict.shop_prices)
         )

  defp comparison(_verdict), do: nil

  # The answer the product's card shows, for its alt text.
  defp answer(%{cheapest: %{price: price} = cheapest} = verdict),
    do:
      gettext("%{verdict}: najtaniej teraz %{price} w %{shop}.",
        verdict: VerdictComponents.verdict_label(verdict),
        price: Format.price(price),
        shop: OfferComponents.priced_shop_name(cheapest)
      )

  defp answer(_verdict), do: gettext("Teraz żaden sklep nie ma tego produktu na stanie.")
end
