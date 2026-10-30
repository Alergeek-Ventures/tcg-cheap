defmodule TcgCheap.Sealed.Product do
  @moduledoc """
  One sealed product from the Cardmarket catalogue, with its latest Cardmarket
  price (EUR) and the current Polish shop availability derived from offers.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  alias TcgCheap.Sealed.Kinds
  alias TcgCheap.Sealed.Preparations.Browse

  postgres do
    table "sealed_products"
    repo TcgCheap.Repo

    custom_indexes do
      index [:available, :cardmarket_added_on]
      index [:kind]
    end
  end

  actions do
    defaults [:read]

    create :import do
      accept [
        :cardmarket_id,
        :name,
        :kind,
        :cardmarket_category_id,
        :cardmarket_expansion_id,
        :set_name,
        :cardmarket_added_on,
        :slug,
        :search_text,
        :cardmarket_trend,
        :cardmarket_low,
        :cardmarket_avg,
        :cardmarket_price_updated_on
      ]

      upsert? true
      upsert_identity :cardmarket_id

      # The slug stays stable so product URLs survive renames on Cardmarket.
      upsert_fields [
        :name,
        :kind,
        :cardmarket_category_id,
        :cardmarket_expansion_id,
        :set_name,
        :cardmarket_added_on,
        :search_text,
        :cardmarket_trend,
        :cardmarket_low,
        :cardmarket_avg,
        :cardmarket_price_updated_on,
        :updated_at
      ]
    end

    update :set_availability do
      accept [:available, :lowest_price, :image_url]
    end

    read :by_slug do
      argument :slug, :string, allow_nil?: false
      get? true
      filter expr(slug == ^arg(:slug))
    end

    read :browse do
      description "Products for the public list: in stock in Poland first, then newest."
      argument :query, :string, default: ""
      argument :kind, :atom, constraints: [one_of: Kinds.all()]

      pagination offset?: true, default_limit: 30, max_page_size: 100, countable: true
      prepare Browse
    end
  end

  validations do
    validate one_of(:kind, Kinds.all())
  end

  attributes do
    uuid_primary_key :id
    attribute :cardmarket_id, :integer, allow_nil?: false, public?: true

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints max_length: 300
    end

    attribute :kind, :atom, allow_nil?: false, public?: true
    attribute :cardmarket_category_id, :integer, public?: true
    attribute :cardmarket_expansion_id, :integer, public?: true
    attribute :set_name, :string, public?: true, constraints: [max_length: 200]
    attribute :cardmarket_added_on, :date, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true, constraints: [max_length: 220]
    attribute :search_text, :string, allow_nil?: false, public?: true, default: ""
    attribute :image_url, :string, public?: true, constraints: [max_length: 2_000]
    attribute :cardmarket_trend, :decimal, public?: true
    attribute :cardmarket_low, :decimal, public?: true
    attribute :cardmarket_avg, :decimal, public?: true
    attribute :cardmarket_price_updated_on, :date, public?: true
    attribute :available, :boolean, allow_nil?: false, default: false, public?: true
    attribute :lowest_price, :decimal, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :cardmarket_id, [:cardmarket_id]
    identity :slug, [:slug]
  end
end
