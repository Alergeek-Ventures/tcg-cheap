defmodule TcgCheap.Sealed.Product do
  @moduledoc """
  One sealed product from the Cardmarket catalogue, with its latest Cardmarket
  price (EUR) and the current Polish shop availability derived from offers.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  alias TcgCheap.Sealed.{Kinds, Regions}
  alias TcgCheap.Sealed.Preparations.Browse

  postgres do
    table "sealed_products"
    repo TcgCheap.Repo

    custom_indexes do
      index [:available, :cardmarket_added_on]
      index [:kind]
      index [:region]
      index [:cardmarket_expansion_id]
    end
  end

  actions do
    defaults [:read]

    create :import do
      accept [
        :cardmarket_id,
        :name,
        :kind,
        :region,
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
        :region,
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

    update :set_eans do
      description "Replaces the product's barcodes (EAN-13 or UPC-A, check digit verified)."
      argument :eans, {:array, :string}, allow_nil?: false
      change TcgCheap.Sealed.Changes.SetEans
    end

    update :set_contents do
      description "Replaces what the product holds; nil removes it."
      accept [:contents]
    end

    read :with_eans do
      description "Products with at least one known barcode."
      filter expr(fragment("cardinality(?) > 0", eans))
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
      argument :region, :atom, constraints: [one_of: Regions.all()]
      argument :expansion, :integer, description: "A Cardmarket expansion id."

      pagination offset?: true, default_limit: 30, max_page_size: 100, countable: true
      prepare Browse
    end

    read :facets do
      description "Every product the public list would show, unpaged, for its filter counts."
      argument :query, :string, default: ""
      argument :kind, :atom, constraints: [one_of: Kinds.all()]
      argument :region, :atom, constraints: [one_of: Regions.all()]
      argument :expansion, :integer
      prepare Browse

      prepare build(
                select: [
                  :region,
                  :cardmarket_expansion_id,
                  :set_name,
                  :cardmarket_added_on,
                  :available
                ]
              )
    end
  end

  validations do
    validate one_of(:kind, Kinds.all())
    validate one_of(:region, Regions.all())
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

    attribute :region, :atom do
      description "Language edition, see `TcgCheap.Sealed.Regions`."
      allow_nil? false
      default :en
      public? true
    end

    attribute :cardmarket_category_id, :integer, public?: true
    attribute :cardmarket_expansion_id, :integer, public?: true
    attribute :set_name, :string, public?: true, constraints: [max_length: 200]
    attribute :cardmarket_added_on, :date, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true, constraints: [max_length: 220]
    # Untrimmed: the leading space lets every word be found as a prefix.
    attribute :search_text, :string,
      allow_nil?: false,
      public?: true,
      default: "",
      constraints: [trim?: false]

    attribute :image_url, :string, public?: true, constraints: [max_length: 2_000]
    attribute :cardmarket_trend, :decimal, public?: true
    attribute :cardmarket_low, :decimal, public?: true
    attribute :cardmarket_avg, :decimal, public?: true
    attribute :cardmarket_price_updated_on, :date, public?: true
    attribute :available, :boolean, allow_nil?: false, default: false, public?: true
    attribute :lowest_price, :decimal, public?: true

    attribute :eans, {:array, :string} do
      description "EAN-13 barcodes printed on the product, maintained by an admin or agent."
      allow_nil? false
      default []
      public? true
    end

    attribute :contents, TcgCheap.Sealed.ProductContents do
      description "What the box holds, maintained by an admin or agent."
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :cardmarket_id, [:cardmarket_id]
    identity :slug, [:slug]
  end
end
