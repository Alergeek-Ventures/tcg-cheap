defmodule TcgCheap.Operations.ImportIssue do
  @moduledoc "Retained, secret-safe diagnostics for catalogue and sealed-retailer imports."

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Operations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "import_issues"
    repo TcgCheap.Repo

    custom_indexes do
      index [:last_seen_at, :id]
    end

    check_constraints do
      check_constraint [:provider_key, :target_key], "import_issues_text_invariant",
        check: "btrim(provider_key) <> '' AND btrim(target_key) <> ''"

      check_constraint [:provider_key], "import_issues_provider_invariant",
        check:
          "provider_key = 'tcgdex_catalogue' OR provider_key ~ '^sealed_retailer:[A-Za-z0-9][A-Za-z0-9._-]{0,143}$'"

      check_constraint [:provider_key, :operation], "import_issues_provider_operation_invariant",
        check:
          "(provider_key = 'tcgdex_catalogue' AND operation IN ('card_catalogue_sync','card_catalogue_enrichment')) OR (provider_key ~ '^sealed_retailer:[A-Za-z0-9][A-Za-z0-9._-]{0,143}$' AND operation = 'sealed_retailer_refresh')"

      check_constraint [:operation], "import_issues_operation_invariant",
        check:
          "operation IN ('card_catalogue_sync','card_catalogue_enrichment','sealed_retailer_refresh')"

      check_constraint [:stage], "import_issues_stage_invariant",
        check:
          "stage IN ('catalogue_fetch','catalogue_validation','set_fetch','set_validation','set_import','card_fetch','card_import','retailer_fetch','listing_validation','listing_import')"

      check_constraint [:target_type], "import_issues_target_type_invariant",
        check: "target_type IN ('catalogue','set','card','retailer')"

      check_constraint [:issue_kind], "import_issues_kind_invariant",
        check: "issue_kind IN ('unmatched','ambiguous','partial','malformed','failed')"

      check_constraint [:issue_code], "import_issues_code_invariant",
        check:
          "issue_code IN ('partial_coverage','malformed_response','budget','rate_limit','timeout','transport','provider_response','persistence','configuration','local_input','unknown')"

      check_constraint [:operation, :stage], "import_issues_operation_stage_invariant",
        check:
          "(operation = 'card_catalogue_sync' AND stage IN ('catalogue_fetch','catalogue_validation','set_fetch','set_validation','set_import')) OR (operation = 'card_catalogue_enrichment' AND stage IN ('set_fetch','set_validation','set_import','card_fetch','card_import')) OR (operation = 'sealed_retailer_refresh' AND stage IN ('retailer_fetch','listing_validation','listing_import'))"

      check_constraint [:stage, :target_type, :target_key],
                       "import_issues_stage_target_invariant",
                       check:
                         "(stage IN ('catalogue_fetch','catalogue_validation') AND target_type = 'catalogue' AND target_key = 'tcgdex') OR (stage IN ('set_fetch','set_validation','set_import') AND target_type = 'set' AND octet_length(target_key) BETWEEN 1 AND 128 AND target_key ~ '^[A-Za-z0-9][A-Za-z0-9._-]*$') OR (stage IN ('card_fetch','card_import') AND target_type = 'card' AND octet_length(target_key) BETWEEN 1 AND 128 AND target_key ~ '^[A-Za-z0-9]([A-Za-z0-9._!-]|%[0-9A-Fa-f]{2})*$') OR (stage IN ('retailer_fetch','listing_validation','listing_import') AND target_type = 'retailer' AND target_key ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' AND target_key = lower(target_key))"

      check_constraint [:issue_kind, :issue_code], "import_issues_kind_code_invariant",
        check:
          "(issue_kind IN ('unmatched','ambiguous') AND issue_code = 'provider_response') OR (issue_kind = 'partial' AND issue_code = 'partial_coverage') OR (issue_kind = 'malformed' AND issue_code = 'malformed_response') OR (issue_kind = 'failed' AND issue_code IN ('budget','rate_limit','timeout','transport','provider_response','persistence','configuration','local_input','unknown'))"

      check_constraint [:first_seen_at, :last_seen_at], "import_issues_timestamp_invariant",
        check: "last_seen_at >= first_seen_at"

      check_constraint [:resolved_at, :last_seen_at], "import_issues_resolution_invariant",
        check: "resolved_at IS NULL OR resolved_at >= last_seen_at"
    end
  end

  actions do
    defaults [:read]

    read :admin_catalogue do
      prepare build(sort: [last_seen_at: :desc, id: :desc])
    end

    create :record do
      argument :provider_key, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 160]

      argument :operation, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 80]

      argument :stage, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 80]

      argument :target_type, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 40]

      argument :target_key, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 240]

      argument :issue_kind, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 40]

      argument :issue_code, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 80]

      argument :occurred_at, :utc_datetime_usec, allow_nil?: false
      argument :resolved_at, :utc_datetime_usec, allow_nil?: true
      accept []
      change set_attribute(:provider_key, arg(:provider_key))
      change set_attribute(:operation, arg(:operation))
      change set_attribute(:stage, arg(:stage))
      change set_attribute(:target_type, arg(:target_type))
      change set_attribute(:target_key, arg(:target_key))
      change set_attribute(:issue_kind, arg(:issue_kind))
      change set_attribute(:issue_code, arg(:issue_code))
      change set_attribute(:first_seen_at, arg(:occurred_at))
      change set_attribute(:last_seen_at, arg(:occurred_at))
      change set_attribute(:resolved_at, arg(:resolved_at))
      upsert? true
      upsert_identity :unique_import_issue
      upsert_fields [:last_seen_at, :resolved_at]

      upsert_condition expr(
                         (last_seen_at < upsert_conflict(:last_seen_at) or
                            (last_seen_at == upsert_conflict(:last_seen_at) and
                               is_nil(upsert_conflict(:resolved_at)))) and
                           (is_nil(resolved_at) or
                              (not is_nil(upsert_conflict(:resolved_at)) and
                                 resolved_at < upsert_conflict(:resolved_at)) or
                              (is_nil(upsert_conflict(:resolved_at)) and
                                 resolved_at < upsert_conflict(:last_seen_at)))
                       )

      return_skipped_upsert? true

      validate one_of(:operation, [
                 "card_catalogue_sync",
                 "card_catalogue_enrichment",
                 "sealed_retailer_refresh"
               ])

      validate match(
                 :provider_key,
                 ~r/\A(tcgdex_catalogue|sealed_retailer:[A-Za-z0-9][A-Za-z0-9._-]{0,143})\z/
               )

      validate one_of(:stage, [
                 "catalogue_fetch",
                 "catalogue_validation",
                 "set_fetch",
                 "set_validation",
                 "set_import",
                 "card_fetch",
                 "card_import",
                 "retailer_fetch",
                 "listing_validation",
                 "listing_import"
               ])

      validate one_of(:target_type, ["catalogue", "set", "card", "retailer"])
      validate one_of(:issue_kind, ["unmatched", "ambiguous", "partial", "malformed", "failed"])

      validate one_of(:issue_code, [
                 "partial_coverage",
                 "malformed_response",
                 "budget",
                 "rate_limit",
                 "timeout",
                 "transport",
                 "provider_response",
                 "persistence",
                 "configuration",
                 "local_input",
                 "unknown"
               ])

      validate compare(:resolved_at, greater_than_or_equal_to: ref(:last_seen_at))
      validate TcgCheap.Operations.Validations.ImportIssue
    end

    read :unresolved_catalogue_sets do
      filter expr(
               provider_key == "tcgdex_catalogue" and operation == "card_catalogue_sync" and
                 target_type == "set" and issue_kind in ["malformed", "failed"] and
                 is_nil(resolved_at)
             )

      prepare build(
                distinct: [:target_key],
                distinct_sort: [target_key: :asc, id: :asc],
                sort: [target_key: :asc, id: :asc],
                limit: 1001
              )
    end

    read :unresolved_catalogue_set do
      argument :target_key, :string, allow_nil?: false
      get? false

      filter expr(
               provider_key == "tcgdex_catalogue" and operation == "card_catalogue_sync" and
                 target_type == "set" and issue_kind in ["partial", "malformed", "failed"] and
                 is_nil(resolved_at) and target_key == ^arg(:target_key)
             )

      prepare build(sort: [last_seen_at: :desc, id: :desc], limit: 1001)
    end

    read :unresolved_hard_catalogue_set do
      argument :target_key, :string, allow_nil?: false
      get? false

      filter expr(
               provider_key == "tcgdex_catalogue" and operation == "card_catalogue_sync" and
                 target_type == "set" and issue_kind in ["malformed", "failed"] and
                 is_nil(resolved_at) and target_key == ^arg(:target_key)
             )

      prepare build(sort: [last_seen_at: :desc, id: :desc], limit: 1001)
    end

    update :resolve do
      argument :resolved_at, :utc_datetime_usec, allow_nil?: false
      accept []
      change set_attribute(:resolved_at, arg(:resolved_at))
      validate compare(:resolved_at, greater_than_or_equal_to: ref(:last_seen_at))
    end
  end

  policies do
    policy action_type(:read) do
      access_type :strict
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider_key, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 160]

    attribute :operation, :string, allow_nil?: false, public?: true, constraints: [max_length: 80]
    attribute :stage, :string, allow_nil?: false, public?: true, constraints: [max_length: 80]

    attribute :target_type, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 40]

    attribute :target_key, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 240]

    attribute :issue_kind, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 40]

    attribute :issue_code, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 80]

    attribute :first_seen_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :last_seen_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :resolved_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  identities do
    identity :unique_import_issue, [
      :provider_key,
      :operation,
      :stage,
      :target_type,
      :target_key,
      :issue_kind,
      :issue_code
    ]
  end
end
