defmodule TcgCheap.Sealed.CardDailyPrice do
  @moduledoc """
  One single card's Cardmarket trend on one day, in EUR, by Cardmarket
  product id: the history behind the price charts. `TcgCheap.Sealed.CardPrice`
  keeps only the latest guide; the daily catalogue import
  (`TcgCheap.Sealed.CatalogueImport`) also records the trend here for the
  cards of our catalogue, so the history starts on the day the import first
  ran with it. A day without a guide has no row: a chart shows the gap.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_card_daily_prices"
    repo TcgCheap.Repo
  end

  actions do
    defaults [:read]

    create :record do
      accept [:cardmarket_id, :priced_on, :trend, :trend_holo]
      upsert? true
      upsert_fields [:trend, :trend_holo]
    end
  end

  attributes do
    attribute :cardmarket_id, :integer do
      description "The Cardmarket product id of the single."
      primary_key? true
      allow_nil? false
      public? true
    end

    attribute :priced_on, :date do
      description "The day of the Cardmarket price guide."
      primary_key? true
      allow_nil? false
      public? true
    end

    attribute :trend, :decimal, public?: true
    attribute :trend_holo, :decimal, public?: true
  end
end
