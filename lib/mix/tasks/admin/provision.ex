defmodule Mix.Tasks.Admin.Provision do
  use Mix.Task

  @shortdoc "Provision an administrator from ADMIN_EMAIL and ADMIN_PASSWORD"
  @moduledoc """
  Provisions an administrator without exposing a public registration route.

      ADMIN_EMAIL=admin@example.com ADMIN_PASSWORD='use-a-secret-manager' mix admin.provision

  The password is read only from the environment and is never printed.
  """

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    email = required_env!("ADMIN_EMAIL")
    password = required_env!("ADMIN_PASSWORD")

    case TcgCheap.Accounts.register_admin(
           %{email: email, password: password, password_confirmation: password},
           authorize?: false
         ) do
      {:ok, admin} ->
        Mix.shell().info("Provisioned administrator #{admin.email}")

      {:error, error} ->
        Mix.raise("Administrator provisioning failed: #{Exception.message(error)}")
    end
  end

  defp required_env!(name) do
    case System.get_env(name) do
      value when is_binary(value) and byte_size(value) > 0 -> value
      _ -> Mix.raise("#{name} is required")
    end
  end
end
