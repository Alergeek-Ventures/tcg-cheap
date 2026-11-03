defmodule TcgCheap.Sealed.AgentTools.ShopStatus do
  @moduledoc "What each shop's latest fetch returned and how much of it is matched."

  use Ash.Resource.Actions.Implementation

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.Shops

  @impl true
  def run(_input, _opts, _context) do
    offers = Sealed.list_offers!(query: [select: rows_fields()])
    current = Sealed.current_offers(DateTime.utc_now(), :all, select: rows_fields())

    singles =
      Sealed.list_card_offers!(query: [select: [:shop, :last_seen_at, :card_id, :in_stock]])

    current_singles = Sealed.current_card_offers()
    fetches = Sealed.latest_shop_fetches!(~U[1970-01-01 00:00:00Z])
    single_fetches = Sealed.latest_card_fetches!(~U[1970-01-01 00:00:00Z])
    by_shop = Enum.group_by(singles, & &1.shop)
    current_by_shop = Enum.group_by(current_singles, & &1.shop)

    {:ok,
     Enum.map(rows(offers, current), fn row ->
       row = empty_fetch_status(row, fetches[row.key])
       seen = latest_fetch(Map.get(by_shop, row.key, []))

       singles_status = %{
         singles_seen: length(seen),
         singles_matched: Enum.count(seen, & &1.card_id),
         singles_matched_in_stock:
           Enum.count(Map.get(current_by_shop, row.key, []), &(&1.card_id && &1.in_stock)),
         singles_last_fetch: seen |> List.first() |> then(&(&1 && &1.last_seen_at))
       }

       fetched = single_fetches[row.key]

       singles_status =
         if fetched &&
              (is_nil(singles_status.singles_last_fetch) ||
                 DateTime.compare(fetched, singles_status.singles_last_fetch) == :gt),
            do: %{
              singles_last_fetch: fetched,
              singles_seen: 0,
              singles_matched: 0,
              singles_matched_in_stock: 0
            },
            else: singles_status

       Map.merge(row, singles_status)
     end)}
  end

  defp empty_fetch_status(row, nil), do: row

  defp empty_fetch_status(row, fetched) do
    if is_nil(row.last_fetch) or DateTime.compare(fetched, row.last_fetch) == :gt,
      do: Map.merge(row, %{last_fetch: fetched, seen: 0, matched: 0}),
      else: row
  end

  @doc "The offer fields `rows/2` reads."
  @spec rows_fields() :: [atom()]
  def rows_fields, do: [:shop, :last_seen_at, :product_id, :in_stock]

  @doc "One row per configured shop, given every stored offer and the current ones."
  @spec rows([Sealed.Offer.t()], [Sealed.Offer.t()]) :: [map()]
  def rows(offers, current) do
    by_shop = Enum.group_by(offers, & &1.shop)
    current_by_shop = Enum.group_by(current, & &1.shop)

    for shop <- Shops.all() do
      seen = by_shop |> Map.get(shop.key, []) |> latest_fetch()

      %{
        key: shop.key,
        name: shop.name,
        last_fetch: seen |> List.first() |> then(&(&1 && &1.last_seen_at)),
        seen: length(seen),
        matched: Enum.count(seen, & &1.product_id),
        matched_in_stock:
          current_by_shop
          |> Map.get(shop.key, [])
          |> Enum.count(&(&1.product_id && &1.in_stock))
      }
    end
  end

  # The offers seen in a shop's latest fetch, however long ago it was.
  defp latest_fetch([]), do: []

  defp latest_fetch(offers) do
    latest = offers |> Enum.map(& &1.last_seen_at) |> Enum.max(DateTime)
    Enum.filter(offers, &(DateTime.compare(&1.last_seen_at, latest) == :eq))
  end
end
