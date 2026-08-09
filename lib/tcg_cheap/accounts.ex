defmodule TcgCheap.Accounts do
  @moduledoc "Administrator authentication and token resources."

  use Ash.Domain,
    otp_app: :tcg_cheap

  resources do
    resource TcgCheap.Accounts.Admin do
      define :register_admin, action: :register_with_password
      define :sign_in_admin, action: :sign_in_with_password
      define :get_admin_by_subject, action: :get_by_subject, args: [:subject]
    end

    resource TcgCheap.Accounts.Token
  end
end
