defmodule TcgCheap.Sealed do
  @moduledoc """
  The buying guide: the Cardmarket sealed catalogue, shop offers matched to
  it, and daily prices.

  An offer is *current* when it was seen in its shop's latest successful
  fetch and that fetch happened within the last 3 days. Offers a shop no
  longer lists stop counting as soon as the shop is fetched again.
  """

  use Ash.Domain, otp_app: :tcg_cheap

  alias TcgCheap.Sealed.{Ean, Offer}

  @current_for_seconds 3 * 86_400

  resources do
    resource TcgCheap.Sealed.Product do
      define :import_product, action: :import
      define :list_products, action: :read
      define :get_product_by_slug, action: :by_slug, args: [:slug], not_found_error?: false
      define :browse_products, action: :browse, args: [{:optional, :query}, {:optional, :kind}]
      define :set_product_availability, action: :set_availability
      define :set_product_eans, action: :set_eans, args: [:eans]
      define :get_product, action: :read, get_by: [:id], not_found_error?: false
      define :list_products_with_eans, action: :with_eans
    end

    resource TcgCheap.Sealed.Offer do
      define :upsert_offer, action: :upsert
      define :match_offer, action: :match, args: [:product_id]
      define :assign_offer_manually, action: :assign_manually, args: [:product_id]
      define :exclude_offer_manually, action: :exclude_manually
      define :clear_manual_offer, action: :clear_manual
      define :get_offer, action: :read, get_by: [:id]
      define :list_offers, action: :read
      define :list_offers_seen_since, action: :seen_since, args: [:since]

      define :list_offers_seen_since_for_products,
        action: :seen_since_for_products,
        args: [:since, :product_ids]

      define :list_latest_shop_fetches, action: :latest_fetches, args: [:since]
      define :list_manual_offers, action: :manual
    end

    resource TcgCheap.Sealed.DailyPrice do
      define :record_shop_price, action: :record_shop_price
      define :record_cardmarket_trend, action: :record_cardmarket_trend
      define :list_daily_prices_since, action: :since, args: [:since, :product_ids]
      define :list_daily_prices_on, action: :on, args: [:date]
      define :list_price_history, action: :history, args: [:product_id, :since]

      define :get_last_stocked_day,
        action: :last_stocked,
        args: [:product_id],
        get?: true,
        not_found_error?: false
    end
  end

  @doc "Every current offer, or only those of the given products (see the module documentation)."
  @spec current_offers(DateTime.t(), [Ecto.UUID.t()] | :all) :: [Offer.t()]
  def current_offers(%DateTime{} = now, product_ids \\ :all) do
    since = DateTime.add(now, -@current_for_seconds, :second)
    latest = since |> list_latest_shop_fetches!() |> Map.new(&{&1.shop, &1.last_seen_at})

    offers =
      case product_ids do
        :all -> list_offers_seen_since!(since)
        ids -> list_offers_seen_since_for_products!(since, ids)
      end

    Enum.filter(offers, &(DateTime.compare(&1.last_seen_at, Map.fetch!(latest, &1.shop)) == :eq))
  end

  @doc """
  Every known barcode and its product: a product's own EANs and the EANs of
  offers assigned to it manually. A code claimed by two products identifies
  neither and is left out.
  """
  @spec known_eans() :: %{String.t() => Ecto.UUID.t()}
  def known_eans do
    from_products =
      for product <- list_products_with_eans!(), ean <- product.eans, do: {ean, product.id}

    from_offers =
      for %Offer{ean: ean, product_id: id} <- list_manual_offers!(),
          is_binary(ean) and not is_nil(id),
          do: {ean, id}

    (from_products ++ from_offers)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {ean, ids} ->
      case Enum.uniq(ids) do
        [id] -> [{ean, id}]
        _conflict -> []
      end
    end)
    |> Map.new()
  end

  @doc "The product identified by a scanned or typed barcode, if it is known."
  @spec product_for_barcode(String.t()) :: TcgCheap.Sealed.Product.t() | nil
  def product_for_barcode(code) do
    with ean when is_binary(ean) <- Ean.normalize(code),
         {:ok, id} <- Map.fetch(known_eans(), ean) do
      get_product!(id)
    else
      _unknown -> nil
    end
  end
end
