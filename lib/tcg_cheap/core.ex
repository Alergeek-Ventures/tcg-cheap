defmodule TcgCheap.Core do
  @moduledoc "The daily NBP EUR/PLN exchange rate used by the buying guide."

  use Ash.Domain,
    otp_app: :tcg_cheap

  resources do
    resource TcgCheap.Pricing.ExchangeRate do
      define :record_exchange_rate, action: :record
      define :get_latest_exchange_rate, action: :latest, args: [:as_of], not_found_error?: false

      define :list_exchange_rate_history,
        action: :history,
        args: [:as_of, {:optional, :limit}]
    end
  end
end
