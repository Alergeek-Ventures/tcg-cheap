defmodule TcgCheap.Pricing.Singles.HomepagePriceChange do
  @moduledoc "Typed, public evidence for one homepage singles price change."

  @enforce_keys [
    :card_printing_id,
    :tcgdex_id,
    :name,
    :set_name,
    :collector_number,
    :start_value_eur,
    :current_value_eur,
    :change_percent,
    :start_date,
    :current_date,
    :current_fetched_at
  ]
  defstruct [
    :card_printing_id,
    :tcgdex_id,
    :name,
    :set_name,
    :collector_number,
    :rarity,
    :image_url,
    :start_value_eur,
    :current_value_eur,
    :change_percent,
    :start_date,
    :current_date,
    :current_fetched_at
  ]

  @type t :: %__MODULE__{
          card_printing_id: String.t(),
          tcgdex_id: String.t(),
          name: String.t(),
          set_name: String.t(),
          collector_number: String.t(),
          rarity: String.t() | nil,
          image_url: String.t() | nil,
          start_value_eur: Decimal.t(),
          current_value_eur: Decimal.t(),
          change_percent: Decimal.t(),
          start_date: Date.t(),
          current_date: Date.t(),
          current_fetched_at: DateTime.t()
        }
end
