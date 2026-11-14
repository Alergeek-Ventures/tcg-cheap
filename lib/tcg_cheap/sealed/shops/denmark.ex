defmodule TcgCheap.Sealed.Shops.Denmark do
  @moduledoc """
  Shops in Denmark, priced in their own currency and compared by their delivery
  to the guide's markets (`TcgCheap.Sealed.Shops`).
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.Shopify

  @shops [
    %Shop{
      key: "gemipulls",
      name: "GemiPulls",
      host: "gemipulls.com",
      source: Shopify,
      singles_categories: ["singles"],
      currency: "DKK",
      singles_only: true,
      country: "DK",
      max_pages: 5,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "DK"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc "Deliveries to Denmark of shops abroad, by shop key: none recorded."
  def deliveries, do: %{}
end
