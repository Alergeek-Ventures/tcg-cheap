defmodule TcgCheap.Sealed.Deals do
  @moduledoc """
  Today's deals as one row for the Polish home page, wherever they are sold.

  A shop deal is a product in stock at a good price, furthest under its
  typical shop price (`PriceGuide`). A retail chain's price running today (`RetailDeal`) is a
  deal by the same measure: rated against that typical price as a price seen
  in a physical shop would be, and kept only when it is a good price. A
  chain's deal without its product, or with too few shops to rate it, is
  left out here; the booster price page and the product page still list it.
  Chain prices never enter a product's verdict.
  """

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Cache, PriceGuide, Shops, Summary}

  @shop_deals 10

  @type t :: %{
          id: String.t(),
          source: {:shop, String.t()} | {:retail, Sealed.RetailDeal.t()},
          product: Sealed.Product.t(),
          price: Decimal.t(),
          typical: Decimal.t(),
          percent: pos_integer() | nil,
          photo: String.t() | nil
        }

  @doc "The deals, the biggest discount first. Shared for a few minutes."
  @spec current() :: [t()]
  def current, do: Cache.fetch(:deals, &read/0)

  @doc """
  The Polish sealed market today: how many products are in stock, how many
  of them at a good price, and the summaries of the shop deals, furthest
  under their typical price first (`deals`). Shared for a few minutes.
  """
  @spec market() :: %{deals: [Summary.t()], in_stock: non_neg_integer(), good: non_neg_integer()}
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

    # A good price always has a typical shop price to undercut; one far under
    # it is more often a wrong match than a deal.
    deals =
      good
      |> Enum.map(&{&1, Decimal.div(&1.verdict.cheapest.price, &1.verdict.typical)})
      |> Enum.filter(fn {_summary, ratio} -> Decimal.gte?(ratio, PriceGuide.deal_min_ratio()) end)
      |> Enum.sort_by(&elem(&1, 1), Decimal)
      |> Enum.map(&elem(&1, 0))
      |> Enum.take(@shop_deals)

    %{deals: deals, in_stock: length(summaries), good: length(good)}
  end

  defp read do
    now = DateTime.utc_now()
    retail = Sealed.list_current_retail_deals!(DateTime.to_date(now))
    summaries = retail |> Enum.map(& &1.product_id) |> Enum.reject(&is_nil/1) |> summaries(now)

    shop_deals = Enum.map(market().deals, &shop_deal/1)

    retail_deals =
      for deal <- retail,
          summary = Map.get(summaries, deal.product_id),
          summary && good_price?(deal.price, summary.verdict),
          do: retail_deal(deal, summary)

    (shop_deals ++ retail_deals)
    |> with_photos()
    |> Enum.sort_by(&(&1.percent || 0), :desc)
  end

  defp summaries([], _now), do: %{}

  defp summaries(ids, now) do
    [query: [filter: [id: [in: Enum.uniq(ids)]], select: Summary.fields()]]
    |> Sealed.list_products!()
    |> Summary.list(now)
    |> Map.new(&{&1.product.id, &1})
  end

  # Only a typical price from enough shops judges a chain's price: the
  # Cardmarket fallback is context, not a verdict.
  defp good_price?(price, %{typical_source: :shops, typical: %Decimal{}} = verdict),
    do: PriceGuide.rate(price, verdict, {true, false, false})

  defp good_price?(_price, _verdict), do: false

  defp shop_deal(%{product: product, verdict: verdict}) do
    %{
      id: "shop-#{product.slug}",
      source: {:shop, verdict.cheapest.shop},
      product: product,
      price: verdict.cheapest.price,
      typical: verdict.typical,
      percent: PriceGuide.discount_percent(verdict.cheapest.price, verdict.typical)
    }
  end

  defp retail_deal(deal, %{product: product, verdict: verdict}) do
    %{
      id: "retail-#{deal.id}",
      source: {:retail, deal},
      product: product,
      price: deal.price,
      typical: verdict.typical,
      percent: PriceGuide.discount_percent(deal.price, verdict.typical)
    }
  end

  # The row's box photos, read in one query.
  defp with_photos(deals) do
    ids = deals |> Enum.map(& &1.product.id) |> Enum.uniq()

    photos =
      [query: [filter: [id: [in: ids]], select: [:id]], load: [:stored_photo_card_url]]
      |> Sealed.list_products!()
      |> Map.new(&{&1.id, &1.stored_photo_card_url})

    Enum.map(deals, &Map.put(&1, :photo, Map.get(photos, &1.product.id)))
  end
end
