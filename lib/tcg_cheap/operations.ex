defmodule TcgCheap.Operations do
  @moduledoc "Admission-control resources and actions for external acquisitions."

  use Ash.Domain, otp_app: :tcg_cheap

  resources do
    resource TcgCheap.Operations.DataProvider do
      define :register_provider,
        action: :register,
        args: [
          :provider_key,
          :display_name,
          :estimated_cost_per_request,
          :hourly_request_limit,
          :daily_request_limit,
          :monthly_request_limit,
          :monthly_spend_limit
        ]

      define :enable_provider, action: :enable, args: [:expected_updated_at]
      define :disable_provider, action: :disable, args: [:expected_updated_at]
      define :list_providers, action: :admin_list, args: [:provider_keys]
      define :get_provider_by_key, action: :by_key, args: [:provider_key], not_found_error?: false
    end

    resource TcgCheap.Operations.BudgetUsage do
      define :list_budget_usage, action: :read

      define :list_current_budget_windows,
        action: :current_windows,
        args: [:provider_ids, :hour_started_at, :day_started_at, :month_started_at]
    end

    resource TcgCheap.Operations.AcquisitionRun do
      define :start_acquisition_run,
        action: :start,
        args: [
          :attempt_key,
          :provider_key,
          :operation,
          :target_key,
          :worker,
          :queue,
          :job_id,
          :attempt,
          :max_attempts,
          :started_at
        ]

      define :finish_acquisition_run,
        action: :finish,
        args: [:status, :failure_category, :request_count]

      define :reconcile_stranded_acquisition_run,
        action: :reconcile_stranded,
        args: [:expected_cutoff, :finished_at]

      define :list_recent_acquisition_runs, action: :recent, args: [:provider_keys, :limit]
    end

    resource TcgCheap.Operations.SourceHealth do
      define :list_source_health, action: :by_providers, args: [:provider_keys]
    end

    resource TcgCheap.Operations.ImportIssue do
      define :record_import_issue,
        action: :record,
        args: [
          :provider_key,
          :operation,
          :stage,
          :target_type,
          :target_key,
          :issue_kind,
          :issue_code,
          :occurred_at
        ]

      define :list_admin_import_issues, action: :admin_catalogue
    end

    resource TcgCheap.Operations.CatalogueSyncRun do
      define :start_catalogue_sync_run, action: :start, args: [:set_ids, :started_at]

      define :get_active_catalogue_sync_run,
        action: :active,
        not_found_error?: false

      define :advance_catalogue_sync_run,
        action: :advance,
        args: [:expected_index, :set_id, :outcome, :completed_at]
    end
  end
end
