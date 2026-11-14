defmodule TcgCheap.Pricing.ExchangeRate do
  @moduledoc """
  The canonical NBP mid rate to PLN for each currency and effective date:
  EUR for Cardmarket, the others for the markets' and the shops' currencies
  (`TcgCheap.Sealed.Market.currencies/0`). NBP publishes the most traded
  currencies every working day in table A and the rest every Wednesday in
  table B (RSD, MKD, BAM, ALL, MDL and others).
  """

  use Ash.Resource, domain: TcgCheap.Pricing, data_layer: AshPostgres.DataLayer

  # NBP's table A, as https://api.nbp.pl/api/exchangerates/tables/a/ listed
  # it on 2026-11-14; every other currency NBP prices is in table B.
  @table_a ~w(THB USD AUD HKD CAD NZD SGD EUR HUF CHF GBP UAH JPY CZK DKK ISK NOK SEK RON TRY
              ILS CLP PHP MXN ZAR BRL MYR IDR INR KRW CNY XDR)

  @doc ~S(The NBP table a currency's rate is published in: "A" daily, "B" weekly.)
  @spec table(String.t()) :: String.t()
  def table(currency) when currency in @table_a, do: "A"
  def table(_currency), do: "B"

  postgres do
    table "exchange_rates"
    repo TcgCheap.Repo

    custom_indexes do
      index [:source, :table, :base_currency, :quote_currency, :effective_date, :fetched_at]
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :source,
        :table,
        :base_currency,
        :quote_currency,
        :rate,
        :effective_date,
        :publication_number,
        :fetched_at
      ]

      upsert? true
      upsert_identity :canonical_observation
      upsert_fields [:rate, :publication_number, :fetched_at]
    end

    read :latest do
      argument :as_of, :date, allow_nil?: false
      argument :base_currency, :string, allow_nil?: false, default: "EUR"
      get? true

      filter expr(
               source == "nbp" and base_currency == ^arg(:base_currency) and
                 quote_currency == "PLN" and effective_date <= ^arg(:as_of)
             )

      prepare build(sort: [effective_date: :desc, fetched_at: :desc, id: :desc], limit: 1)
    end
  end

  validations do
    validate one_of(:source, ["nbp"])
    validate one_of(:table, ["A", "B"])
    validate match(:base_currency, ~r/\A[A-Z]{3}\z/)
    validate one_of(:quote_currency, ["PLN"])
    validate compare(:rate, greater_than: 0)
  end

  attributes do
    uuid_primary_key :id
    attribute :source, :string, allow_nil?: false, default: "nbp", public?: true
    attribute :table, :string, allow_nil?: false, default: "A", public?: true
    attribute :base_currency, :string, allow_nil?: false, default: "EUR", public?: true
    attribute :quote_currency, :string, allow_nil?: false, default: "PLN", public?: true
    attribute :rate, :decimal, allow_nil?: false, public?: true
    attribute :effective_date, :date, allow_nil?: false, public?: true

    attribute :publication_number, :string do
      allow_nil? false
      public? true
      constraints min_length: 1
    end

    attribute :fetched_at, :utc_datetime_usec, allow_nil?: false, public?: true
    create_timestamp :created_at
  end

  identities do
    identity :canonical_observation, [
      :source,
      :table,
      :base_currency,
      :quote_currency,
      :effective_date
    ]
  end
end
