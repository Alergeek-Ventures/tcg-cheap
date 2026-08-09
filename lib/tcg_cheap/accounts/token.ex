defmodule TcgCheap.Accounts.Token do
  @moduledoc "Persisted token metadata used by AshAuthentication."

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TcgCheap.Accounts,
    extensions: [AshAuthentication.TokenResource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "admin_auth_tokens"
    repo TcgCheap.Repo
  end

  actions do
    defaults [:read]
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end
end
