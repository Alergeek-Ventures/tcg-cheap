defmodule TcgCheap.Catalogue.Validations.Retailer do
  @moduledoc "Validates retailer identity fields."
  use Ash.Resource.Validation

  @impl true
  # These are independent identity constraints with field-specific errors.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def validate(changeset, _opts, _context) do
    category = Ash.Changeset.get_attribute(changeset, :category)
    source_key = Ash.Changeset.get_attribute(changeset, :source_key)
    name = Ash.Changeset.get_attribute(changeset, :name)
    url = Ash.Changeset.get_attribute(changeset, :homepage_url)

    cond do
      category not in ~w(regular_retailer lgs) ->
        {:error, field: :category, message: "is invalid"}

      not is_binary(source_key) or String.trim(source_key) == "" ->
        {:error, field: :source_key, message: "must not be blank"}

      not is_binary(name) or String.trim(name) == "" ->
        {:error, field: :name, message: "must not be blank"}

      not is_nil(url) and not https_url?(url) ->
        {:error, field: :homepage_url, message: "must be HTTPS with a host"}

      true ->
        :ok
    end
  end

  defp https_url?(value) when is_binary(value) do
    uri = URI.parse(String.trim(value))
    uri.scheme == "https" and is_binary(uri.host) and String.trim(uri.host) != ""
  end

  defp https_url?(_), do: false
end
