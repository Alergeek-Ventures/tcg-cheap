defmodule TcgCheap.Sealed.DailyPrice do
  @moduledoc """
  One product's prices on one day: the lowest in-stock price in Polish shops
  (nil, with `shops_in_stock` zero, when no shop had it) and the Cardmarket
  trend in EUR. Shop fetches and the catalogue import each write their own
  columns.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_daily_prices"
    repo TcgCheap.Repo

    references do
      reference :product, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :record_shop_price do
      accept [:product_id, :date, :lowest_price, :shops_in_stock]
      upsert? true
      upsert_identity :product_day
      upsert_fields [:lowest_price, :shops_in_stock, :updated_at]
    end

    create :record_cardmarket_trend do
      accept [:product_id, :date, :cardmarket_trend]
      upsert? true
      upsert_identity :product_day
      upsert_fields [:cardmarket_trend, :updated_at]
    end

    read :since do
      argument :since, :date, allow_nil?: false
      argument :product_ids, {:array, :uuid}, allow_nil?: false
      filter expr(date >= ^arg(:since) and product_id in ^arg(:product_ids))
      prepare build(sort: [product_id: :asc, date: :asc])
    end

    read :on do
      argument :date, :date, allow_nil?: false
      filter expr(date == ^arg(:date))
    end

    read :history do
      argument :product_id, :uuid, allow_nil?: false
      argument :since, :date, allow_nil?: false
      filter expr(product_id == ^arg(:product_id) and date >= ^arg(:since))
      prepare build(sort: [date: :asc])
    end
  end

  validations do
    validate compare(:lowest_price, greater_than: 0)
    validate compare(:shops_in_stock, greater_than_or_equal_to: 0)
  end

  attributes do
    uuid_primary_key :id
    attribute :date, :date, allow_nil?: false, public?: true
    attribute :lowest_price, :decimal, public?: true
    attribute :shops_in_stock, :integer, allow_nil?: false, default: 0, public?: true
    attribute :cardmarket_trend, :decimal, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :product, TcgCheap.Sealed.Product, allow_nil?: false, public?: true
  end

  identities do
    identity :product_day, [:product_id, :date]
  end
end
