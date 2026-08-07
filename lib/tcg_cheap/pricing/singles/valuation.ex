defmodule TcgCheap.Pricing.Singles.Valuation do
  @moduledoc "Pure fixed-preset valuation for normalized singles offers."

  alias TcgCheap.Pricing.Singles.Offer

  defmodule Result do
    @moduledoc "Result of the `default_v1` singles valuation."

    @enforce_keys [:value_eur, :qualifying_seller_count, :preset_version, :method]
    defstruct [:value_eur, :qualifying_seller_count, :preset_version, :method]

    @type t :: %__MODULE__{
            value_eur: Decimal.t(),
            qualifying_seller_count: non_neg_integer(),
            preset_version: :default_v1,
            method: :five_lowest_distinct_sellers
          }
  end

  @type result :: Result.t()

  @spec calculate_default_v1([Offer.t()]) ::
          {:ok, result()} | {:error, :no_qualifying_offers}
  def calculate_default_v1(offers) when is_list(offers) do
    qualifying =
      offers
      |> Enum.filter(&qualifying_offer?/1)
      |> lowest_offer_by_seller()
      |> Enum.sort_by(& &1.price_eur, fn left, right -> Decimal.compare(left, right) != :gt end)
      |> Enum.take(5)

    case qualifying do
      [] ->
        {:error, :no_qualifying_offers}

      _ ->
        value =
          qualifying
          |> Enum.map(& &1.price_eur)
          |> average()
          |> Decimal.round(2, :half_up)

        {:ok,
         %Result{
           value_eur: value,
           qualifying_seller_count: length(qualifying),
           preset_version: :default_v1,
           method: :five_lowest_distinct_sellers
         }}
    end
  end

  defp qualifying_offer?(%Offer{} = offer) do
    offer.language == :en and
      offer.condition == :near_mint and
      offer.ships_to_poland? == true and
      is_binary(offer.seller_key) and
      String.trim(offer.seller_key) != "" and
      match?(%Decimal{}, offer.price_eur) and
      finite_positive_price?(offer.price_eur)
  end

  defp qualifying_offer?(_), do: false

  defp finite_positive_price?(%Decimal{sign: 1, coef: coef, exp: exp})
       when is_integer(coef) and coef > 0 and is_integer(exp),
       do: true

  defp finite_positive_price?(_), do: false

  defp lowest_offer_by_seller(offers) do
    offers
    |> Enum.group_by(& &1.seller_key)
    |> Enum.map(fn {_seller, seller_offers} ->
      Enum.min_by(seller_offers, & &1.price_eur, fn left, right ->
        Decimal.compare(left, right) != :gt
      end)
    end)
  end

  defp average(prices) do
    prices
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
    |> Decimal.div(Decimal.new(length(prices)))
  end
end
