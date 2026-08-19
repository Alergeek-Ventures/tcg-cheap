defmodule TcgCheap.Catalogue.Validations.CollectionScope do
  @moduledoc false
  use Ash.Resource.Validation

  @scopes ["pitch_black_full", "rolling_ir_sir", "curated_playable", "legacy_local"]

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    scopes = list_attribute(changeset, :collection_scopes)
    source = typed_attribute(changeset, :collection_scope_source, &is_binary/1)
    scoped_at = typed_attribute(changeset, :collection_scoped_at, &match?(%DateTime{}, &1))
    expires_on = typed_attribute(changeset, :collection_expires_on, &match?(%Date{}, &1))

    with :ok <- valid_scope_values(scopes),
         :ok <- unique_scopes(scopes),
         :ok <- valid_metadata(scopes, source, scoped_at, expires_on) do
      valid_expiry(expires_on, scoped_at)
    end
  end

  defp list_attribute(changeset, attribute) do
    case Ash.Changeset.get_attribute(changeset, attribute) do
      value when is_list(value) -> value
      _ -> []
    end
  end

  defp typed_attribute(changeset, attribute, predicate) do
    case Ash.Changeset.get_attribute(changeset, attribute) do
      value when is_nil(value) -> nil
      value -> if(predicate.(value), do: value, else: nil)
    end
  end

  defp valid_scope_values(scopes) do
    if Enum.any?(scopes, &(&1 not in @scopes)) do
      {:error, field: :collection_scopes, message: "contains an invalid scope"}
    else
      :ok
    end
  end

  defp unique_scopes(scopes) do
    if length(scopes) == length(Enum.uniq(scopes)) do
      :ok
    else
      {:error, field: :collection_scopes, message: "must not contain duplicates"}
    end
  end

  defp valid_metadata([], nil, nil, nil), do: :ok

  defp valid_metadata([], _source, _scoped_at, _expires_on),
    do: {:error, message: "empty scopes require empty metadata"}

  defp valid_metadata(_scopes, source, scoped_at, _expires_on)
       when not is_nil(source) and not is_nil(scoped_at), do: :ok

  defp valid_metadata(_scopes, _source, _scoped_at, _expires_on),
    do: {:error, message: "scopes require source and scoped_at"}

  defp valid_expiry(nil, _scoped_at), do: :ok
  defp valid_expiry(_expires_on, nil), do: :ok

  defp valid_expiry(expires_on, scoped_at) do
    if Date.compare(expires_on, DateTime.to_date(scoped_at)) == :lt do
      {:error, field: :collection_expires_on, message: "cannot precede scoped_at"}
    else
      :ok
    end
  end
end
