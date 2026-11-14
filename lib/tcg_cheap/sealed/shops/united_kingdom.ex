defmodule TcgCheap.Sealed.Shops.UnitedKingdom do
  @moduledoc """
  Shops in the United Kingdom, priced in their own currency and compared by their delivery
  to the guide's markets (`TcgCheap.Sealed.Shops`).
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.NopCommerce

  @shops [
    %Shop{
      key: "unicorncards",
      name: "Unicorn Cards",
      host: "unicorncards.co.uk",
      source: NopCommerce,
      singles_categories: ["1:1"],
      currency: "GBP",
      singles_only: true,
      country: "GB",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "GB"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc "Deliveries to the United Kingdom of shops abroad, by shop key: none recorded."
  def deliveries, do: %{}
end
