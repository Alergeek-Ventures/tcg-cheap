defmodule TcgCheap.Sealed.Refresh do
  @moduledoc """
  Fetches one shop and stores the result in a single transaction.

  A successful fetch upserts every offer seen and then `recompute/1`s: all
  stored offers are re-matched (the catalogue may have changed; manual
  assignments are kept), today's lowest shop price is recorded per product,
  and each product's availability, lowest price and image are refreshed. A
  failed fetch writes nothing; a shop listing no products at all counts as
  failed, so its last offers simply age out instead of staying current.
  """

  alias TcgCheap.Repo
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{DailyPrice, Matcher, Offer, Shop, WooCommerce}

  @spec run(Shop.t(), keyword()) :: {:ok, %{offers: non_neg_integer()}} | {:error, term()}
  def run(%Shop{} = shop, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    case WooCommerce.fetch(shop, Keyword.get(opts, :req_options, [])) do
      {:ok, []} ->
        {:error, :empty_feed}

      {:ok, fetched} ->
        Repo.transaction(
          fn ->
            upsert_offers(shop, fetched, now)
            recompute(now)
            %{offers: length(fetched)}
          end,
          timeout: transaction_timeout()
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "How long a transaction that recomputes prices may take."
  def transaction_timeout, do: :timer.minutes(5)

  @doc """
  Re-matches offers and refreshes daily shop prices and product availability.
  Must run inside a transaction; concurrent recomputations are serialized.
  """
  @spec recompute(DateTime.t()) :: :ok
  def recompute(%DateTime{} = now) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext('tcg_cheap:sealed_recompute'))")
    products = Sealed.list_products!()
    rematch_offers(products)
    current = now |> Sealed.current_offers() |> Enum.filter(& &1.product_id)
    record_shop_prices(current, DateTime.to_date(now))
    update_products(products, current)
    :ok
  end

  defp upsert_offers(shop, fetched, now) do
    inputs = Enum.map(fetched, &Map.merge(&1, %{shop: shop.key, last_seen_at: now}))

    %Ash.BulkResult{status: :success} =
      Ash.bulk_create!(inputs, Offer, :upsert,
        domain: Sealed,
        return_errors?: true,
        stop_on_error?: true
      )
  end

  defp rematch_offers(products) do
    offers = Sealed.list_offers!()

    # An EAN manually assigned to two different products identifies neither.
    eans =
      for %Offer{manual?: true, ean: ean, product_id: id} <- offers,
          is_binary(ean) and not is_nil(id),
          reduce: %{} do
        acc -> Map.update(acc, ean, id, &if(&1 == id, do: id, else: :conflict))
      end
      |> Map.reject(fn {_ean, id} -> id == :conflict end)

    index = Matcher.index(products, eans)

    for %Offer{manual?: false} = offer <- offers,
        id = Matcher.product_id(offer, index),
        id != offer.product_id do
      # Nothing subscribes to offer notifications; drop them inside the transaction.
      Sealed.match_offer!(offer, id, return_notifications?: true)
    end
  end

  defp record_shop_prices(current, today) do
    by_product = current |> Enum.filter(& &1.in_stock) |> Enum.group_by(& &1.product_id)

    previously_priced =
      for %{lowest_price: %Decimal{}, product_id: id} <- Sealed.list_daily_prices_on!(today),
          do: id

    ids = Enum.uniq(Enum.map(current, & &1.product_id) ++ previously_priced)

    inputs =
      Enum.map(ids, fn id ->
        offers = Map.get(by_product, id, [])

        %{
          product_id: id,
          date: today,
          lowest_price: offers |> Enum.map(& &1.price) |> Enum.min(Decimal, fn -> nil end),
          shops_in_stock: offers |> Enum.map(& &1.shop) |> Enum.uniq() |> length()
        }
      end)

    bulk_record(inputs, :record_shop_price)
  end

  defp update_products(products, current) do
    by_product = Enum.group_by(current, & &1.product_id)

    for product <- products,
        offers = Map.get(by_product, product.id, []),
        wanted = availability(product, offers),
        wanted != Map.take(product, [:available, :lowest_price, :image_url]) do
      Sealed.set_product_availability!(product, wanted, return_notifications?: true)
    end
  end

  defp availability(product, offers) do
    in_stock = offers |> Enum.filter(& &1.in_stock) |> Enum.sort_by(& &1.price, Decimal)
    best_image = Enum.find_value(in_stock ++ offers, & &1.image_url)

    %{
      available: in_stock != [],
      lowest_price: List.first(in_stock) && hd(in_stock).price,
      image_url: best_image || product.image_url
    }
  end

  @doc false
  def bulk_record([], _action), do: :ok

  def bulk_record(inputs, action) do
    %Ash.BulkResult{status: :success} =
      Ash.bulk_create!(inputs, DailyPrice, action,
        domain: Sealed,
        return_errors?: true,
        stop_on_error?: true
      )

    :ok
  end
end
