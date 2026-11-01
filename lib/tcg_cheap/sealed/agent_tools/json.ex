defmodule TcgCheap.Sealed.AgentTools.Json do
  @moduledoc "Plain JSON-ready maps of offers, products and suggested prices for the agent tools."

  alias TcgCheap.Sealed.{Offer, Product, Shops, SuggestedPrice}

  @spec offer(Offer.t()) :: map()
  def offer(%Offer{} = offer) do
    %{
      id: offer.id,
      shop: offer.shop,
      shop_name: Shops.name(offer.shop),
      title: offer.title,
      price: offer.price,
      in_stock: offer.in_stock,
      ean: offer.ean,
      url: offer.url,
      manual: offer.manual?,
      product_id: offer.product_id,
      last_seen_at: offer.last_seen_at
    }
    |> put_product(offer.product)
  end

  @spec product(Product.t() | nil) :: map() | nil
  def product(nil), do: nil

  def product(%Product{} = product) do
    Map.take(product, [:id, :slug, :name, :kind, :set_name, :cardmarket_id, :eans])
  end

  @spec suggested_price(SuggestedPrice.t() | nil) :: map() | nil
  def suggested_price(nil), do: nil

  def suggested_price(%SuggestedPrice{} = item) do
    item
    |> Map.take([:id, :rebel_id, :title, :url, :ean, :price, :product_id, :last_seen_at])
    |> Map.put(:manual, item.manual?)
    |> put_product(item.product)
  end

  defp put_product(map, %Product{} = product), do: Map.put(map, :product, product(product))
  defp put_product(map, _not_loaded), do: map
end
