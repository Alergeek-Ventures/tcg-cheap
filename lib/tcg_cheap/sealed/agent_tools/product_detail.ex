defmodule TcgCheap.Sealed.AgentTools.ProductDetail do
  @moduledoc """
  One product with its public verdict, current offers, suggested price and
  contents, as on its product page.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.Json
  alias TcgCheap.Sealed.Guide

  @impl true
  def run(input, _opts, _context) do
    with {:ok, slug} <- slug(input.arguments),
         {:ok, detail} <- Guide.product(slug, DateTime.utc_now()) do
      {:ok, present(detail)}
    else
      _ -> {:error, InvalidArgument.exception(field: :slug, message: "no such product")}
    end
  end

  defp slug(%{slug: slug}) when is_binary(slug), do: {:ok, slug}

  defp slug(%{id: id}) when is_binary(id) do
    case Sealed.get_product(id) do
      {:ok, %Sealed.Product{} = product} -> {:ok, product.slug}
      _ -> :error
    end
  end

  defp slug(_arguments), do: :error

  defp present(%{product: product, verdict: verdict} = detail) do
    %{
      product:
        product
        |> Map.take([
          :cardmarket_added_on,
          :cardmarket_trend,
          :cardmarket_price_updated_on,
          :available,
          :lowest_price,
          :image_url
        ])
        |> Map.merge(Json.product(product))
        |> Map.put(:path, "/produkty/#{product.slug}"),
      verdict: %{verdict | cheapest: verdict.cheapest && Json.offer(verdict.cheapest)},
      cardmarket_trend_pln: detail.cardmarket_pln,
      eur_pln: detail.eur_pln,
      suggested_price: Json.suggested_price(detail.suggested_price),
      contents: Json.contents(product.contents),
      offers: Enum.map(detail.offers, &Json.offer/1)
    }
  end
end
