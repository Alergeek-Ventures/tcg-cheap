defmodule TcgCheap.Sealed.SuggestedPrice do
  @moduledoc """
  A suggested retail price (SCD, gross PLN) from the public wholesale
  catalogue of the REBEL distributor (`TcgCheap.Sealed.Rebel`), kept after
  the item leaves the catalogue: REBEL lists only its current range.

  `product_id` is set by automatic matching, or by an agent when `manual?`
  is true (a manual decision with no product keeps the item unmatched for
  good); automatic matching never overwrites a manual decision. The price is
  shown on the product page only and never enters the price verdict.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_suggested_prices"
    repo TcgCheap.Repo

    references do
      reference :product, on_delete: :nilify
    end

    custom_indexes do
      index [:product_id]
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [:rebel_id, :title, :url, :ean, :price, :last_seen_at]
      upsert? true
      upsert_identity :rebel_id
      upsert_fields [:title, :url, :ean, :price, :last_seen_at, :updated_at]
    end

    update :match do
      description "Automatic matching; refuses to touch manual decisions."
      accept [:product_id]
      validate attribute_equals(:manual?, false)
    end

    update :decide_manually do
      description "Assigns the item to a product, or with no product keeps it unmatched for good."
      accept [:product_id]
      change set_attribute(:manual?, true)
    end

    read :for_product do
      argument :product_id, :uuid, allow_nil?: false
      get? true
      filter expr(product_id == ^arg(:product_id))
      prepare build(sort: [last_seen_at: :desc, id: :asc], limit: 1)
    end
  end

  validations do
    validate compare(:price, greater_than: 0)
  end

  attributes do
    uuid_primary_key :id

    attribute :rebel_id, :string do
      allow_nil? false
      public? true
      constraints max_length: 20
    end

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints max_length: 300
    end

    attribute :url, :string do
      allow_nil? false
      public? true
      constraints max_length: 2_000
    end

    attribute :ean, :string do
      public? true
      constraints max_length: 13
    end

    attribute :price, :decimal, allow_nil?: false, public?: true
    attribute :manual?, :boolean, allow_nil?: false, default: false, public?: true
    attribute :last_seen_at, :utc_datetime_usec, allow_nil?: false, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :product, TcgCheap.Sealed.Product, public?: true
  end

  identities do
    identity :rebel_id, [:rebel_id]
  end
end
