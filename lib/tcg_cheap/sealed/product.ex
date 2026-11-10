defmodule TcgCheap.Sealed.Product do
  @moduledoc """
  One sealed product from the Cardmarket catalogue, with its latest Cardmarket
  price (EUR) and the current shop availability derived from offers.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage]

  alias TcgCheap.Sealed.{Kinds, Regions}
  alias TcgCheap.Sealed.Preparations.{Browse, PhotosMissingVariant}
  alias TcgCheap.Storage.Calculations.StoredVariant
  alias TcgCheap.Storage.Variants.ResizedImage

  postgres do
    table "sealed_products"
    repo TcgCheap.Repo

    custom_indexes do
      index [:available, :cardmarket_added_on]
      index [:kind]
      index [:region]
      index [:cardmarket_expansion_id]
    end

    custom_statements do
      # ParadeDB full-text index for `Preparations.Browse`.
      statement :sealed_products_search_index do
        up "CREATE INDEX sealed_products_search_index ON sealed_products USING paradedb (id, search_text)"
        down "DROP INDEX sealed_products_search_index"
      end
    end
  end

  # The packaging photo, mirrored from the shop that offers the product or
  # from a `checked_photo_url` (`TcgCheap.Sealed.PhotoMirror`), in the sizes
  # the pages show: `small` for list rows, `card` and `page` for larger
  # screens and the product page.
  storage do
    blob_resource(TcgCheap.Storage.Blob)
    attachment_resource(TcgCheap.Storage.Attachment)

    has_one_attached :photo do
      variant(:small, {ResizedImage, width: 192}, generate: :eager)
      variant(:card, {ResizedImage, width: 352}, generate: :eager)
      variant(:page, {ResizedImage, width: 960}, generate: :eager)
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
      accept [:available, :lowest_price, :lowest_preorder_price, :image_url]
    end

    update :set_eans do
      description "Replaces the product's barcodes (EAN-13 or UPC-A, check digit verified)."
      argument :eans, {:array, :string}, allow_nil?: false
      change TcgCheap.Sealed.Changes.SetEans
    end

    read :photos_to_mirror do
      description "Products whose shop photo is not mirrored yet, or changed since."
      argument :limit, :integer, allow_nil?: false

      filter expr(
               (not is_nil(checked_photo_url) and
                  (is_nil(photo_source_url) or photo_source_url != checked_photo_url)) or
                 (is_nil(checked_photo_url) and not is_nil(image_url) and
                    (is_nil(photo_source_url) or photo_source_url != image_url))
             )

      filter expr(is_nil(photo_attempted_at) or photo_attempted_at < ago(1, :hour))

      prepare build(
                sort: [photo_attempted_at: :asc_nils_first, available: :desc],
                limit: arg(:limit)
              )
    end

    read :photos_missing_variants do
      description "Mirrored photos lacking the current version of a variant, e.g. one added since."
      argument :limit, :integer, allow_nil?: false
      prepare PhotosMissingVariant
      prepare build(limit: arg(:limit))
    end

    update :record_photo_source do
      accept [:photo_source_url]
      change set_attribute(:photo_attempted_at, &DateTime.utc_now/0)
    end

    update :set_photo do
      description "Sets the checked photo that replaces the shops' photos; nil goes back to them."
      accept [:checked_photo_url]
      # Copied on the mirror's next run, even from the url already stored.
      change set_attribute(:photo_source_url, nil)
      change set_attribute(:photo_attempted_at, nil)
      change TcgCheap.Sealed.Changes.DropUnsourcedPhoto
    end

    update :record_photo_attempt do
      accept []
      change set_attribute(:photo_attempted_at, &DateTime.utc_now/0)
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

    read :boosters_by_name do
      description "Single boosters of one edition with these exact names, e.g. \"Delta Reign Booster\"."
      argument :names, {:array, :string}, allow_nil?: false
      argument :region, :atom, allow_nil?: false, constraints: [one_of: Regions.all()]
      filter expr(kind == :booster and region == ^arg(:region) and name in ^arg(:names))
    end

    read :browse do
      description "Products for the public list: in stock in Poland first, then pre-orders, then the best matches of a search, then newest."
      argument :query, :string, default: ""
      argument :kind, :atom, constraints: [one_of: Kinds.choices()]
      argument :region, :atom, constraints: [one_of: Regions.all()]
      argument :expansion, :integer, description: "A Cardmarket expansion id."

      pagination offset?: true, default_limit: 30, max_page_size: 100, countable: true
      prepare Browse
    end

    read :facets do
      description "Every product the public list would show, unpaged, for its filter counts."
      argument :query, :string, default: ""
      argument :kind, :atom, constraints: [one_of: Kinds.choices()]
      argument :region, :atom, constraints: [one_of: Regions.all()]
      argument :expansion, :integer
      prepare Browse

      prepare build(
                select: [
                  :region,
                  :kind,
                  :cardmarket_expansion_id,
                  :set_name,
                  :cardmarket_added_on,
                  :available
                ]
              )
    end

    action :facet_counts, {:array, :map} do
      description "The `:facets` products of a search, counted per edition, kind, expansion and set name."
      argument :query, :string, default: ""
      run TcgCheap.Sealed.Product.FacetCounts
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
    attribute :search_text, :string, allow_nil?: false, public?: true, default: ""

    attribute :image_url, :string, public?: true, constraints: [max_length: 2_000]
    attribute :cardmarket_trend, :decimal, public?: true
    attribute :cardmarket_low, :decimal, public?: true
    attribute :cardmarket_avg, :decimal, public?: true
    attribute :cardmarket_price_updated_on, :date, public?: true
    attribute :available, :boolean, allow_nil?: false, default: false, public?: true
    attribute :lowest_price, :decimal, public?: true

    attribute :lowest_preorder_price, :decimal do
      description "The cheapest current pre-order, while no offer is in stock."
      public? true
    end

    attribute :eans, {:array, :string} do
      description "EAN-13 barcodes printed on the product, maintained by an admin or agent."
      allow_nil? false
      default []
      public? true
    end

    attribute :photo_attempted_at, :utc_datetime_usec

    attribute :photo_source_url, :string do
      description "The offer photo (`image_url`) the stored photo was chosen for; the stored photo may be a larger one from another offer."
      public? true
      constraints max_length: 2_000
    end

    attribute :checked_photo_url, :string do
      description "A photo of the product an admin or agent checked by eye, on an allowed image host; stored instead of the shops' photos while set."
      public? true
      constraints max_length: 2_000
    end

    attribute :contents, TcgCheap.Sealed.ProductContents do
      description "What the box holds, maintained by an admin or agent."
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  calculations do
    calculate :photo_placeholder,
              :string,
              {StoredVariant, attachment: :photo, variant: :card, value: :placeholder} do
      description "Inline blurred preview shown while the photo loads."
      public? true
    end

    calculate :stored_photo_small_url,
              :string,
              {StoredVariant, attachment: :photo, variant: :small, value: :url} do
      description "The `small` photo once stored; rendering never generates it."
      public? true
    end

    calculate :stored_photo_card_url,
              :string,
              {StoredVariant, attachment: :photo, variant: :card, value: :url} do
      description "The `card` photo once stored; rendering never generates it."
      public? true
    end

    calculate :stored_photo_page_url,
              :string,
              {StoredVariant, attachment: :photo, variant: :page, value: :url} do
      description "The `page` photo once stored; rendering never generates it."
      public? true
    end
  end

  identities do
    identity :cardmarket_id, [:cardmarket_id]
    identity :slug, [:slug]
  end
end
