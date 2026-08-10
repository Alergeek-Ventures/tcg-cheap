defmodule TcgCheap.Operations.ImportIssue do
  @moduledoc "Retained, secret-safe diagnostics for catalogue imports."

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
        check: "provider_key = 'tcgdex_catalogue'"

      check_constraint [:operation], "import_issues_operation_invariant",
        check: "operation IN ('card_catalogue_sync','card_catalogue_enrichment')"

      check_constraint [:stage], "import_issues_stage_invariant",
        check:
          "stage IN ('catalogue_fetch','catalogue_validation','set_fetch','set_validation','set_import','card_fetch','card_import')"

      check_constraint [:target_type], "import_issues_target_type_invariant",
        check: "target_type IN ('catalogue','set','card')"

      check_constraint [:issue_kind], "import_issues_kind_invariant",
        check: "issue_kind IN ('unmatched','ambiguous','malformed','failed')"

      check_constraint [:issue_code], "import_issues_code_invariant",
        check:
          "issue_code IN ('malformed_response','budget','rate_limit','timeout','transport','provider_response','persistence','configuration','local_input','unknown')"

      check_constraint [:operation, :stage], "import_issues_operation_stage_invariant",
        check:
          "(operation = 'card_catalogue_sync' AND stage IN ('catalogue_fetch','catalogue_validation','set_fetch','set_validation','set_import')) OR (operation = 'card_catalogue_enrichment' AND stage IN ('set_fetch','set_validation','set_import','card_fetch','card_import'))"

      check_constraint [:stage, :target_type, :target_key],
                       "import_issues_stage_target_invariant",
                       check:
                         "(stage IN ('catalogue_fetch','catalogue_validation') AND target_type = 'catalogue' AND target_key = 'tcgdex') OR (stage IN ('set_fetch','set_validation','set_import') AND target_type = 'set') OR (stage IN ('card_fetch','card_import') AND target_type = 'card')"

      check_constraint [:issue_kind, :issue_code], "import_issues_kind_code_invariant",
        check:
          "(issue_kind IN ('unmatched','ambiguous') AND issue_code = 'provider_response') OR (issue_kind = 'malformed' AND issue_code = 'malformed_response') OR (issue_kind = 'failed' AND issue_code IN ('budget','rate_limit','timeout','transport','provider_response','persistence','configuration','local_input','unknown'))"

      check_constraint [:first_seen_at, :last_seen_at], "import_issues_timestamp_invariant",
        check: "last_seen_at >= first_seen_at"
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
      upsert? true
      upsert_identity :unique_import_issue
      upsert_fields [:last_seen_at]
      upsert_condition expr(last_seen_at < upsert_conflict(:last_seen_at))
      return_skipped_upsert? true

      validate one_of(:operation, ["card_catalogue_sync", "card_catalogue_enrichment"])
      validate one_of(:provider_key, ["tcgdex_catalogue"])
      validate match(:target_key, ~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/)

      validate one_of(:stage, [
                 "catalogue_fetch",
                 "catalogue_validation",
                 "set_fetch",
                 "set_validation",
                 "set_import",
                 "card_fetch",
                 "card_import"
               ])

      validate one_of(:target_type, ["catalogue", "set", "card"])
      validate one_of(:issue_kind, ["unmatched", "ambiguous", "malformed", "failed"])

      validate one_of(:issue_code, [
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

      validate TcgCheap.Operations.Validations.ImportIssue
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
