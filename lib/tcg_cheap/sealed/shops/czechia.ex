defmodule TcgCheap.Sealed.Shops.Czechia do
  @moduledoc """
  Shops in Czechia, priced in their own currency and compared by their delivery
  to the guide's markets (`TcgCheap.Sealed.Shops`).
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.Shoptet

  @shops [
    %Shop{
      key: "bulbazard",
      name: "Bulbazard",
      host: "www.bulbazard.cz",
      source: Shoptet,
      singles_categories: ["/kusove-karty-pokemon/"],
      currency: "CZK",
      singles_only: true,
      country: "CZ",
      max_pages: 40,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "CZ"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc "Deliveries to Czechia of shops abroad, by shop key: none recorded."
  def deliveries, do: %{}
end
