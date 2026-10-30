defmodule TcgCheap.Sealed.DailyPrice do
  @moduledoc """
  The lowest in-stock price of a catalogue product on one day.

  `lowest_price` is nil (and `shops_in_stock` zero) on a day when no shop had
  the product in stock.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_daily_prices"
    repo TcgCheap.Repo
  end

  actions do
    defaults [:read]

    create :record do
      accept [:product_slug, :date, :lowest_price, :shops_in_stock]
      upsert? true
      upsert_identity :product_day
      upsert_fields [:lowest_price, :shops_in_stock, :updated_at]
    end

    read :since do
      argument :since, :date, allow_nil?: false
      filter expr(date >= ^arg(:since))
      prepare build(sort: [product_slug: :asc, date: :asc])
    end

    read :history do
      argument :product_slug, :string, allow_nil?: false
      argument :since, :date, allow_nil?: false
      filter expr(product_slug == ^arg(:product_slug) and date >= ^arg(:since))
      prepare build(sort: [date: :asc])
    end
  end

  validations do
    validate compare(:lowest_price, greater_than: 0)
    validate compare(:shops_in_stock, greater_than_or_equal_to: 0)
  end

  attributes do
    uuid_primary_key :id

    attribute :product_slug, :string do
      allow_nil? false
      public? true
      constraints max_length: 160
    end

    attribute :date, :date, allow_nil?: false, public?: true
    attribute :lowest_price, :decimal, public?: true
    attribute :shops_in_stock, :integer, allow_nil?: false, default: 0, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :product_day, [:product_slug, :date]
  end
end
