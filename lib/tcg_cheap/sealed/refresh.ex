defmodule TcgCheap.Sealed.Refresh do
  @moduledoc """
  Fetches one shop and stores the result in a single transaction.

  A successful fetch upserts every offer seen, re-matches all stored offers
  (the catalogue may have changed since they were stored) and recomputes
  today's daily price for every catalogue product. A failed fetch writes
  nothing.
  """

  alias TcgCheap.Repo
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Catalogue, DailyPrice, Matcher, Offer, WooCommerce}
  alias TcgCheap.Sealed.Shop

  @spec run(Shop.t(), keyword()) :: {:ok, %{offers: non_neg_integer()}} | {:error, term()}
  def run(%Shop{} = shop, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    with {:ok, fetched} <- WooCommerce.fetch(shop, Keyword.get(opts, :req_options, [])) do
      Repo.transaction(fn ->
        upsert_offers(shop, fetched, now)
        rematch_offers()
        record_daily_prices(now)
        %{offers: length(fetched)}
      end)
    end
  end

  defp upsert_offers(_shop, [], _now), do: :ok

  defp upsert_offers(shop, fetched, now) do
    products = Catalogue.all()

    inputs =
      Enum.map(fetched, fn offer ->
        Map.merge(offer, %{
          shop: shop.key,
          product_slug: Matcher.product_slug(offer, products),
          last_seen_at: now
        })
      end)

    %Ash.BulkResult{status: :success} =
      Ash.bulk_create!(inputs, Offer, :upsert,
        domain: Sealed,
        return_errors?: true,
        stop_on_error?: true
      )
  end

  defp rematch_offers do
    products = Catalogue.all()

    Enum.each(Sealed.list_offers!(), fn offer ->
      slug = Matcher.product_slug(offer, products)
      # Nothing subscribes to offer notifications; drop them inside the transaction.
      if slug != offer.product_slug,
        do: Sealed.assign_offer_product!(offer, slug, return_notifications?: true)
    end)
  end

  defp record_daily_prices(now) do
    today = DateTime.to_date(now)

    by_product =
      now
      |> Sealed.current_offers()
      |> Enum.filter(&(&1.in_stock and is_binary(&1.product_slug)))
      |> Enum.group_by(& &1.product_slug)

    inputs =
      for product <- Catalogue.all() do
        offers = Map.get(by_product, product.slug, [])

        %{
          product_slug: product.slug,
          date: today,
          lowest_price: offers |> Enum.map(& &1.price) |> Enum.min(Decimal, fn -> nil end),
          shops_in_stock: offers |> Enum.map(& &1.shop) |> Enum.uniq() |> length()
        }
      end

    %Ash.BulkResult{status: :success} =
      Ash.bulk_create!(inputs, DailyPrice, :record,
        domain: Sealed,
        return_errors?: true,
        stop_on_error?: true
      )
  end
end
