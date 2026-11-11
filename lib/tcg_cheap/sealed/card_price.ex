defmodule TcgCheap.Sealed.CardPrice do
  @moduledoc """
  The Cardmarket trend of one single card, in EUR, from Cardmarket's latest
  price guide, by Cardmarket product id. The daily catalogue import
  (`TcgCheap.Sealed.CatalogueImport`) replaces every row, so a card the
  guide no longer prices has none. The cards on single booster pages
  (`TcgCheap.Sealed.TcgdexCard`) show it.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_card_prices"
    repo TcgCheap.Repo
  end

  actions do
    defaults [:read]

    create :record do
      accept [:cardmarket_id, :trend, :trend_holo, :low, :avg7, :avg30, :priced_on]
      upsert? true
      upsert_fields [:trend, :trend_holo, :low, :avg7, :avg30, :priced_on, :updated_at]
    end

    destroy :prune do
      description "Removes a price the latest price guide no longer gives."
    end
  end

  attributes do
    attribute :cardmarket_id, :integer do
      description "The Cardmarket product id of the single."
      primary_key? true
      allow_nil? false
      public? true
    end

    attribute :trend_holo, :decimal, public?: true
    attribute :low, :decimal, public?: true

    attribute :trend, :decimal do
      description "Cardmarket's trend price in EUR, nil when it gives none."
      public? true
    end

    attribute :avg7, :decimal do
      description "The average sale price of the last 7 days in EUR (non-reverse), nil without sales."
      public? true
    end

    attribute :avg30, :decimal do
      description "The average sale price of the last 30 days in EUR (non-reverse), nil without sales."
      public? true
    end

    attribute :priced_on, :date do
      description "The day of the Cardmarket price guide."
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
