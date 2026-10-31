defmodule TcgCheap.Release do
  @moduledoc "Operations intended to be run by the compiled OTP release."

  @app :tcg_cheap

  def provision_admin do
    email = TcgCheap.AdminProvisioning.required_env!("ADMIN_EMAIL")
    password = TcgCheap.AdminProvisioning.required_env!("ADMIN_PASSWORD")

    load_app()

    {:ok, result, _apps} =
      Ecto.Migrator.with_repo(TcgCheap.Repo, fn _repo ->
        TcgCheap.AdminProvisioning.register(email, password)
      end)

    case result do
      {:ok, admin} ->
        IO.puts("Provisioned administrator #{admin.email}")
        :ok

      {:error, _error} ->
        raise "Administrator provisioning failed"
    end
  end

  defp load_app do
    Application.load(@app)
  end
end
