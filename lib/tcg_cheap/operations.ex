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

      define :enable_provider, action: :enable
      define :disable_provider, action: :disable
      define :get_provider_by_key, action: :by_key, args: [:provider_key], not_found_error?: false
    end

    resource TcgCheap.Operations.BudgetUsage do
      define :list_budget_usage, action: :read
    end
  end
end
