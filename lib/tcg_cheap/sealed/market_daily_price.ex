defmodule TcgCheap.Sealed.MarketDailyPrice do
  @moduledoc """
  One product's lowest in-stock price on one day in a market other than
  Poland (`TcgCheap.Sealed.Market`), in that market's currency: the lowest
  compared price of its shops (`Market.compared/3`); nil, with
  `shops_in_stock` zero, when no shop there had it.

  Poland keeps its history in `TcgCheap.Sealed.DailyPrice`: it predates
  markets, and the Cardmarket trend every market converts lives there.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_market_daily_prices"
    repo TcgCheap.Repo

    references do
      reference :product, on_delete: :delete
    end

    custom_indexes do
      index [:market, :date]
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [:product_id, :market, :date, :lowest_price, :shops_in_stock]
      upsert? true
      upsert_identity :product_market_day
      upsert_fields [:lowest_price, :shops_in_stock, :updated_at]
    end

    read :on do
      argument :market, :string, allow_nil?: false
      argument :date, :date, allow_nil?: false
      filter expr(market == ^arg(:market) and date == ^arg(:date))
    end

    read :last_stocked do
      description "The latest day on which some shop of the market had the product."
      argument :product_id, :uuid, allow_nil?: false
      argument :market, :string, allow_nil?: false

      filter expr(
               product_id == ^arg(:product_id) and market == ^arg(:market) and
                 not is_nil(lowest_price)
             )

      prepare build(sort: [date: :desc], limit: 1)
    end

    read :history do
      argument :product_id, :uuid, allow_nil?: false
      argument :market, :string, allow_nil?: false
      argument :since, :date, allow_nil?: false

      filter expr(
               product_id == ^arg(:product_id) and market == ^arg(:market) and
                 date >= ^arg(:since)
             )

      prepare build(sort: [date: :asc])
    end

    read :histories do
      description "The daily prices of several products in a market since a date, for list verdicts."
      argument :product_ids, {:array, :uuid}, allow_nil?: false
      argument :market, :string, allow_nil?: false
      argument :since, :date, allow_nil?: false

      filter expr(
               product_id in ^arg(:product_ids) and market == ^arg(:market) and
                 date >= ^arg(:since)
             )
    end
  end

  validations do
    validate compare(:lowest_price, greater_than: 0)
    validate compare(:shops_in_stock, greater_than_or_equal_to: 0)
  end

  attributes do
    uuid_primary_key :id

    attribute :market, :string do
      description "The market's code (`TcgCheap.Sealed.Market`), never Poland's."
      allow_nil? false
      public? true
      constraints max_length: 8
    end

    attribute :date, :date, allow_nil?: false, public?: true
    attribute :lowest_price, :decimal, public?: true
    attribute :shops_in_stock, :integer, allow_nil?: false, default: 0, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :product, TcgCheap.Sealed.Product, allow_nil?: false, public?: true
  end

  identities do
    identity :product_market_day, [:product_id, :market, :date]
  end
end
