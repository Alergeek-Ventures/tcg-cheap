defmodule TcgCheap.Pricing.ExchangeRate do
  @moduledoc "The canonical NBP EUR/PLN observation for each effective date."

  use Ash.Resource, domain: TcgCheap.Core, data_layer: AshPostgres.DataLayer

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
      get? true

      filter expr(
               source == "nbp" and table == "A" and base_currency == "EUR" and
                 quote_currency == "PLN" and effective_date <= ^arg(:as_of)
             )

      prepare build(sort: [effective_date: :desc, fetched_at: :desc, id: :desc], limit: 1)
    end

    read :history do
      argument :as_of, :date, allow_nil?: false
      argument :limit, :integer, allow_nil?: false, default: 90, constraints: [min: 1, max: 366]

      filter expr(
               source == "nbp" and table == "A" and base_currency == "EUR" and
                 quote_currency == "PLN" and effective_date <= ^arg(:as_of)
             )

      prepare build(
                sort: [effective_date: :desc, fetched_at: :desc, id: :desc],
                limit: arg(:limit)
              )
    end
  end

  validations do
    validate one_of(:source, ["nbp"])
    validate one_of(:table, ["A"])
    validate one_of(:base_currency, ["EUR"])
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
