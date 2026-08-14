defmodule TcgCheap.Operations.CatalogueSyncRun do
  @moduledoc "Durable progress for the TCGdex catalogue synchronisation."

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Operations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "catalogue_sync_runs"
    repo TcgCheap.Repo

    custom_indexes do
      index [:provider_key], unique: true, where: "status = 'running'"
    end

    custom_statements do
      statement :canonical_catalogue_set_ids_function do
        up ~S"""
        CREATE FUNCTION tcg_cheap_validate_catalogue_set_ids()
        RETURNS trigger
        LANGUAGE plpgsql
        AS $$
        BEGIN
          IF NEW.set_ids <> ARRAY(
            SELECT set_id FROM unnest(NEW.set_ids) AS set_id ORDER BY set_id
          ) OR cardinality(NEW.set_ids) <> cardinality(ARRAY(
            SELECT DISTINCT set_id FROM unnest(NEW.set_ids) AS set_id
          )) THEN
            RAISE EXCEPTION USING
              ERRCODE = '23514',
              CONSTRAINT = 'catalogue_sync_runs_set_ids_canonical_invariant',
              MESSAGE = 'set_ids must be sorted and unique';
          END IF;

          RETURN NEW;
        END;
        $$;
        """

        down "DROP FUNCTION tcg_cheap_validate_catalogue_set_ids();"
      end

      statement :canonical_catalogue_set_ids_trigger do
        up ~S"""
        CREATE TRIGGER catalogue_sync_runs_set_ids_canonical_trigger
        BEFORE INSERT OR UPDATE OF set_ids ON catalogue_sync_runs
        FOR EACH ROW EXECUTE FUNCTION tcg_cheap_validate_catalogue_set_ids();
        """

        down "DROP TRIGGER catalogue_sync_runs_set_ids_canonical_trigger ON catalogue_sync_runs;"
      end
    end

    check_constraints do
      check_constraint [:provider_key], "catalogue_sync_runs_provider_invariant",
        check: "provider_key = 'tcgdex_catalogue'"

      check_constraint [:set_ids], "catalogue_sync_runs_set_ids_invariant",
        check:
          "cardinality(set_ids) BETWEEN 1 AND 1000 AND array_position(set_ids, NULL) IS NULL AND array_to_string(set_ids, ',') ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}(,[A-Za-z0-9][A-Za-z0-9._-]{0,127})*$'"

      check_constraint [:next_index, :set_ids], "catalogue_sync_runs_index_invariant",
        check: "next_index >= 0 AND next_index <= cardinality(set_ids)"

      check_constraint [:synced_sets, :partial_sets, :failed_sets, :excluded_sets, :next_index],
                       "catalogue_sync_runs_counter_invariant",
                       check:
                         "synced_sets >= 0 AND partial_sets >= 0 AND failed_sets >= 0 AND excluded_sets >= 0 AND synced_sets + partial_sets + failed_sets + excluded_sets = next_index"

      check_constraint [:status, :next_index, :set_ids, :completed_at],
                       "catalogue_sync_runs_lifecycle_invariant",
                       check:
                         "(status = 'running' AND next_index < cardinality(set_ids) AND completed_at IS NULL) OR (status = 'completed' AND next_index = cardinality(set_ids) AND completed_at IS NOT NULL)"

      check_constraint [:scope], "catalogue_sync_runs_scope_invariant",
        check: "scope IN ('all_sets','failed_sets')"

      check_constraint [:status], "catalogue_sync_runs_status_invariant",
        check: "status IN ('running','completed')"

      check_constraint [:started_at, :completed_at], "catalogue_sync_runs_timestamp_invariant",
        check: "completed_at IS NULL OR completed_at >= started_at"
    end
  end

  actions do
    read :read do
      primary? true
    end

    read :active do
      get? true
      filter expr(provider_key == "tcgdex_catalogue" and status == "running")
    end

    create :start do
      argument :set_ids, {:array, :string},
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 1000, nil_items?: false]

      argument :started_at, :utc_datetime_usec, allow_nil?: false
      accept []
      change {TcgCheap.Operations.Changes.StartCatalogueSyncRun, []}
    end

    create :start_failed do
      argument :set_ids, {:array, :string},
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 1000, nil_items?: false]

      argument :started_at, :utc_datetime_usec, allow_nil?: false
      accept []
      change {TcgCheap.Operations.Changes.StartFailedCatalogueSyncRun, []}
    end

    update :advance do
      argument :expected_index, :integer, allow_nil?: false, constraints: [min: 0]
      argument :set_id, :string, allow_nil?: false
      argument :outcome, :string, allow_nil?: false
      argument :completed_at, :utc_datetime_usec
      accept []
      require_atomic? false
      change {TcgCheap.Operations.Changes.AdvanceCatalogueSyncRun, []}
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :provider_key, :string, allow_nil?: false, public?: true
    attribute :set_ids, {:array, :string}, allow_nil?: false, public?: true
    attribute :next_index, :integer, allow_nil?: false, default: 0, public?: true
    attribute :synced_sets, :integer, allow_nil?: false, default: 0, public?: true
    attribute :failed_sets, :integer, allow_nil?: false, default: 0, public?: true
    attribute :partial_sets, :integer, allow_nil?: false, default: 0, public?: true
    attribute :excluded_sets, :integer, allow_nil?: false, default: 0, public?: true
    attribute :scope, :string, allow_nil?: false, default: "all_sets", public?: true
    attribute :status, :string, allow_nil?: false, default: "running", public?: true
    attribute :started_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :completed_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end
end
