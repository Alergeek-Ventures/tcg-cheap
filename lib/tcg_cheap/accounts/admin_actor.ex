defmodule TcgCheap.Accounts.AdminActor do
  @moduledoc "Fail-closed validation for administrator actors at operational boundaries."

  alias TcgCheap.Accounts.Admin

  @spec validate(term()) :: :ok | {:error, :invalid_actor}
  def validate(%Admin{id: id}) when is_binary(id) do
    with {:ok, uuid} <- dump_uuid(id),
         {:ok, %{rows: [[1]]}} <-
           TcgCheap.Repo.query("SELECT 1 FROM admins WHERE id = $1", [uuid]) do
      :ok
    else
      _ -> {:error, :invalid_actor}
    end
  rescue
    _ -> {:error, :invalid_actor}
  end

  def validate(_), do: {:error, :invalid_actor}

  defp dump_uuid(<<_::binary-size(16)>> = id), do: {:ok, id}
  defp dump_uuid(id), do: Ecto.UUID.dump(id)
end
