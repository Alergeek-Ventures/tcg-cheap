defmodule TcgCheap.Catalogue.SealedRetailers.LootQuest do
  @moduledoc """
  Normalizes LootQuest's public WooCommerce Store API into sealed listing values.

  Private development configuration permits explicit technical test runs; public acquisition and
  republication still require external permission.
  """

  @behaviour TcgCheap.Catalogue.SealedRetailerAdapter

  alias TcgCheap.Catalogue.SealedRetailers.WooCommerceStoreAPI

  @lootquest_spec WooCommerceStoreAPI.new!(%{
                    endpoint: "https://lootquest.pl/wp-json/wc/store/v1/products",
                    category: 55,
                    canonical_host: "lootquest.pl",
                    product_path: ~r|\A/produkt/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
                    eligible_category_slugs: [
                      "pokemon-boostery",
                      "pokemon-blistry",
                      "pokemon-zestawy",
                      "pokemon-talie"
                    ],
                    exclusion:
                      ~r/(japan|japoń|japons|korea|koreań|koreans|china|chiń|chins|import|single|pojedyncz|accessor|akcesori|sleeve|preorder|pre-order|backorder|przedsprzeda|przedpremier)/iu,
                    required_title: nil
                  })

  @impl true
  def source_key, do: "lootquest"

  @impl true
  def fetch_listings(%{source_key: "lootquest", status: "active"}, options)
      when is_list(options),
      do: WooCommerceStoreAPI.fetch(@lootquest_spec, options)

  def fetch_listings(%{source_key: "lootquest"}, _options), do: {:error, :retailer_disabled}
  def fetch_listings(_retailer, _options), do: {:error, :invalid_retailer}
end
