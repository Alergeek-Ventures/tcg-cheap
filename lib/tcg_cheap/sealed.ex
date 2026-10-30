defmodule TcgCheap.Sealed do
  @moduledoc """
  The buying guide: the Cardmarket sealed catalogue, shop offers matched to
  it, and daily prices.

  An offer is *current* when it was seen in its shop's latest successful
  fetch and that fetch happened within the last 3 days. Offers a shop no
  longer lists stop counting as soon as the shop is fetched again.
  """

  use Ash.Domain, otp_app: :tcg_cheap

  alias TcgCheap.Sealed.Offer

  @current_for_seconds 3 * 86_400

  resources do
    resource TcgCheap.Sealed.Product do
      define :import_product, action: :import
      define :list_products, action: :read
      define :get_product_by_slug, action: :by_slug, args: [:slug], not_found_error?: false
      define :list_products_by_ids, action: :by_ids, args: [:ids]
      define :browse_products, action: :browse, args: [{:optional, :query}, {:optional, :kind}]
      define :set_product_availability, action: :set_availability
    end

    resource TcgCheap.Sealed.Offer do
      define :upsert_offer, action: :upsert
      define :match_offer, action: :match, args: [:product_id]
      define :assign_offer_manually, action: :assign_manually, args: [:product_id]
      define :clear_manual_offer, action: :clear_manual
      define :get_offer, action: :read, get_by: [:id]
      define :list_offers, action: :read
      define :list_offers_seen_since, action: :seen_since, args: [:since]
      define :list_manual_offers, action: :manual
    end

    resource TcgCheap.Sealed.DailyPrice do
      define :record_shop_price, action: :record_shop_price
      define :record_cardmarket_trend, action: :record_cardmarket_trend
      define :list_daily_prices_since, action: :since, args: [:since, :product_ids]
      define :list_daily_prices_on, action: :on, args: [:date]
      define :list_price_history, action: :history, args: [:product_id, :since]
    end
  end

  @doc "How long an offer may go unseen before it stops counting."
  @spec current_for_seconds() :: pos_integer()
  def current_for_seconds, do: @current_for_seconds

  @doc "Every current offer (see the module documentation)."
  @spec current_offers(DateTime.t()) :: [Offer.t()]
  def current_offers(%DateTime{} = now) do
    now
    |> DateTime.add(-@current_for_seconds, :second)
    |> list_offers_seen_since!()
    |> latest_per_shop()
  end

  @doc "Keeps only the offers seen in each shop's latest fetch."
  @spec latest_per_shop([Offer.t()]) :: [Offer.t()]
  def latest_per_shop(offers) do
    latest =
      Enum.reduce(offers, %{}, fn offer, acc ->
        Map.update(acc, offer.shop, offer.last_seen_at, &later(&1, offer.last_seen_at))
      end)

    Enum.filter(offers, &(DateTime.compare(&1.last_seen_at, Map.fetch!(latest, &1.shop)) == :eq))
  end

  defp later(a, b), do: if(DateTime.compare(a, b) == :lt, do: b, else: a)
end
