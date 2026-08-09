defmodule TcgCheap.Catalogue.SealedProduct do
  @moduledoc "Source-neutral canonical catalogue entry for an officially distributed sealed product."
  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sealed_products"
    repo TcgCheap.Repo

    check_constraints do
      check_constraint [:slug, :name], "sealed_products_identity_invariant",
        check:
          "slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND btrim(name) <> '' AND btrim(search_name) <> ''",
        message: "slug and name must not be blank"

      check_constraint [:product_type], "sealed_products_product_type_invariant",
        check:
          "product_type IN ('booster_pack', 'sleeved_booster', 'booster_bundle', 'booster_box', 'elite_trainer_box', 'tin', 'collection_box', 'deck', 'trainer_toolkit', 'other')"

      check_constraint [:publication_status, :distribution_status],
                       "sealed_products_status_invariant",
                       check:
                         "publication_status IN ('draft', 'approved', 'archived') AND distribution_status IN ('current', 'discontinued')"

      check_constraint [:msrp_pln, :msrp_currency, :msrp_source],
                       "sealed_products_msrp_invariant",
                       check:
                         "((msrp_pln IS NULL AND msrp_currency = 'PLN' AND msrp_source IS NULL) OR (msrp_pln IS NOT NULL AND msrp_pln > 0 AND msrp_currency = 'PLN' AND msrp_source IS NOT NULL AND btrim(msrp_source) <> ''))",
                       message: "MSRP must be positive with a nonblank PLN source, or absent"

      check_constraint [:market, :language, :officially_distributed],
                       "sealed_products_distribution_invariant",
                       check: "market = 'PL' AND language = 'en'"

      check_constraint [:publication_status, :approved_at, :archived_at],
                       "sealed_products_review_timestamps_invariant",
                       check:
                         "(publication_status = 'draft' AND approved_at IS NULL AND archived_at IS NULL) OR (publication_status = 'approved' AND approved_at IS NOT NULL AND archived_at IS NULL) OR (publication_status = 'archived' AND archived_at IS NOT NULL)"

      check_constraint [:publication_status, :officially_distributed, :release_date],
                       "sealed_products_approved_completeness_invariant",
                       check:
                         "publication_status <> 'approved' OR (officially_distributed = TRUE AND release_date IS NOT NULL)"

      check_constraint [:source, :source_id], "sealed_products_source_identity_invariant",
        check:
          "(source IS NULL AND source_id IS NULL) OR (source IS NOT NULL AND source_id IS NOT NULL AND btrim(source) <> '' AND btrim(source_id) <> '')"

      check_constraint [:msrp_pln, :msrp_currency, :msrp_source],
                       "sealed_products_msrp_finite_invariant",
                       check:
                         "msrp_pln IS NULL OR (msrp_pln <> 'NaN'::numeric AND msrp_pln <> 'Infinity'::numeric AND msrp_pln <> '-Infinity'::numeric)"
    end
  end

  actions do
    defaults [:read]

    create :create_draft do
      accept [
        :slug,
        :name,
        :product_type,
        :series_name,
        :set_name,
        :release_date,
        :msrp_pln,
        :msrp_source,
        :msrp_source_url,
        :image_url,
        :officially_distributed,
        :source,
        :source_id,
        :source_payload,
        :source_updated_at,
        :last_synced_at
      ]

      change TcgCheap.Catalogue.Changes.SetSealedProductSearchText
      validate TcgCheap.Catalogue.Validations.SealedProductIdentity
      validate TcgCheap.Catalogue.Validations.SourceIdentity
      validate TcgCheap.Catalogue.Validations.SealedProductFields
    end

    create :import_draft do
      accept [
        :slug,
        :name,
        :product_type,
        :series_name,
        :set_name,
        :release_date,
        :msrp_pln,
        :msrp_source,
        :msrp_source_url,
        :image_url,
        :officially_distributed,
        :source,
        :source_id,
        :source_payload,
        :source_updated_at,
        :last_synced_at
      ]

      change TcgCheap.Catalogue.Changes.SetSealedProductSearchText
      validate TcgCheap.Catalogue.Validations.SealedProductIdentity
      validate {TcgCheap.Catalogue.Validations.SourceIdentity, required?: true}
      validate TcgCheap.Catalogue.Validations.SealedProductFields
      upsert? true
      upsert_identity :unique_source_id

      upsert_fields [
        :slug,
        :name,
        :search_name,
        :product_type,
        :series_name,
        :set_name,
        :release_date,
        :msrp_pln,
        :msrp_source,
        :msrp_source_url,
        :image_url,
        :officially_distributed,
        :source,
        :source_id,
        :source_payload,
        :source_updated_at,
        :last_synced_at
      ]

      upsert_condition expr(
                         publication_status == "draft" and
                           publication_status == upsert_conflict(:publication_status)
                       )

      return_skipped_upsert? true
    end

    update :revise_draft do
      argument :expected_updated_at, :utc_datetime_usec, allow_nil?: false

      accept [
        :slug,
        :name,
        :product_type,
        :series_name,
        :set_name,
        :release_date,
        :msrp_pln,
        :msrp_source,
        :msrp_source_url,
        :image_url,
        :officially_distributed,
        :source,
        :source_id,
        :source_payload,
        :source_updated_at,
        :last_synced_at
      ]

      # Transaction-local row lock plus Elixir search-text normalization require a non-atomic action.
      require_atomic? false
      validate TcgCheap.Catalogue.Validations.SealedProductIdentity
      validate TcgCheap.Catalogue.Validations.SourceIdentity
      validate TcgCheap.Catalogue.Validations.SealedProductFields
      change TcgCheap.Catalogue.Changes.SetSealedProductSearchText

      change {TcgCheap.Catalogue.Changes.LockAndValidateReview,
              resource: __MODULE__,
              lock_action: :lock_for_update_by_id,
              status_attribute: :publication_status,
              expected_status: "draft",
              version_argument: :expected_updated_at}
    end

    update :approve do
      argument :expected_updated_at, :utc_datetime_usec, allow_nil?: false
      accept []

      # Transaction-local row lock, latest completeness check, and wall-clock release date require a non-atomic action.
      require_atomic? false
      change set_attribute(:publication_status, "approved")
      change atomic_update(:approved_at, expr(now()))

      change {TcgCheap.Catalogue.Changes.LockAndValidateReview,
              resource: __MODULE__,
              lock_action: :lock_for_update_by_id,
              status_attribute: :publication_status,
              expected_status: "draft",
              version_argument: :expected_updated_at,
              mode: :product_approval}
    end

    update :archive do
      argument :expected_updated_at, :utc_datetime_usec, allow_nil?: false
      accept []

      # Review rows may be archived while draft or after publication; lock and version both states.
      require_atomic? false
      change set_attribute(:publication_status, "archived")
      change atomic_update(:archived_at, expr(now()))

      change {TcgCheap.Catalogue.Changes.LockAndValidateReview,
              resource: __MODULE__,
              lock_action: :lock_for_update_by_id,
              status_attribute: :publication_status,
              expected_status: ["draft", "approved"],
              version_argument: :expected_updated_at}
    end

    update :mark_discontinued do
      accept []
      change set_attribute(:distribution_status, "discontinued")
    end

    read :by_slug do
      argument :slug, :string, allow_nil?: false
      get? true
      filter expr(slug == ^arg(:slug))
    end

    read :public_by_slug do
      argument :slug, :string, allow_nil?: false
      get? true

      filter expr(
               slug == ^arg(:slug) and publication_status == "approved" and
                 officially_distributed == true and market == "PL" and language == "en" and
                 release_date <= today() and
                 distribution_status in ["current", "discontinued"]
             )
    end

    read :public_by_id do
      argument :id, :uuid, allow_nil?: false
      get? true

      filter expr(
               id == ^arg(:id) and publication_status == "approved" and
                 officially_distributed == true and market == "PL" and language == "en" and
                 release_date <= today() and distribution_status in ["current", "discontinued"]
             )
    end

    read :public_catalogue do
      filter expr(
               publication_status == "approved" and release_date <= today() and
                 officially_distributed == true and market == "PL" and language == "en" and
                 distribution_status in ["current", "discontinued"]
             )

      prepare build(sort: [name: :asc, slug: :asc])
    end

    read :draft_review_queue do
      filter expr(publication_status == "draft")
      prepare build(sort: [inserted_at: :asc, slug: :asc])
    end

    read :draft_review_by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id) and publication_status == "draft")
    end

    read :lock_for_update_by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
      prepare build(lock: :for_update)
    end
  end

  policies do
    policy action([
             :revise_draft,
             :approve,
             :archive,
             :mark_discontinued,
             :draft_review_queue,
             :draft_review_by_id
           ]) do
      authorize_if TcgCheap.Accounts.Checks.Admin
    end

    policy always() do
      authorize_if always()
    end
  end

  validations do
    validate one_of(:publication_status, ~w(draft approved archived))
    validate one_of(:distribution_status, ~w(current discontinued))
  end

  attributes do
    uuid_primary_key :id
    attribute :slug, :string, allow_nil?: false, public?: true, constraints: [max_length: 120]
    attribute :name, :string, allow_nil?: false, public?: true, constraints: [max_length: 240]
    attribute :search_name, :string, allow_nil?: false, default: "", public?: false
    attribute :product_type, :string, allow_nil?: false, public?: true
    attribute :series_name, :string, public?: true
    attribute :set_name, :string, public?: true
    attribute :release_date, :date, public?: true
    attribute :msrp_pln, :decimal, public?: true
    attribute :msrp_currency, :string, allow_nil?: false, default: "PLN", public?: true
    attribute :msrp_source, :string, public?: true
    attribute :msrp_source_url, :string, public?: true, constraints: [max_length: 2_000]
    attribute :image_url, :string, public?: true, constraints: [max_length: 2_000]
    attribute :market, :string, allow_nil?: false, default: "PL", public?: true
    attribute :language, :string, allow_nil?: false, default: "en", public?: true
    attribute :officially_distributed, :boolean, allow_nil?: false, default: false, public?: true
    attribute :publication_status, :string, allow_nil?: false, default: "draft", public?: true
    attribute :distribution_status, :string, allow_nil?: false, default: "current", public?: true
    attribute :source, :string, public?: false
    attribute :source_id, :string, public?: false
    attribute :source_payload, :map, public?: false
    attribute :source_updated_at, :utc_datetime_usec, public?: false
    attribute :last_synced_at, :utc_datetime_usec, public?: false
    attribute :approved_at, :utc_datetime_usec, public?: true
    attribute :archived_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :aliases, TcgCheap.Catalogue.SealedProductAlias
  end

  identities do
    identity :unique_slug, [:slug]
    identity :unique_source_id, [:source, :source_id]
  end
end
