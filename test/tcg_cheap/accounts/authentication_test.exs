defmodule TcgCheap.Accounts.AuthenticationTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Accounts
  alias TcgCheap.Accounts.Admin
  alias TcgCheap.Accounts.Token
  alias TcgCheap.Core

  test "explicit provisioning and password sign-in return a stored token" do
    email = unique_email()

    assert {:ok, admin} =
             Accounts.register_admin(
               %{
                 email: email,
                 password: "correct horse battery staple",
                 password_confirmation: "correct horse battery staple"
               },
               authorize?: false
             )

    assert token = Ash.Resource.get_metadata(admin, :token)
    assert is_binary(token)

    assert {:ok, signed_in} =
             Accounts.sign_in_admin(%{email: email, password: "correct horse battery staple"},
               context: %{private: %{ash_authentication?: true}}
             )

    assert is_binary(Ash.Resource.get_metadata(signed_in, :token))
    assert {:ok, stored_tokens} = Ash.read(Token, authorize?: false)
    assert stored_tokens != []
  end

  test "wrong password fails" do
    email = unique_email()
    provision_admin(email)

    assert {:error, _error} =
             Accounts.sign_in_admin(%{email: email, password: "wrong password"},
               context: %{private: %{ash_authentication?: true}}
             )
  end

  test "duplicate email is rejected" do
    email = unique_email()
    provision_admin(email)

    assert {:error, _error} =
             Accounts.register_admin(
               %{
                 email: email,
                 password: "another secure password",
                 password_confirmation: "another secure password"
               },
               authorize?: false
             )
  end

  test "administrator passwords are bounded before hashing" do
    assert {:error, _error} =
             Accounts.register_admin(
               %{
                 email: unique_email(),
                 password: "too short",
                 password_confirmation: "too short"
               },
               authorize?: false
             )

    oversized = String.duplicate("a", 129)

    assert {:error, _error} =
             Accounts.register_admin(
               %{
                 email: unique_email(),
                 password: oversized,
                 password_confirmation: oversized
               },
               authorize?: false
             )
  end

  test "sealed review actions require an administrator actor" do
    admin = provision_admin(unique_email())

    draft =
      Core.create_sealed_product_draft!(%{
        slug: "authorized-review-#{System.unique_integer([:positive])}",
        name: "Authorized Review Product",
        product_type: "tin",
        officially_distributed: true,
        release_date: Date.utc_today()
      })

    input = %{expected_updated_at: draft.updated_at}

    assert {:error, %Ash.Error.Forbidden{}} = Core.approve_sealed_product(draft, input)
    assert {:ok, approved} = Core.approve_sealed_product(draft, input, actor: admin)
    assert approved.publication_status == "approved"
  end

  test "ordinary admin reads are not anonymously open" do
    provision_admin(unique_email())
    assert {:ok, []} = Ash.read(Admin)
  end

  defp provision_admin(email) do
    Accounts.register_admin!(
      %{
        email: email,
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple"
      },
      authorize?: false
    )
  end

  defp unique_email do
    "admin-#{System.unique_integer([:positive])}@example.test"
  end
end
