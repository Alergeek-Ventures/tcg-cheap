defmodule TcgCheap.Pricing.CardmarketBulk.RawResponse do
  @moduledoc "Immutable compressed Cardmarket bulk response retained per import batch."
  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cardmarket_bulk_raw_responses"
    repo TcgCheap.Repo

    custom_indexes do
      index [:batch_id]
    end

    references do
      reference :batch, on_delete: :restrict
    end

    check_constraints do
      check_constraint [:endpoint_kind, :content_type, :content_encoding],
                       "cardmarket_bulk_raw_responses_kind_invariant",
                       check:
                         "endpoint_kind IN ('products', 'prices') AND content_type = 'application/json' AND content_encoding = 'gzip'"

      check_constraint [:endpoint_kind, :source_url],
                       "cardmarket_bulk_raw_responses_url_invariant",
                       check:
                         "(endpoint_kind = 'products' AND source_url = 'https://downloads.s3.cardmarket.com/productCatalog/productList/products_singles_6.json') OR (endpoint_kind = 'prices' AND source_url = 'https://downloads.s3.cardmarket.com/productCatalog/priceGuide/price_guide_6.json')"

      check_constraint [:source_byte_size, :compressed_byte_size, :body],
                       "cardmarket_bulk_raw_responses_body_invariant",
                       check:
                         "source_byte_size > 0 AND compressed_byte_size > 0 AND octet_length(body) = compressed_byte_size"

      check_constraint [:sha256], "cardmarket_bulk_raw_responses_hash_hex",
        check: "sha256 ~ '^[0-9a-fA-F]{64}$'"

      check_constraint [:fetched_at, :upstream_created_at],
                       "cardmarket_bulk_raw_responses_timestamps_coherent",
                       check: "fetched_at >= upstream_created_at"
    end
  end

  actions do
    read :read

    create :store do
      accept [
        :batch_id,
        :endpoint_kind,
        :source_url,
        :content_type,
        :content_encoding,
        :source_byte_size,
        :compressed_byte_size,
        :sha256,
        :body,
        :fetched_at,
        :upstream_created_at
      ]
    end

    read :for_batch do
      argument :batch_id, :uuid, allow_nil?: false
      filter expr(batch_id == ^arg(:batch_id))
    end

    read :by_sha256 do
      argument :endpoint_kind, :string, allow_nil?: false
      argument :sha256, :string, allow_nil?: false
      filter expr(endpoint_kind == ^arg(:endpoint_kind) and sha256 == ^arg(:sha256))
      prepare build(limit: 1)
      get? true
    end
  end

  policies do
    bypass action([:store, :for_batch, :by_sha256]) do
      authorize_if always()
    end

    policy action_type(:read) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  validations do
    validate one_of(:endpoint_kind, ["products", "prices"])
    validate match(:sha256, ~r/\A[0-9a-fA-F]{64}\z/)
    validate compare(:source_byte_size, greater_than: 0)
    validate compare(:compressed_byte_size, greater_than: 0)
  end

  attributes do
    uuid_primary_key :id

    attribute :endpoint_kind, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 20]

    attribute :source_url, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 2_000]

    attribute :content_type, :string,
      allow_nil?: false,
      default: "application/json",
      public?: true

    attribute :content_encoding, :string,
      allow_nil?: false,
      default: "gzip",
      public?: true,
      constraints: [min_length: 4, max_length: 16]

    attribute :source_byte_size, :integer, allow_nil?: false, public?: true, constraints: [min: 1]

    attribute :compressed_byte_size, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]

    attribute :sha256, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 64, max_length: 64]

    attribute :body, :binary, allow_nil?: false, public?: false, select_by_default?: false
    attribute :fetched_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :upstream_created_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :batch, TcgCheap.Pricing.CardmarketBulk.Batch, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_batch_endpoint, [:batch_id, :endpoint_kind]
  end
end
