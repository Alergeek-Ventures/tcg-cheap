defmodule TcgCheap.Sealed.AgentTools.SetPhoto do
  @moduledoc """
  Sets or clears a product's checked photo, which `TcgCheap.Sealed.PhotoMirror`
  stores in place of the shops' photos. The image host is checked against
  `TcgCheap.Catalogue.ExternalImage`.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Catalogue.ExternalImage
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.Json

  @impl true
  def run(input, _opts, _context) do
    url = input.arguments[:url]

    with :ok <- allowed(url),
         {:ok, product} when not is_nil(product) <- Sealed.get_product(input.arguments.product_id),
         {:ok, product} <- Sealed.set_product_photo(product, url) do
      {:ok, Map.put(Json.product(product), :checked_photo_url, product.checked_photo_url)}
    else
      {:ok, nil} -> invalid(:product_id, "no product with this id")
      {:error, error} -> {:error, error}
    end
  end

  defp allowed(nil), do: :ok

  defp allowed(url) do
    if ExternalImage.valid?(url),
      do: :ok,
      else: invalid(:url, "#{url} is not an https image on an allowed image host")
  end

  defp invalid(field, message),
    do: {:error, InvalidArgument.exception(field: field, message: message)}
end
