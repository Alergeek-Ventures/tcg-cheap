defmodule TcgCheap.Sealed.Stock do
  @moduledoc """
  Which products a market has in stock. Poland reads the availability stored
  on each product; another market derives it from its shops' current offers
  at the market's compared prices (`TcgCheap.Sealed.Market.compared/3`).
  """

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Cache, Market}

  @doc """
  The products some shop of the market has in stock now at a compared price
  (one that counts in its verdicts), as the market's lists order them.
  """
  @spec in_stock_ids(Market.t(), DateTime.t()) :: MapSet.t(Ecto.UUID.t())
  def in_stock_ids(%Market{} = market, %DateTime{} = now), do: market_stock(market, now).in_stock

  @doc "Whether some shop of the market has the product in stock now at a compared price."
  @spec in_stock?(Ecto.UUID.t(), Market.t(), DateTime.t()) :: boolean()
  def in_stock?(product_id, %Market{} = market, %DateTime{} = now) do
    now
    |> Sealed.current_offers([product_id],
      select: [:product_id, :price, :shop_price, :currency, :market_prices, :in_stock]
    )
    |> Enum.filter(& &1.in_stock)
    |> Market.compared(market, DateTime.to_date(now))
    |> Enum.any?()
  end

  @doc """
  The filter for products in stock in the market: the stored availability
  for Poland, else the ids in stock now.
  """
  @spec in_stock_filter(Market.t(), DateTime.t()) :: keyword()
  def in_stock_filter(market, now) do
    if market == Market.poland(),
      do: [available: true],
      else: [id: [in: MapSet.to_list(market_stock(market, now).in_stock)]]
  end

  @doc """
  The arguments that order the product list by stock: nil for Poland, which
  orders by the availability stored on each product; for another market, its
  products in stock and on pre-order now.
  """
  @spec list_order(Market.t(), DateTime.t()) ::
          %{in_stock: [Ecto.UUID.t()], preorder: [Ecto.UUID.t()]} | nil
  def list_order(market, now) do
    if market == Market.poland() do
      nil
    else
      stock = market_stock(market, now)
      %{in_stock: MapSet.to_list(stock.in_stock), preorder: MapSet.to_list(stock.preorder)}
    end
  end

  # The products a market's shops have in stock, and those they sell as a
  # pre-order, from their current offers at the market's compared prices: what
  # `available` and `lowest_preorder_price` store for Poland. Shared like the
  # other whole-site reads: offers change with the shop fetches, so `now` only
  # matters to the reader that computes it.
  defp market_stock(market, now) do
    Cache.fetch({:market_stock, market.code}, fn ->
      offers =
        now
        |> Sealed.current_offers(:all,
          select: [
            :product_id,
            :price,
            :shop_price,
            :currency,
            :market_prices,
            :in_stock,
            :preorder
          ]
        )
        |> Enum.filter(&(&1.product_id && (&1.in_stock or &1.preorder)))
        |> Market.compared(market, DateTime.to_date(now))

      {in_stock, preorders} = Enum.split_with(offers, & &1.in_stock)

      %{
        in_stock: MapSet.new(in_stock, & &1.product_id),
        preorder: MapSet.new(preorders, & &1.product_id)
      }
    end)
  end
end
