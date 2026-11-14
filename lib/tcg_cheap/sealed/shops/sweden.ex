defmodule TcgCheap.Sealed.Shops.Sweden do
  @moduledoc """
  Shops in Sweden, priced in their own currency and compared by their delivery
  to the guide's markets (`TcgCheap.Sealed.Shops`).
  """

  alias TcgCheap.Sealed.Shop
  alias TcgCheap.Sealed.ShopFeed.{Chasedex, GoogleFeed}

  @shops [
    # Bangerpack (White Tree AB, Helsingborg) publishes a Google Shopping
    # export, served from its CDN in euros; it holds sealed products only. Its
    # FAQ (2026-11-10) says it ships to Poland at a price shown only in the
    # checkout and has no free delivery.
    %Shop{
      key: "bangerpack",
      name: "Bangerpack",
      host: "bangerpack.com",
      source: GoogleFeed,
      feed_host: "cdn.bangerpack.com",
      feed_path: "/shopping-pl.xml",
      currency: "EUR",
      country: "SE",
      max_pages: 1,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    },
    %Shop{
      key: "chasedex",
      name: "Chasedex",
      host: "chasedex.se",
      source: Chasedex,
      # Not read (the sitemaps decide); nil would disable singles.
      singles_categories: ["all"],
      currency: "SEK",
      singles_only: true,
      country: "SE",
      max_pages: 80,
      shipping_from: nil,
      free_shipping_from: nil,
      pickup_city: nil
    }
  ]

  @doc "The ISO code of the country these shops are in."
  def country, do: "SE"

  @doc "The shops, in the order they are fetched and listed."
  @spec all() :: [Shop.t()]
  def all, do: @shops

  @doc "Deliveries to Sweden of shops abroad, by shop key: none recorded."
  def deliveries, do: %{}
end
