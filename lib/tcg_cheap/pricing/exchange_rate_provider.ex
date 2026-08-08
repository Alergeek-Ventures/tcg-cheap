defmodule TcgCheap.Pricing.ExchangeRateProvider do
  @moduledoc "Contract for acquiring the canonical exchange rate."

  defmodule Result do
    @moduledoc "A normalized exchange-rate observation."
    @enforce_keys [
      :rate,
      :effective_date,
      :publication_number,
      :fetched_at,
      :source,
      :table,
      :base_currency,
      :quote_currency
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            rate: Decimal.t(),
            effective_date: Date.t(),
            publication_number: String.t(),
            fetched_at: DateTime.t(),
            source: String.t(),
            table: String.t(),
            base_currency: String.t(),
            quote_currency: String.t()
          }
  end

  @type result :: Result.t()
  @callback fetch(map(), keyword()) :: {:ok, result()} | {:error, term()}
end
