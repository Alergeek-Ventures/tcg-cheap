defmodule TcgCheap.Sealed.SealedBanner do
  @moduledoc """
  The sealed banner, for the product list without an expansion: the product
  in stock furthest under its typical shop price today.
  """

  alias TcgCheap.Cards
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Cache, PriceGuide, Shops, Summary}

  @contents_photos 3

  @doc """
  The product in stock furthest under its typical shop price today (a good
  price, see `PriceGuide`) with its box photo and up to three photos of what
  it holds, how many products are in stock in Poland, how many of them at a
  good price, and in how many shops. Shared for a few minutes.
  """
  @spec market() :: map()
  def market, do: Cache.fetch(:sealed_market, &read_market/0)

  defp read_market do
    now = DateTime.utc_now()

    offers =
      Sealed.current_offers(now, :all, select: [:product_id, :price, :market_prices, :in_stock])
      # Unmatched offers (accessories, other games) are no product of ours.
      |> Enum.filter(&(&1.in_stock and not is_nil(&1.product_id)))
      # Only offers that count in Polish prices: not a shop only listed, nor
      # a product its shop does not sell to Poland.
      |> Shops.compared()

    summaries =
      [
        query: [
          filter: [id: [in: offers |> Enum.map(& &1.product_id) |> Enum.uniq()]],
          select: Summary.fields()
        ]
      ]
      |> Sealed.list_products!()
      |> Summary.list(now)

    good = Enum.filter(summaries, &(&1.verdict.status == :good))

    # A good price always has a typical shop price to undercut.
    deals =
      good
      |> Enum.map(&{&1, Decimal.div(&1.verdict.cheapest.price, &1.verdict.typical)})
      |> Enum.filter(fn {_summary, ratio} ->
        Decimal.gte?(ratio, PriceGuide.deal_min_ratio())
      end)
      |> Enum.sort_by(&elem(&1, 1), Decimal)
      |> Enum.map(&elem(&1, 0))

    %{
      deal: deals |> List.first() |> deal(),
      in_stock: length(summaries),
      good: length(good),
      offers: length(offers),
      shops: offers |> Enum.map(& &1.shop) |> Enum.uniq() |> length()
    }
  end

  # The deal with its own photos: the box, and what it holds where a checked
  # photo of the contents is mirrored (a deck's cards, its coin, its pin).
  defp deal(nil), do: nil

  defp deal(%{verdict: verdict, product: %{slug: slug}}) do
    product = Sealed.get_product_by_slug!(slug, load: [:stored_photo_card_url])

    %{
      product: product,
      contents_photos: contents_photos(product.contents),
      price: verdict.cheapest.price,
      shop: verdict.cheapest.shop,
      typical: verdict.typical,
      shops: length(verdict.shop_prices),
      percent: PriceGuide.discount_percent(verdict.cheapest.price, verdict.typical)
    }
  end

  defp contents_photos(nil), do: []

  defp contents_photos(contents) do
    sources =
      contents.items
      |> Enum.map(&Cards.Image.photo_source_url(&1.photo))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    mirrored =
      sources
      |> Enum.map(&Cards.Image.source_hash/1)
      |> TcgCheap.Storage.mirrored_image_urls(:thumbnail)

    sources
    |> Enum.map(&Map.get(mirrored, Cards.Image.source_hash(&1)))
    |> Enum.reject(&is_nil/1)
    |> Enum.take(@contents_photos)
  end
end
