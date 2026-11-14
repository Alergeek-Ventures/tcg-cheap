defmodule TcgCheap.Sealed.Refresh do
  @moduledoc """
  Fetches one shop through its feed client (`source`). Sealed offers commit
  first; singles are then stored and matched in a separate transaction under
  their own lock, so they never hold up sealed price recomputations.

  The sealed transaction upserts every sealed offer seen and `recompute/1`s: all
  stored offers are re-matched (the catalogue may have changed; manual
  assignments are kept), today's lowest shop price is recorded per product,
  and each product's availability, lowest price (or, with nothing in stock,
  lowest pre-order price) and image are refreshed. A
  failed fetch writes nothing; a shop listing no products at all counts as
  failed, so its last offers simply age out instead of staying current.
  """

  alias TcgCheap.Repo
  alias TcgCheap.Sealed

  alias TcgCheap.Sealed.{
    CardRefresh,
    DailyPrice,
    FetchFailure,
    Market,
    MarketDailyPrice,
    Matcher,
    Offer,
    Shop,
    Shops
  }

  require Logger

  # Matching reads names and set names; availability compares and updates
  # the rest. Kind and region stay for the product's validations.
  @product_fields [
    :name,
    :set_name,
    :kind,
    :region,
    :available,
    :lowest_price,
    :lowest_preorder_price,
    :image_url
  ]

  @spec run(Shop.t(), keyword()) :: {:ok, %{offers: non_neg_integer()}} | {:error, term()}
  def run(%Shop{} = shop, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    case shop.source.fetch(shop, Keyword.get(opts, :req_options, [])) do
      {:ok, []} ->
        {:error, :empty_feed}

      # Singles read apart failed: the sealed offers stay current, while the
      # shop's singles are left as they were and age out unless a later fetch
      # reads them again.
      # With no sealed offers either, FetchWorker reports it as a failed sealed fetch.
      {:partial, [], reason} ->
        {:error, reason}

      {:partial, sealed, reason} ->
        FetchFailure.report(:singles, shop.key, reason)

        with {:ok, sealed} <- in_pln(shop, sealed, now),
             do: store_sealed(shop, Enum.map(sealed, &Map.drop(&1, [:kind, :category])), now)

      {:ok, fetched} ->
        {singles, sealed} = Enum.split_with(fetched, &(Map.get(&1, :kind) == :single))

        sealed = Enum.map(sealed, &Map.drop(&1, [:kind, :category]))

        with {:ok, singles} <- in_pln(shop, singles, now),
             {:ok, sealed} <- in_pln(shop, sealed, now),
             {:ok, counts} <- store_sealed(shop, sealed, now),
             {:ok, card_counts} <- CardRefresh.run(shop, singles, now) do
          {:ok, Map.merge(counts, card_counts)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Every offer keeps the shop's own price (`shop_price`, which other markets
  # convert), and a shop abroad's `price` is stored in PLN at the latest NBP
  # rate, so it compares with Polish shops and Cardmarket like any other
  # offer (`Market.pln_rate/2`: a rate over a week old fails the fetch).
  defp in_pln(%Shop{currency: currency} = shop, offers, now) do
    offers = Enum.map(offers, &Map.merge(&1, %{shop_price: &1.price, currency: currency}))

    case shop.currency do
      "PLN" -> {:ok, offers}
      _abroad -> convert_to_pln(offers, currency, DateTime.to_date(now))
    end
  end

  defp convert_to_pln(offers, currency, today) do
    with {:ok, %{rate: rate}} <- Market.pln_rate(currency, today),
         do: {:ok, Enum.map(offers, &%{&1 | price: to_pln(&1.price, rate)})}
  end

  defp to_pln(price, rate), do: price |> Decimal.mult(rate) |> Decimal.round(2)

  # A shop read only for its singles (`Shop.singles_only`) has no sealed side
  # to store or recompute; its sealed products are dropped here.
  defp store_sealed(%Shop{singles_only: true}, _offers, _now), do: {:ok, %{offers: 0}}

  defp store_sealed(shop, offers, now) do
    Repo.transaction(
      fn ->
        lock_recompute()
        upsert_offers(shop, offers, now)
        Sealed.record_shop_fetch!(%{shop: shop.key, fetched_at: now}, return_notifications?: true)
        recompute(now)
        %{offers: length(offers)}
      end,
      timeout: transaction_timeout()
    )
  end

  @doc "How long a transaction that recomputes prices may take."
  def transaction_timeout, do: :timer.minutes(5)

  @doc """
  Re-matches offers and refreshes daily shop prices and product availability.
  Must run inside a transaction; concurrent recomputations are serialized.
  """
  @spec recompute(DateTime.t()) :: :ok
  def recompute(%DateTime{} = now) do
    lock_recompute()
    products = Sealed.list_products!(query: [select: @product_fields])
    rematch_offers(products)

    matched =
      now
      |> Sealed.current_offers(:all,
        select: [:product_id, :price, :shop_price, :currency, :in_stock, :preorder, :image_url]
      )
      |> Enum.filter(& &1.product_id)

    # A shop abroad counts at its price with delivery to Poland; one with an
    # unknown delivery price is only listed.
    current = Shops.compared(matched)
    today = DateTime.to_date(now)

    record_shop_prices(current, today)
    update_products(products, current)
    Enum.each(Market.all() -- [Market.poland()], &record_market_prices(&1, matched, today))
    :ok
  end

  defp upsert_offers(shop, fetched, now) do
    inputs =
      Enum.map(
        fetched,
        &(&1
          |> Map.put_new(:preorder, false)
          |> preorder_by_title()
          |> Map.merge(%{shop: shop.key, last_seen_at: now}))
      )

    %Ash.BulkResult{status: :success} =
      Ash.bulk_create!(inputs, Offer, :upsert,
        domain: Sealed,
        return_errors?: true,
        stop_on_error?: true
      )
  end

  # An offer for sale whose title says pre-order is one, whatever the feed says.
  defp preorder_by_title(%{in_stock: true, title: title} = offer) do
    if Matcher.preorder_title?(title), do: %{offer | in_stock: false, preorder: true}, else: offer
  end

  defp preorder_by_title(offer), do: offer

  @doc "Runs a manual write and recomputes prices in the same transaction."
  @spec with_recompute((-> {:ok, record, list()} | {:error, term()})) ::
          {:ok, record} | {:error, term()}
        when record: struct()
  def with_recompute(fun) do
    Repo.transaction(
      fn ->
        # Lock before the write so simultaneous manual writes cannot deadlock
        # against the offer updates performed by recompute/1.
        lock_recompute()

        case fun.() do
          {:ok, record, _notifications} ->
            recompute(DateTime.utc_now())
            record

          {:error, error} ->
            Repo.rollback(error)
        end
      end,
      timeout: transaction_timeout()
    )
  end

  defp lock_recompute do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext('tcg_cheap:sealed_recompute'))")
  end

  defp rematch_offers(products) do
    offers = Sealed.list_offers!(query: [select: [:title, :ean, :manual?, :product_id]])
    index = Matcher.index(products, Sealed.known_eans())

    # An offer that no longer matches (nil) is unmatched again: a wrong match
    # poisons the price history more than a missing one.
    for %Offer{manual?: false} = offer <- offers,
        id <- [Matcher.product_id(offer, index)],
        id != offer.product_id do
      # Nothing subscribes to offer notifications; drop them inside the transaction.
      Sealed.match_offer!(offer, id, return_notifications?: true)
    end
  end

  defp record_shop_prices(current, today) do
    previously_priced =
      for %{lowest_price: %Decimal{}, product_id: id} <-
            Sealed.list_daily_prices_on!(today, query: [select: [:product_id, :lowest_price]]),
          do: id

    current
    |> daily_prices(previously_priced, today)
    |> bulk_record(:record_shop_price)
  end

  # Poland's history stays in `DailyPrice` (it predates markets, and holds the
  # Cardmarket trend); every other market's goes to `MarketDailyPrice`, by the
  # same rules. Without a recent rate for a currency some offer needs, the
  # market's day is not recorded: a lowest price missing a shop would be wrong.
  defp record_market_prices(market, matched, today) do
    case Market.missing_rates(matched, market, today) do
      [] ->
        previously_priced =
          for %{lowest_price: %Decimal{}, product_id: id} <-
                Sealed.list_market_daily_prices_on!(market.code, today,
                  query: [select: [:product_id, :lowest_price]]
                ),
              do: id

        matched
        |> Market.compared(market, today)
        |> daily_prices(previously_priced, today)
        |> Enum.map(&Map.put(&1, :market, market.code))
        |> bulk_record(:record, MarketDailyPrice)

      missing ->
        Logger.warning(
          "#{market.code} prices not recorded on #{today}: no recent rate for #{inspect(missing)}"
        )
    end
  end

  # Today's lowest in-stock compared price and shop count of every product
  # with an offer, and of each one priced earlier today (now out of stock).
  defp daily_prices(current, previously_priced, today) do
    by_product = current |> Enum.filter(& &1.in_stock) |> Enum.group_by(& &1.product_id)
    ids = Enum.uniq(Enum.map(current, & &1.product_id) ++ previously_priced)

    Enum.map(ids, fn id ->
      offers = Map.get(by_product, id, [])

      %{
        product_id: id,
        date: today,
        lowest_price: offers |> Enum.map(& &1.price) |> Enum.min(Decimal, fn -> nil end),
        shops_in_stock: offers |> Enum.map(& &1.shop) |> Enum.uniq() |> length()
      }
    end)
  end

  defp update_products(products, current) do
    by_product = Enum.group_by(current, & &1.product_id)

    for product <- products,
        offers = Map.get(by_product, product.id, []),
        wanted = availability(product, offers),
        wanted !=
          Map.take(product, [:available, :lowest_price, :lowest_preorder_price, :image_url]) do
      Sealed.set_product_availability!(product, wanted, return_notifications?: true)
    end
  end

  defp availability(product, offers) do
    in_stock = offers |> Enum.filter(& &1.in_stock) |> Enum.sort_by(& &1.price, Decimal)
    preorders = if in_stock == [], do: Enum.filter(offers, & &1.preorder), else: []

    %{
      available: in_stock != [],
      lowest_price: List.first(in_stock) && hd(in_stock).price,
      lowest_preorder_price:
        preorders |> Enum.map(& &1.price) |> Enum.min(Decimal, fn -> nil end),
      image_url: image_url(product, in_stock ++ offers)
    }
  end

  # The photo stays while an offer still shows it, so a change of the cheapest
  # shop does not make `TcgCheap.Sealed.PhotoMirror` copy the product again.
  defp image_url(product, offers) do
    images = offers |> Enum.map(& &1.image_url) |> Enum.reject(&is_nil/1)

    if product.image_url in images,
      do: product.image_url,
      else: List.first(images, product.image_url)
  end

  @doc false
  def bulk_record(inputs, action, resource \\ DailyPrice)
  def bulk_record([], _action, _resource), do: :ok

  def bulk_record(inputs, action, resource) do
    %Ash.BulkResult{status: :success} =
      Ash.bulk_create!(inputs, resource, action,
        domain: Sealed,
        return_errors?: true,
        stop_on_error?: true
      )

    :ok
  end
end
