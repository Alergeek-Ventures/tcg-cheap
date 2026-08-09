defmodule TcgCheap.Operations.DataProvider do
  @moduledoc "Configured external acquisition provider and its admission limits."

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Operations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "acquisition_data_providers"
    repo TcgCheap.Repo

    check_constraints do
      check_constraint [:provider_key, :display_name],
                       "acquisition_data_providers_identity_invariant",
                       check: "btrim(provider_key) <> '' AND btrim(display_name) <> ''"

      check_constraint [:status], "acquisition_data_providers_status_invariant",
        check: "status IN ('active', 'disabled')"

      check_constraint [:estimated_cost_per_request], "acquisition_data_providers_cost_invariant",
        check: "estimated_cost_per_request >= 0 AND estimated_cost_per_request < 1000000000"

      check_constraint [:hourly_request_limit, :daily_request_limit, :monthly_request_limit],
                       "acquisition_data_providers_request_limits_invariant",
                       check:
                         "hourly_request_limit > 0 AND daily_request_limit > 0 AND monthly_request_limit > 0"

      check_constraint [:hourly_request_limit, :daily_request_limit, :monthly_request_limit],
                       "acquisition_data_providers_request_limit_order_invariant",
                       check:
                         "hourly_request_limit <= daily_request_limit AND daily_request_limit <= monthly_request_limit"

      check_constraint [:monthly_spend_limit], "acquisition_data_providers_spend_limit_invariant",
        check: "monthly_spend_limit >= 0 AND monthly_spend_limit <= 50"
    end
  end

  actions do
    defaults [:read]

    create :register do
      argument :provider_key, :string, allow_nil?: false
      argument :display_name, :string, allow_nil?: false
      argument :estimated_cost_per_request, :decimal, allow_nil?: false
      argument :hourly_request_limit, :integer, allow_nil?: false
      argument :daily_request_limit, :integer, allow_nil?: false
      argument :monthly_request_limit, :integer, allow_nil?: false
      argument :monthly_spend_limit, :decimal, allow_nil?: false
      accept []
      change set_attribute(:provider_key, arg(:provider_key))
      change set_attribute(:display_name, arg(:display_name))
      change set_attribute(:estimated_cost_per_request, arg(:estimated_cost_per_request))
      change set_attribute(:hourly_request_limit, arg(:hourly_request_limit))
      change set_attribute(:daily_request_limit, arg(:daily_request_limit))
      change set_attribute(:monthly_request_limit, arg(:monthly_request_limit))
      change set_attribute(:monthly_spend_limit, arg(:monthly_spend_limit))
      upsert? true
      upsert_identity :unique_provider_key

      upsert_fields [
        :display_name,
        :estimated_cost_per_request,
        :hourly_request_limit,
        :daily_request_limit,
        :monthly_request_limit,
        :monthly_spend_limit
      ]

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

    read :by_key do
      argument :provider_key, :string, allow_nil?: false
      get? true
      filter expr(provider_key == ^arg(:provider_key))
    end
  end

  validations do
    validate compare(:estimated_cost_per_request, greater_than_or_equal_to: 0)
    validate compare(:monthly_spend_limit, greater_than_or_equal_to: 0)
    validate compare(:monthly_spend_limit, less_than_or_equal_to: 50)
    validate compare(:hourly_request_limit, greater_than: 0)
    validate compare(:hourly_request_limit, less_than_or_equal_to: :daily_request_limit)
    validate compare(:daily_request_limit, greater_than: 0)
    validate compare(:daily_request_limit, less_than_or_equal_to: :monthly_request_limit)
    validate compare(:monthly_request_limit, greater_than: 0)
  end

  attributes do
    uuid_primary_key :id

    attribute :provider_key, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 160]

    attribute :display_name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 240]

    attribute :status, :string, allow_nil?: false, default: "active", public?: true
    attribute :estimated_cost_per_request, :decimal, allow_nil?: false, public?: true
    attribute :hourly_request_limit, :integer, allow_nil?: false, public?: true
    attribute :daily_request_limit, :integer, allow_nil?: false, public?: true
    attribute :monthly_request_limit, :integer, allow_nil?: false, public?: true
    attribute :monthly_spend_limit, :decimal, allow_nil?: false, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_provider_key, [:provider_key]
  end
end
