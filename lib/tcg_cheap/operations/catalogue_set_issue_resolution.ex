defmodule TcgCheap.Operations.CatalogueSetIssueResolution do
  @moduledoc "Durable per-set import issue resolution watermarks."

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Operations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "catalogue_set_issue_resolutions"
    repo TcgCheap.Repo

    identity_index_names unique_catalogue_set_issue_resolution:
                           "catalogue_set_issue_resolutions_identity"

    custom_indexes do
      index [:set_id, :mode]
    end

    check_constraints do
      check_constraint [:set_id], "catalogue_set_issue_resolutions_set_id_invariant",
        check: "btrim(set_id) <> '' AND set_id ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'"

      check_constraint [:mode], "catalogue_set_issue_resolutions_mode_invariant",
        check: "mode IN ('hard','all')"
    end
  end

  actions do
    read :by_set_mode do
      argument :set_id, :string, allow_nil?: false
      argument :mode, :string, allow_nil?: false
      get? true
      filter expr(set_id == ^arg(:set_id) and mode == ^arg(:mode))
    end

    create :record do
      argument :set_id, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 128]
      argument :mode, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 4]
      argument :resolved_at, :utc_datetime_usec, allow_nil?: false
      accept []
      change set_attribute(:set_id, arg(:set_id))
      change set_attribute(:mode, arg(:mode))
      change set_attribute(:resolved_at, arg(:resolved_at))
      upsert? true
      upsert_identity :unique_catalogue_set_issue_resolution
      upsert_fields [:resolved_at]

      upsert_condition expr(
                         is_nil(resolved_at) or
                           resolved_at < upsert_conflict(:resolved_at)
                       )

      return_skipped_upsert? true
      validate match(:set_id, ~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/)
      validate one_of(:mode, ["hard", "all"])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :set_id, :string, allow_nil?: false, public?: false, constraints: [max_length: 128]
    attribute :mode, :string, allow_nil?: false, public?: false, constraints: [max_length: 4]
    attribute :resolved_at, :utc_datetime_usec, allow_nil?: false, public?: false
    create_timestamp :inserted_at, public?: false
    update_timestamp :updated_at, public?: false
  end

  identities do
    identity :unique_catalogue_set_issue_resolution, [:set_id, :mode]
  end
end
