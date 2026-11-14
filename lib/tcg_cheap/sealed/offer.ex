defmodule TcgCheap.Sealed.Offer do
  @moduledoc """
  One product listed by a shop, as last seen in that shop's feed.

  `product_id` is set by automatic matching, or by an administrator when
  `manual?` is true; automatic matching never overwrites a manual assignment.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_offers"
    repo TcgCheap.Repo

    references do
      reference :product, on_delete: :nilify
    end

    custom_indexes do
      index [:last_seen_at]
      index [:product_id, :last_seen_at]
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
        :shop_price,
        :currency,
        :in_stock,
        :preorder,
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
        :shop_price,
        :currency,
        :in_stock,
        :preorder,
        :last_seen_at,
        :updated_at
      ]
    end

    update :match do
      description "Automatic matching; refuses to touch manual assignments."
      accept [:product_id]
      validate attribute_equals(:manual?, false)
    end

    update :assign_manually do
      accept [:product_id]
      change set_attribute(:manual?, true)
      validate present(:product_id)
    end

    update :exclude_manually do
      description "Keeps the offer unmatched for good, e.g. after a wrong automatic match."
      change set_attribute(:manual?, true)
      change set_attribute(:product_id, nil)
    end

    update :clear_manual do
      change set_attribute(:manual?, false)
      change set_attribute(:product_id, nil)
    end

    read :seen_since do
      argument :since, :utc_datetime_usec, allow_nil?: false
      filter expr(last_seen_at >= ^arg(:since))
      prepare build(sort: [shop: :asc, price: :asc, id: :asc])
    end

    read :seen_since_for_products do
      argument :since, :utc_datetime_usec, allow_nil?: false
      argument :product_ids, {:array, :uuid}, allow_nil?: false
      filter expr(last_seen_at >= ^arg(:since) and product_id in ^arg(:product_ids))
      prepare build(sort: [shop: :asc, price: :asc, id: :asc])
    end

    action :latest_fetches, :map do
      description "Per shop, the time of its latest fetch since a time."
      argument :since, :utc_datetime_usec, allow_nil?: false
      run TcgCheap.Sealed.Offer.LatestFetches
    end

    read :manual do
      filter expr(manual? == true)
      prepare build(sort: [shop: :asc, title: :asc], load: [:product])
    end
  end

  validations do
    validate compare(:price, greater_than: 0)
    validate compare(:shop_price, greater_than: 0)
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

    attribute :shop_price, :decimal do
      description "The shop's own price, in `currency`; `price` is it in PLN as of the fetch. Nil until the shop's first fetch that records it."
      public? true
    end

    attribute :currency, :string do
      description "The ISO code of `shop_price`'s currency, the shop's."
      public? true
      constraints max_length: 3
    end

    attribute :in_stock, :boolean, allow_nil?: false, public?: true

    attribute :preorder, :boolean do
      description "Sold as a pre-order: never in stock, shown apart from offers without stock."
      allow_nil? false
      default false
      public? true
    end

    attribute :manual?, :boolean, allow_nil?: false, default: false, public?: true
    attribute :last_seen_at, :utc_datetime_usec, allow_nil?: false, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :product, TcgCheap.Sealed.Product, public?: true
  end

  identities do
    identity :shop_product, [:shop, :shop_product_id]
  end
end
