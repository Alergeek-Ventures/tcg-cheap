defmodule TcgCheap.Sealed.Sitemap do
  @moduledoc """
  The sitemap's `lastmod` dates: the day a page's price last changed, from
  the daily histories. A product's page shows its lowest in-stock price
  (`TcgCheap.Sealed.DailyPrice`); a card's history is its Cardmarket trend
  (`TcgCheap.Sealed.CardDailyPrice`), the only price of a card we keep by
  day. A page without history has no date.
  """

  import Ecto.Query

  alias TcgCheap.Repo
  alias TcgCheap.Sealed.{CardDailyPrice, DailyPrice}

  @doc "The day each product's lowest price last changed, by product id."
  @spec product_dates([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => Date.t()}
  def product_dates([]), do: %{}

  def product_dates(ids) do
    from(d in DailyPrice,
      where: d.product_id in ^ids,
      windows: [history: [partition_by: d.product_id, order_by: d.date]],
      select: %{
        key: d.product_id,
        day: d.date,
        price: d.lowest_price,
        previous: over(lag(d.lowest_price), :history),
        nth: over(row_number(), :history)
      }
    )
    |> last_change()
  end

  @doc "The day each card's Cardmarket trend last changed, by Cardmarket product id."
  @spec card_dates([integer()]) :: %{integer() => Date.t()}
  def card_dates([]), do: %{}

  def card_dates(cardmarket_ids) do
    from(d in CardDailyPrice,
      where: d.cardmarket_id in ^cardmarket_ids,
      windows: [history: [partition_by: d.cardmarket_id, order_by: d.priced_on]],
      select: %{
        key: d.cardmarket_id,
        day: d.priced_on,
        price: d.trend,
        previous: over(lag(d.trend), :history),
        nth: over(row_number(), :history)
      }
    )
    |> last_change()
  end

  # The first day of a history counts as a change: the page got its price.
  defp last_change(history) do
    from(h in subquery(history),
      where: h.nth == 1 or fragment("? IS DISTINCT FROM ?", h.price, h.previous),
      group_by: h.key,
      select: {h.key, max(h.day)}
    )
    |> Repo.all()
    |> Map.new()
  end
end
