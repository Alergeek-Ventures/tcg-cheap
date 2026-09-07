defmodule TcgCheap.Pricing.CardmarketBulk.Batch do
  @moduledoc "Lifecycle evidence for a Cardmarket bulk import and its promotion outcome."

  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cardmarket_bulk_batches"
    repo TcgCheap.Repo

    check_constraints do
      check_constraint [:policy_version, :parser_version],
                       "cardmarket_bulk_batches_versions_present",
                       check: "btrim(policy_version) <> '' AND btrim(parser_version) <> ''"

      check_constraint [:product_sha256, :price_sha256], "cardmarket_bulk_batches_hashes_hex",
        check: "product_sha256 ~ '^[0-9a-fA-F]{64}$' AND price_sha256 ~ '^[0-9a-fA-F]{64}$'"

      check_constraint [
                         :product_row_count,
                         :price_row_count,
                         :singles_price_row_count,
                         :priceable_singles_count
                       ],
                       "cardmarket_bulk_batches_counts_coherent",
                       check:
                         "product_row_count > 0 AND price_row_count > 0 AND singles_price_row_count > 0 AND priceable_singles_count > 0 AND price_row_count >= singles_price_row_count AND product_row_count = singles_price_row_count AND priceable_singles_count <= singles_price_row_count"

      check_constraint [:product_byte_size, :price_byte_size],
                       "cardmarket_bulk_batches_sizes_positive",
                       check: "product_byte_size > 0 AND price_byte_size > 0"

      check_constraint [:status], "cardmarket_bulk_batches_status_valid",
        check: "status IN ('staged', 'succeeded', 'failed')"

      check_constraint [:failure_summary], "cardmarket_bulk_batches_failure_summary_bounded",
        check:
          "failure_summary IS NULL OR (btrim(failure_summary) <> '' AND octet_length(failure_summary) <= 160)"

      check_constraint [:status, :completed_at, :failure_summary],
                       "cardmarket_bulk_batches_lifecycle_coherent",
                       check:
                         "(status = 'staged' AND completed_at IS NULL AND failure_summary IS NULL) OR (status = 'succeeded' AND completed_at IS NOT NULL AND failure_summary IS NULL) OR (status = 'failed' AND completed_at IS NOT NULL AND failure_summary IS NOT NULL)"

      check_constraint [:product_created_at, :price_created_at, :fetched_at, :completed_at],
                       "cardmarket_bulk_batches_timestamps_coherent",
                       check:
                         "fetched_at >= product_created_at AND fetched_at >= price_created_at AND (completed_at IS NULL OR completed_at >= fetched_at)"
    end
  end

  actions do
    read :read

    read :latest do
      prepare build(
                sort: [completed_at: :desc, id: :desc],
                filter: expr(status == "succeeded"),
                limit: 1
              )

      get? true
    end

    read :latest_successful do
      prepare build(
                sort: [completed_at: :desc, id: :desc],
                filter: expr(status == "succeeded"),
                limit: 1
              )

      get? true
    end

    read :by_identity do
      argument :policy_version, :string, allow_nil?: false
      argument :product_created_at, :utc_datetime_usec, allow_nil?: false
      argument :price_created_at, :utc_datetime_usec, allow_nil?: false
      argument :product_sha256, :string, allow_nil?: false
      argument :price_sha256, :string, allow_nil?: false
      get? true

      filter expr(
               policy_version == ^arg(:policy_version) and
                 product_created_at == ^arg(:product_created_at) and
                 price_created_at == ^arg(:price_created_at) and
                 product_sha256 == ^arg(:product_sha256) and
                 price_sha256 == ^arg(:price_sha256)
             )
    end

    create :complete do
      accept [
        :policy_version,
        :parser_version,
        :product_created_at,
        :price_created_at,
        :fetched_at,
        :completed_at,
        :product_sha256,
        :price_sha256,
        :product_byte_size,
        :price_byte_size,
        :product_row_count,
        :price_row_count,
        :singles_price_row_count,
        :priceable_singles_count
      ]

      change set_attribute(:status, "succeeded")
    end

    create :stage do
      accept [
        :policy_version,
        :parser_version,
        :product_created_at,
        :price_created_at,
        :fetched_at,
        :product_sha256,
        :price_sha256,
        :product_byte_size,
        :price_byte_size,
        :product_row_count,
        :price_row_count,
        :singles_price_row_count,
        :priceable_singles_count
      ]

      change set_attribute(:status, "staged")
    end

    update :succeed do
      accept [:completed_at]
      require_atomic? false
      change set_attribute(:status, "succeeded")
      change set_attribute(:failure_summary, nil)
    end

    update :fail do
      accept [:completed_at, :failure_summary]
      require_atomic? false
      validate one_of(:status, ["staged", "failed"])
      change set_attribute(:status, "failed")
    end
  end

  policies do
    bypass action([:complete, :stage, :succeed, :fail, :by_identity, :latest, :latest_successful]) do
      authorize_if always()
    end

    policy action_type(:read) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  validations do
    validate match(:policy_version, ~r/\S+/)
    validate match(:parser_version, ~r/\S+/)
    validate match(:product_sha256, ~r/\A[0-9a-fA-F]{64}\z/)
    validate match(:price_sha256, ~r/\A[0-9a-fA-F]{64}\z/)
    validate compare(:product_byte_size, greater_than: 0)
    validate compare(:price_byte_size, greater_than: 0)
    validate compare(:product_row_count, greater_than: 0)
    validate compare(:price_row_count, greater_than: 0)
    validate compare(:singles_price_row_count, greater_than_or_equal_to: 0)
    validate compare(:priceable_singles_count, greater_than_or_equal_to: 0)
    validate compare(:priceable_singles_count, less_than_or_equal_to: :singles_price_row_count)
    validate compare(:completed_at, greater_than_or_equal_to: :fetched_at)
  end

  attributes do
    uuid_primary_key :id

    attribute :policy_version, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 160]

    attribute :parser_version, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 160]

    attribute :product_created_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :price_created_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :fetched_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :completed_at, :utc_datetime_usec, allow_nil?: true, public?: true

    attribute :status, :string,
      allow_nil?: false,
      default: "staged",
      public?: true,
      constraints: [min_length: 6, max_length: 9]

    attribute :failure_summary, :string,
      allow_nil?: true,
      public?: true,
      constraints: [max_length: 160]

    attribute :product_sha256, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 64, max_length: 64]

    attribute :price_sha256, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 64, max_length: 64]

    attribute :product_byte_size, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]

    attribute :price_byte_size, :integer, allow_nil?: false, public?: true, constraints: [min: 1]

    attribute :product_row_count, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]

    attribute :price_row_count, :integer, allow_nil?: false, public?: true, constraints: [min: 1]

    attribute :singles_price_row_count, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0]

    attribute :priceable_singles_count, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0]

    create_timestamp :inserted_at, public?: true
  end

  identities do
    identity :unique_import, [
      :policy_version,
      :product_created_at,
      :price_created_at,
      :product_sha256,
      :price_sha256
    ]
  end
end
