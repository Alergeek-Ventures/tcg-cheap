defmodule TcgCheap.Sealed.Offer do
  @moduledoc "One product listed by a shop, as last seen in that shop's feed."

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_offers"
    repo TcgCheap.Repo

    custom_indexes do
      index [:last_seen_at]
      index [:product_slug, :last_seen_at]
    end
  end

  actions do
    defaults [:read]

    create :upsert do
      accept [
        :shop,
        :shop_product_id,
        :title,
        :url,
        :image_url,
        :ean,
        :price,
        :in_stock,
        :product_slug,
        :last_seen_at
      ]

      upsert? true
      upsert_identity :shop_product

      upsert_fields [
        :title,
        :url,
        :image_url,
        :ean,
        :price,
        :in_stock,
        :product_slug,
        :last_seen_at,
        :updated_at
      ]
    end

    update :assign_product do
      accept [:product_slug]
    end

    read :seen_since do
      argument :since, :utc_datetime_usec, allow_nil?: false
      filter expr(last_seen_at >= ^arg(:since))
      prepare build(sort: [shop: :asc, price: :asc, id: :asc])
    end
  end

  validations do
    validate compare(:price, greater_than: 0)
  end

  attributes do
    uuid_primary_key :id

    attribute :shop, :string do
      allow_nil? false
      public? true
      constraints max_length: 40
    end

    attribute :shop_product_id, :string do
      allow_nil? false
      public? true
      constraints max_length: 40
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

    attribute :image_url, :string do
      public? true
      constraints max_length: 2_000
    end

    attribute :ean, :string do
      public? true
      constraints max_length: 13
    end

    attribute :price, :decimal, allow_nil?: false, public?: true
    attribute :in_stock, :boolean, allow_nil?: false, public?: true

    attribute :product_slug, :string do
      public? true
      constraints max_length: 160
    end

    attribute :last_seen_at, :utc_datetime_usec, allow_nil?: false, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :shop_product, [:shop, :shop_product_id]
  end
end
