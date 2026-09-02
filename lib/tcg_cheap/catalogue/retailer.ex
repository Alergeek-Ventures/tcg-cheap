defmodule TcgCheap.Catalogue.Retailer do
  @moduledoc "A source-neutral retailer identity."
  alias TcgCheap.Catalogue.ExternalUrl

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

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
        check: "homepage_url IS NULL OR #{ExternalUrl.postgres_url_check("homepage_url")}"
    end
  end

  actions do
    defaults [:read]

    create :admin_create do
      accept [:slug, :source_key, :name, :category, :homepage_url]
      change TcgCheap.Catalogue.Changes.NormalizeRetailer
      validate TcgCheap.Catalogue.Validations.Retailer
    end

    update :admin_update do
      argument :expected_updated_at, :utc_datetime_usec, allow_nil?: false
      accept [:slug, :name, :category, :status, :homepage_url]
      require_atomic? false
      change TcgCheap.Catalogue.Changes.NormalizeRetailer
      validate TcgCheap.Catalogue.Validations.Retailer
      validate one_of(:status, ["active", "disabled"])

      change {TcgCheap.Catalogue.Changes.LockAndValidateReview,
              resource: __MODULE__,
              lock_action: :lock_for_update_by_id,
              status_attribute: :status,
              expected_status: ["active", "disabled"],
              version_argument: :expected_updated_at}
    end

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

    read :admin_catalogue do
      prepare build(sort: [name: :asc, slug: :asc, source_key: :asc, id: :asc])
    end

    read :lock_for_update_by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
      prepare build(lock: :for_update)
    end
  end

  policies do
    bypass action([:register, :disable, :enable, :by_source_key, :active]) do
      authorize_if always()
    end

    bypass accessing_from(TcgCheap.Catalogue.RetailerListing, :retailer) do
      authorize_if always()
    end

    policy action([:read, :admin_create, :admin_update, :admin_catalogue, :lock_for_update_by_id]) do
      access_type :strict
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
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
