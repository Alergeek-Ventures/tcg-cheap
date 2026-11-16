defmodule TcgCheap.Sealed.Shops.Portugal do
  @moduledoc """
  Shops in Portugal, priced in their own currency and compared by their delivery
  to the guide's markets (`TcgCheap.Sealed.Shops`).
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.Shopify

  @shops [
    %Shop{
      key: "psydeck",
      name: "Psydeck",
      host: "psydeck.com",
      source: Shopify,
      # PSA is the vendor of its graded cards.
      excluded_markers: ["PSA"],
      currency: "EUR",
      country: "PT",
      # 2 pages in November 2026.
      max_pages: 4,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "PT"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc "Deliveries to Portugal of shops abroad, by shop key: none recorded."
  def deliveries, do: %{}
end
