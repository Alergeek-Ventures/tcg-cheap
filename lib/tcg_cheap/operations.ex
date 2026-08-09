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
  end
end
