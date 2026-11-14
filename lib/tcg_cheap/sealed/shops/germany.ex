defmodule TcgCheap.Sealed.Shops.Germany do
  @moduledoc """
  Shops in Germany, priced in their own currency and compared by their delivery
  to the guide's markets (`TcgCheap.Sealed.Shops`).
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.Shopify

  @shops [
    %Shop{
      key: "godofcards",
      name: "God of Cards",
      host: "godofcards.com",
      source: Shopify,
      collection: "pokemon-tcg",
      currency: "EUR",
      country: "DE",
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "cardcosmos",
      name: "CardCosmos",
      host: "cardcosmos.de",
      source: Shopify,
      collection: "pokemon-karten-kaufen",
      currency: "EUR",
      country: "DE",
      max_pages: 10,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "DE"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc "Deliveries to Germany of shops abroad, by shop key: none recorded."
  def deliveries, do: %{}
end
