defmodule TcgCheap.Cards.SinglesBanner do
  @moduledoc """
  The singles banner of a market, in its currency: the card a shop sells
  furthest under its Cardmarket price (with delivery where a shop at home
  competes, else the bare trend, as a singles verdict compares), how many cards are in stock in the market's shops and how many
  of them undercut Cardmarket.
  """

  alias TcgCheap.Cards.Guide
  alias TcgCheap.Sealed.{Cache, Market, PriceGuide}

  # Cards under this Cardmarket trend (20 zł, or as much in the market's
  # currency) are too cheap for a "deal" to matter.
  @deal_floor_pln Decimal.new(20)

  @doc """
  The banner across all expansions, for the card list without one: the best
  deal among the cards in stock in the market, how many there are of the
  catalogue's cards, how many undercut Cardmarket, the most valuable one and
  how many shops sell them. Shared for a few minutes.
  """
  @spec market(Market.t()) :: map()
  def market(%Market{} = market),
    do: Cache.fetch({:singles_market, market.code}, fn -> read_market(market) end)

  @doc """
  The banner of one expansion's `cards` with the `deal` among them
  (`best_deal/2`) and the `images` of the cards it shows: how many of the
  set's cards are in stock in the market and what the whole set costs at the
  lower of the two prices.
  """
  @spec of_set([map()], map() | nil, map()) :: map()
  def of_set(cards, deal, images) do
    priced = Enum.map(cards, &Guide.price/1) |> Enum.reject(&is_nil/1)

    %{
      deal: deal && deal_view(deal, images),
      in_stock: Enum.count(cards, & &1.offer_price),
      cheaper: cheaper(cards),
      total: length(cards),
      # The shops the in-stock cards come from.
      shops:
        cards |> Enum.map(&Map.get(&1, :offer_shop)) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
      # A sum missing some cards' prices would understate the set.
      set_price:
        if(priced != [] and length(priced) == length(cards),
          do: Enum.reduce(priced, &Decimal.add/2)
        )
    }
  end

  @doc """
  The card sold furthest under its Cardmarket price with delivery, nil when
  there is none. First editions have no reference of their own (see
  `Guide.card_verdict/4`).
  """
  @spec best_deal([map()], Market.t()) :: map() | nil
  def best_deal(cards, %Market{} = market) do
    case Market.pln_limit(@deal_floor_pln, market, Date.utc_today()) do
      nil -> nil
      floor -> best_deal_from(cards, floor)
    end
  end

  defp best_deal_from(cards, floor) do
    cards
    |> Enum.filter(
      &(cheaper?(&1) and "firstEdition" not in &1.variants and
          Decimal.gte?(&1.cardmarket_trend, floor))
    )
    |> Enum.map(&{&1, Decimal.div(&1.normal_offer.price, &1.cardmarket_delivered)})
    |> Enum.filter(fn {_card, ratio} -> Decimal.gte?(ratio, PriceGuide.deal_min_ratio()) end)
    |> Enum.min_by(&elem(&1, 1), Decimal, fn -> {nil, nil} end)
    |> elem(0)
  end

  defp read_market(market) do
    cards = Guide.market_cards(market)
    deal = best_deal(cards, market)
    deal = deal && Guide.with_public_identity(deal)
    top = Enum.max_by(cards, &Guide.price/1, Decimal, fn -> nil end)

    %{
      deal: deal && deal_view(deal, Guide.images([deal])),
      in_stock: length(cards),
      cheaper: cheaper(cards),
      total: Guide.catalogue_size(),
      # The whole catalogue has no price of its own, as a set does.
      set_price: nil,
      top: top && %{card: top, price: Guide.price(top)},
      shops: Guide.shop_count(market)
    }
  end

  defp deal_view(deal, images) do
    %{
      card: deal,
      price: deal.normal_offer.price,
      shop: deal.normal_offer.shop,
      abroad_only?: deal.abroad_only?,
      trend: deal.cardmarket_delivered,
      image: Map.fetch!(images, deal.id),
      path: deal.public_path
    }
  end

  defp cheaper(cards), do: Enum.count(cards, &cheaper?/1)

  defp cheaper?(%{
         normal_offer: %{price: price},
         cardmarket_delivered: %Decimal{} = delivered
       }),
       do: Decimal.lt?(price, delivered)

  defp cheaper?(_card), do: false
end
