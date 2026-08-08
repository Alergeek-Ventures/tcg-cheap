defmodule TcgCheap.Catalogue.Retailer do
  @moduledoc "A source-neutral retailer identity."
  use Ash.Resource, otp_app: :tcg_cheap, domain: TcgCheap.Core, data_layer: AshPostgres.DataLayer

  postgres do
    table "retailers"
    repo TcgCheap.Repo

    check_constraints do
      check_constraint [:slug, :source_key, :name, :category, :status],
                       "retailers_identity_invariant",
                       check:
                         "slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND btrim(source_key) <> '' AND btrim(name) <> ''"

      check_constraint [:category], "retailers_category_invariant",
        check: "category IN ('regular_retailer', 'lgs')"

      check_constraint [:status], "retailers_status_invariant",
        check: "status IN ('active', 'disabled')"

      check_constraint [:homepage_url], "retailers_homepage_url_invariant",
        check: "homepage_url IS NULL OR homepage_url ~ '^https://[^/?#[:space:]]+(/|[/?#].*)?$'"
    end
  end

  actions do
    defaults [:read]

    create :register do
      accept [:slug, :source_key, :name, :category, :homepage_url, :metadata, :source_payload]
      change TcgCheap.Catalogue.Changes.NormalizeRetailer
      validate TcgCheap.Catalogue.Validations.Retailer
      upsert? true
      upsert_identity :unique_source_key
      upsert_fields [:slug, :name, :category, :homepage_url, :metadata, :source_payload]
      upsert_condition expr(status == "active" and status == upsert_conflict(:status))
      return_skipped_upsert? true
    end

    update :disable do
      accept []
      change set_attribute(:status, "disabled")
    end

    update :enable do
      accept []
      change set_attribute(:status, "active")
    end

    read :by_source_key do
      argument :source_key, :string, allow_nil?: false
      get? true
      filter expr(source_key == ^arg(:source_key))
    end

    read :active do
      filter expr(status == "active")
      prepare build(sort: [name: :asc, slug: :asc])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :slug, :string, allow_nil?: false, public?: true, constraints: [max_length: 120]

    attribute :source_key, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 160]

    attribute :name, :string, allow_nil?: false, public?: true, constraints: [max_length: 240]
    attribute :category, :string, allow_nil?: false, public?: true, constraints: [max_length: 32]
    attribute :status, :string, allow_nil?: false, default: "active", public?: true
    attribute :homepage_url, :string, public?: true, constraints: [max_length: 2_000]
    attribute :metadata, :map, public?: false
    attribute :source_payload, :map, public?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_source_key, [:source_key]
    identity :unique_slug, [:slug]
  end
end
