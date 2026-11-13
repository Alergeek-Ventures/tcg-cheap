defmodule TcgCheap.Sealed.Sitemap do
  @moduledoc """
  The sitemap's `lastmod` dates: the day a product page's lowest in-stock
  price (`TcgCheap.Sealed.DailyPrice`) last changed. A page without history
  has no date. Card pages have none: their only daily history, the
  Cardmarket trend, changes slightly for most cards every day.
  """

  import Ecto.Query

  alias TcgCheap.Repo
  alias TcgCheap.Sealed.DailyPrice

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
