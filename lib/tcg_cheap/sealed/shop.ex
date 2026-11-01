defmodule TcgCheap.Sealed.Shop do
  @moduledoc """
  A configured shop: how to read its product feed and what a buyer pays and
  can do beyond the item price.

    * `source` – the `TcgCheap.Sealed.ShopFeed` client that reads the feed;
    * WooCommerce: `category` (Pokémon category ids to request, required),
      `sealed_categories` (category slugs that count as sealed; nil when the
      title decides) and `product_path` (the permalink path shape);
    * Shopify: `collection` (the Pokémon collection handle; nil reads the
      whole shop);
    * Google Merchant and Ceneo feeds: `feed_path` (the export, which may
      cover the whole shop); IdoSell: `feed_path` (a Pokémon category or
      search listing, query included);
    * `shipping_from` – the cheapest delivery price in PLN, `free_shipping_from`
      – the order value from which delivery is free, `pickup_city` – the city
      of the shop's own store where orders can be picked up in person; each nil
      when the shop does not publish it;
    * `pickup_location` – `{latitude, longitude}` of that store, for distances
      to visitors; nil when the shop has no pickup.
  """
  @enforce_keys [
    :key,
    :name,
    :host,
    :source,
    :max_pages,
    :shipping_from,
    :free_shipping_from,
    :pickup_city
  ]
  defstruct @enforce_keys ++
              [
                :category,
                :sealed_categories,
                :product_path,
                :collection,
                :feed_path,
                :pickup_location
              ]

  @type t :: %__MODULE__{
          key: String.t(),
          name: String.t(),
          host: String.t(),
          source: module(),
          max_pages: pos_integer(),
          category: String.t() | nil,
          sealed_categories: [String.t()] | nil,
          product_path: Regex.t() | nil,
          collection: String.t() | nil,
          feed_path: String.t() | nil,
          shipping_from: Decimal.t() | nil,
          free_shipping_from: Decimal.t() | nil,
          pickup_city: String.t() | nil,
          pickup_location: TcgCheap.Geo.coords() | nil
        }
end
