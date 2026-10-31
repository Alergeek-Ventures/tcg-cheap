defmodule TcgCheap.Sealed.AgentTools.ShopStatus do
  @moduledoc "What each shop's latest fetch returned and how much of it is matched."

  use Ash.Resource.Actions.Implementation

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.Shops

  @impl true
  def run(_input, _opts, _context) do
    {:ok, rows(Sealed.list_offers!(), Sealed.current_offers(DateTime.utc_now()))}
  end

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
