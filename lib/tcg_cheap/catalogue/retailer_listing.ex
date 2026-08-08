defmodule TcgCheap.Catalogue.RetailerListing do
  @moduledoc "The current local projection of a retailer listing."
  alias TcgCheap.Catalogue.SealedIdentifier
  use Ash.Resource, otp_app: :tcg_cheap, domain: TcgCheap.Core, data_layer: AshPostgres.DataLayer

  postgres do
    table "retailer_listings"
    repo TcgCheap.Repo

    references do
      reference :retailer, on_delete: :delete
    end

    check_constraints do
      check_constraint [:source_listing_id, :source_title, :normalized_title, :direct_url],
                       "retailer_listings_identity_invariant",
                       check:
                         "btrim(source_listing_id) <> '' AND btrim(source_title) <> '' AND btrim(normalized_title) <> '' AND direct_url ~ '^https://[^/?#[:space:]]+(/|[/?#].*)?$'"

      check_constraint [:gtin], "retailer_listings_gtin_invariant",
        check: "gtin IS NULL OR #{SealedIdentifier.postgres_gtin_check("gtin")}"

      check_constraint [:currency], "retailer_listings_currency_invariant",
        check: "currency = 'PLN'"

      check_constraint [:stock_status, :current_price_pln],
                       "retailer_listings_stock_price_invariant",
                       check:
                         "stock_status IN ('in_stock', 'sold_out', 'unknown') AND (stock_status <> 'in_stock' OR (current_price_pln IS NOT NULL AND current_price_pln > 0))"

      check_constraint [:status], "retailer_listings_status_invariant",
        check: "status IN ('active', 'disabled')"

      check_constraint [:current_price_pln], "retailer_listings_price_finite_invariant",
        check:
          "current_price_pln IS NULL OR (current_price_pln > 0 AND current_price_pln <> 'NaN'::numeric AND current_price_pln <> 'Infinity'::numeric AND current_price_pln <> '-Infinity'::numeric)"

      check_constraint [:first_seen_at, :last_seen_at, :last_checked_at],
                       "retailer_listings_times_invariant",
                       check: "first_seen_at <= last_seen_at AND last_seen_at <= last_checked_at"

      custom_indexes do
        index "retailer_id", name: "retailer_listings_retailer_id_index"
      end
    end
  end

  actions do
    defaults [:read]

    create :ingest do
      transaction? true
      touches_resources [TcgCheap.Pricing.SealedListingObservation]

      accept [
        :retailer_id,
        :source_listing_id,
        :source_title,
        :direct_url,
        :gtin,
        :current_price_pln,
        :currency,
        :stock_status,
        :first_seen_at,
        :last_seen_at,
        :last_checked_at,
        :source_payload
      ]

      change TcgCheap.Catalogue.Changes.NormalizeRetailerListing
      change TcgCheap.Catalogue.Changes.LockRetailerListingIngest
      change TcgCheap.Catalogue.Changes.RecordSealedListingObservation
      validate TcgCheap.Catalogue.Validations.RetailerListing
      upsert? true
      upsert_identity :unique_retailer_source_listing

      upsert_fields [
        :source_title,
        :normalized_title,
        :direct_url,
        :gtin,
        :current_price_pln,
        :currency,
        :stock_status,
        :last_seen_at,
        :last_checked_at,
        :source_payload
      ]

      upsert_condition expr(
                         status == "active" and status == upsert_conflict(:status) and
                           upsert_conflict(:last_seen_at) >= last_seen_at and
                           upsert_conflict(:last_checked_at) >= last_checked_at
                       )

      return_skipped_upsert? true
    end

    update :disable do
      accept []
      change set_attribute(:status, "disabled")
    end

    read :by_source_listing do
      argument :retailer_id, :uuid, allow_nil?: false
      argument :source_listing_id, :string, allow_nil?: false
      get? true

      filter expr(
               retailer_id == ^arg(:retailer_id) and source_listing_id == ^arg(:source_listing_id)
             )
    end

    read :active_for_retailer do
      argument :retailer_id, :uuid, allow_nil?: false
      filter expr(retailer_id == ^arg(:retailer_id) and status == "active")
      prepare build(sort: [normalized_title: :asc, source_listing_id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :source_listing_id, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 240]

    attribute :source_title, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 500]

    attribute :normalized_title, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 500]

    attribute :direct_url, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 2_000]

    attribute :gtin, :string, public?: true, constraints: [max_length: 14]
    attribute :current_price_pln, :decimal, public?: true
    attribute :currency, :string, allow_nil?: false, default: "PLN", public?: true
    attribute :stock_status, :string, allow_nil?: false, default: "unknown", public?: true
    attribute :status, :string, allow_nil?: false, default: "active", public?: true
    attribute :first_seen_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :last_seen_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :last_checked_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :source_payload, :map, public?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :retailer, TcgCheap.Catalogue.Retailer, allow_nil?: false, public?: true

    has_many :sealed_listing_observations, TcgCheap.Pricing.SealedListingObservation,
      destination_attribute: :retailer_listing_id,
      public?: true
  end

  identities do
    identity :unique_retailer_source_listing, [:retailer_id, :source_listing_id]
  end
end
