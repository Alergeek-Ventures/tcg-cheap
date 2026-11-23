defmodule TcgCheap.Sealed.Shops.Belgium do
  @moduledoc """
  Shops in Belgium, priced in their own currency and compared by their delivery
  to the guide's markets (`TcgCheap.Sealed.Shops`).
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.WooCommerce

  @product ~r|\A/product/[a-z0-9]+(?:-[a-z0-9]+)*/\z|

  @shops [
    # Based in Hasselt (company address in its terms and on its contact page).
    %Shop{
      key: "collecthors",
      name: "Collecthors",
      host: "www.collecthors.eu",
      source: WooCommerce,
      category: "21965",
      product_path: @product,
      currency: "EUR",
      country: "BE",
      max_pages: 9,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "BE"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc "Deliveries to Belgium of shops abroad, by shop key: none recorded."
  def deliveries, do: %{}
end
