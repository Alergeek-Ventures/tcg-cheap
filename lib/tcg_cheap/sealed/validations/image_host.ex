defmodule TcgCheap.Sealed.Validations.ImageHost do
  @moduledoc "An image URL attribute is on a host we mirror from (`TcgCheap.Catalogue.ExternalImage`)."

  use Ash.Resource.Validation

  alias TcgCheap.Catalogue.ExternalImage

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, opts, _context) do
    case Ash.Changeset.get_attribute(changeset, opts[:attribute]) do
      nil ->
        :ok

      url ->
        if ExternalImage.valid?(url),
          do: :ok,
          else:
            {:error,
             field: opts[:attribute], message: "must be an https URL on an allowed image host"}
    end
  end
end
