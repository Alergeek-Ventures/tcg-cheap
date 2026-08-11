defmodule TcgCheap.Pricing.HomepageSealedPriceChange do
  @moduledoc "Typed, public evidence for one homepage sealed-product price change."

  @enforce_keys [
    :sealed_product_id,
    :slug,
    :name,
    :product_type,
    :start_benchmark_pln,
    :current_benchmark_pln,
    :change_percent,
    :start_date,
    :current_date,
    :current_checked_at,
    :current_calculated_at
  ]
  defstruct [
    :sealed_product_id,
    :slug,
    :name,
    :product_type,
    :series_name,
    :set_name,
    :release_date,
    :distribution_status,
    :start_benchmark_pln,
    :current_benchmark_pln,
    :change_percent,
    :start_date,
    :current_date,
    :current_checked_at,
    :current_calculated_at
  ]

  @type t :: %__MODULE__{
          sealed_product_id: String.t(),
          slug: String.t(),
          name: String.t(),
          product_type: String.t(),
          series_name: String.t() | nil,
          set_name: String.t() | nil,
          release_date: Date.t() | nil,
          distribution_status: String.t(),
          start_benchmark_pln: Decimal.t(),
          current_benchmark_pln: Decimal.t(),
          change_percent: Decimal.t(),
          start_date: Date.t(),
          current_date: Date.t(),
          current_checked_at: DateTime.t(),
          current_calculated_at: DateTime.t()
        }
end
