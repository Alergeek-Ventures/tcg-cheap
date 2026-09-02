defmodule TcgCheap.Pricing.SealedListingObservation do
  @moduledoc "An immutable observation of a sealed retailer listing."

  alias TcgCheap.Catalogue.{ExternalUrl, SealedIdentifier}

  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_listing_observations"
    repo TcgCheap.Repo

    identity_index_names unique_listing_observation_boundary:
                           "sealed_listing_observations_listing_observed_index"

    references do
      reference :retailer_listing, on_delete: :restrict
    end

    check_constraints do
      check_constraint [:source_title, :normalized_title, :direct_url],
                       "sealed_listing_observations_identity_invariant",
                       check:
                         "btrim(source_title) <> '' AND btrim(normalized_title) <> '' AND #{ExternalUrl.postgres_url_check("direct_url")}"

      check_constraint [:gtin], "sealed_listing_observations_gtin_invariant",
        check: "gtin IS NULL OR #{SealedIdentifier.postgres_gtin_check("gtin")}"

      check_constraint [:currency], "sealed_listing_observations_currency_invariant",
        check: "currency = 'PLN'"

      check_constraint [:stock_status, :price_pln],
                       "sealed_listing_observations_stock_price_invariant",
                       check:
                         "stock_status IN ('in_stock', 'sold_out', 'unknown') AND (stock_status <> 'in_stock' OR (price_pln IS NOT NULL AND price_pln > 0))"

      check_constraint [:price_pln], "sealed_listing_observations_price_finite_invariant",
        check:
          "price_pln IS NULL OR (price_pln > 0 AND price_pln <> 'NaN'::numeric AND price_pln <> 'Infinity'::numeric AND price_pln <> '-Infinity'::numeric)"

      custom_indexes do
        index [:retailer_listing_id, :observed_at, :id]
      end
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :retailer_listing_id,
        :source_title,
        :normalized_title,
        :direct_url,
        :gtin,
        :price_pln,
        :currency,
        :stock_status,
        :observed_at,
        :source_payload
      ]

      change TcgCheap.Pricing.Changes.NormalizeSealedListingObservation
      validate TcgCheap.Pricing.Validations.SealedListingObservation
    end

    read :latest_for_listing do
      argument :retailer_listing_id, :uuid, allow_nil?: false
      get? true
      filter expr(retailer_listing_id == ^arg(:retailer_listing_id))
      prepare build(sort: [observed_at: :desc, id: :desc], limit: 1)
    end

    read :history_for_listing do
      argument :retailer_listing_id, :uuid, allow_nil?: false
      filter expr(retailer_listing_id == ^arg(:retailer_listing_id))
      prepare build(sort: [observed_at: :asc, id: :asc])
    end
  end

  validations do
    validate one_of(:currency, ["PLN"])
    validate one_of(:stock_status, ["in_stock", "sold_out", "unknown"])
  end

  attributes do
    uuid_primary_key :id

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
    attribute :price_pln, :decimal, public?: true
    attribute :currency, :string, allow_nil?: false, default: "PLN", public?: true
    attribute :stock_status, :string, allow_nil?: false, default: "unknown", public?: true
    attribute :observed_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :source_payload, :map, public?: false
    create_timestamp :created_at
  end

  relationships do
    belongs_to :retailer_listing, TcgCheap.Catalogue.RetailerListing,
      allow_nil?: false,
      public?: true
  end

  identities do
    identity :unique_listing_observation_boundary, [:retailer_listing_id, :observed_at]
  end
end
