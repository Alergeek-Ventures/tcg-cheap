defmodule TcgCheap.Catalogue.SealedRetailers.Boosterland do
  @moduledoc "Normalizes Boosterland's WooCommerce Store API into sealed listings."

  @behaviour TcgCheap.Catalogue.SealedRetailerAdapter

  alias TcgCheap.Catalogue.SealedRetailers.WooCommerceStoreAPI

  @specification WooCommerceStoreAPI.new!(%{
                   endpoint: "https://boosterland.pl/wp-json/wc/store/v1/products",
                   category: 40,
                   canonical_host: "boosterland.pl",
                   product_path: ~r|\A/sklep/(?:[a-z0-9]+(?:-[a-z0-9]+)*/){1,5}\z|,
                   eligible_category_slugs: ["pokemon"],
                   exclusion:
                     ~r/(japan(?:ese)?|jpn|japoń|japons|korea(?:n|ń)?|korean|china|chinese|chiń|chins|import|single|singles|pojedyncz|accessor|akcesori|acrylic|sleeve|protection|ochron|gadget|gadżet|toy|zabawk|mystery|preorder|pre-order|back-?order|przedsprzeda|przedpremier|event|wydarzen|ticket|bilet)/iu,
                   required_title: ~r/pok(?:e|é)mon\s+tcg/iu
                 })

  @impl true
  def source_key, do: "boosterland"

  @impl true
  def fetch_listings(%{source_key: "boosterland", status: "active"}, options)
      when is_list(options),
      do: WooCommerceStoreAPI.fetch(@specification, options)

  def fetch_listings(%{source_key: "boosterland"}, _options), do: {:error, :retailer_disabled}
  def fetch_listings(_retailer, _options), do: {:error, :invalid_retailer}
end
