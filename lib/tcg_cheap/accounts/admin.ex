defmodule TcgCheap.Accounts.Admin do
  @moduledoc "The administrator identity used for all authenticated operations."

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TcgCheap.Accounts,
    extensions: [AshAuthentication],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "admins"
    repo TcgCheap.Repo
  end

  authentication do
    strategies do
      password :password do
        identity_field :email
        hash_provider AshAuthentication.Argon2Provider
        confirmation_required? false
      end
    end

    tokens do
      enabled? true
      token_resource TcgCheap.Accounts.Token
      store_all_tokens? true
      require_token_presence_for_authentication? true

      signing_secret fn _resource, _opts ->
        token_signing_secret()
      end
    end
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get an administrator by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :sign_in_with_password do
      description "Sign in an administrator with an email address and password"
      get? true

      argument :email, :ci_string do
        allow_nil? false
        constraints max_length: 320
      end

      argument :password, :string do
        allow_nil? false
        constraints max_length: 128
        sensitive? true
      end

      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the administrator"
        allow_nil? false
      end
    end

    create :register_with_password do
      description "Provision an administrator with an email address and password"

      argument :email, :ci_string do
        allow_nil? false
        constraints max_length: 320
      end

      argument :password, :string do
        allow_nil? false
        constraints min_length: 14, max_length: 128
        sensitive? true
      end

      argument :password_confirmation, :string do
        allow_nil? false
        constraints max_length: 128
        sensitive? true
      end

      change set_attribute(:email, arg(:email))
      change AshAuthentication.Strategy.Password.HashPasswordChange
      change AshAuthentication.GenerateTokenChange
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the administrator"
        allow_nil? false
      end
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      constraints max_length: 320
      public? true
    end

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end
  end

  identities do
    identity :unique_email, [:email]
  end

  defp token_signing_secret do
    case Application.fetch_env!(:tcg_cheap, :token_signing_secret) do
      :endpoint_secret_key_base ->
        secret =
          :tcg_cheap
          |> Application.fetch_env!(TcgCheapWeb.Endpoint)
          |> Keyword.fetch!(:secret_key_base)

        {:ok, secret}

      secret when is_binary(secret) ->
        {:ok, secret}
    end
  end
end
