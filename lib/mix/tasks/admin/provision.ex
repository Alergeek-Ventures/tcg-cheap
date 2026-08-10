defmodule Mix.Tasks.Admin.Provision do
  use Mix.Task

  @shortdoc "Provision an administrator from ADMIN_EMAIL and ADMIN_PASSWORD"
  @moduledoc """
  Provisions an administrator without exposing a public registration route.

      mix admin.provision

  Set `ADMIN_EMAIL` and `ADMIN_PASSWORD` through the inherited environment or
  a secret manager. The password is never printed.
  """

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    {email, password} =
      try do
        {TcgCheap.AdminProvisioning.required_env!("ADMIN_EMAIL"),
         TcgCheap.AdminProvisioning.required_env!("ADMIN_PASSWORD")}
      rescue
        error in ArgumentError -> Mix.raise(Exception.message(error))
      end

    case TcgCheap.AdminProvisioning.register(email, password) do
      {:ok, admin} ->
        Mix.shell().info("Provisioned administrator #{admin.email}")

      {:error, _error} ->
        Mix.raise("Administrator provisioning failed")
    end
  end
end
