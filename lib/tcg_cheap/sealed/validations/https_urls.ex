defmodule TcgCheap.Sealed.Validations.HttpsUrls do
  @moduledoc """
  Every URL in a list attribute, or under `key` in each of its maps, is a
  well-formed https URL with a host.
  """

  use Ash.Resource.Validation

  alias TcgCheap.Catalogue.ExternalUrl

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, opts, _context) do
    urls =
      case {Ash.Changeset.get_attribute(changeset, opts[:attribute]) || [], opts[:key]} do
        {list, nil} -> list
        {list, key} -> Enum.map(list, &Map.get(&1, key))
      end

    if Enum.all?(urls, &ExternalUrl.valid?/1),
      do: :ok,
      else: {:error, field: opts[:attribute], message: "must be https URLs with a host"}
  end
end
