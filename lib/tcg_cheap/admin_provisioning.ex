defmodule TcgCheap.AdminProvisioning do
  @moduledoc false

  alias TcgCheap.Accounts.Admin

  @spec register(String.t(), String.t()) :: {:ok, Admin.t()} | {:error, Ash.Error.t()}
  def register(email, password) when is_binary(email) and is_binary(password) do
    TcgCheap.Accounts.register_admin(
      %{email: email, password: password, password_confirmation: password},
      authorize?: false
    )
  end

  @spec required_env!(String.t()) :: String.t()
  def required_env!(name) do
    case System.get_env(name) do
      value when is_binary(value) and byte_size(value) > 0 -> value
      _ -> raise ArgumentError, "#{name} is required"
    end
  end
end
