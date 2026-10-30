defmodule TcgCheap.Sealed do
  @moduledoc """
  The buying guide: shop offers for curated sealed products and their daily
  lowest prices.

  An offer is *current* when it was seen in its shop's latest successful
  fetch and that fetch happened within the last 3 days. Offers a shop no
  longer lists stop counting as soon as the shop is fetched again.
  """

  use Ash.Domain, otp_app: :tcg_cheap

  alias TcgCheap.Sealed.Offer

  @current_for_seconds 3 * 86_400

  resources do
    resource TcgCheap.Sealed.Offer do
      define :upsert_offer, action: :upsert
      define :assign_offer_product, action: :assign_product, args: [:product_slug]
      define :list_offers, action: :read
      define :list_offers_seen_since, action: :seen_since, args: [:since]
    end

    resource TcgCheap.Sealed.DailyPrice do
      define :record_daily_price, action: :record
      define :list_daily_prices_since, action: :since, args: [:since]
      define :list_price_history, action: :history, args: [:product_slug, :since]
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
