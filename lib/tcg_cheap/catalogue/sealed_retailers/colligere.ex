defmodule TcgCheap.Catalogue.SealedRetailers.Colligere do
  @moduledoc "Normalizes Colligere's WooCommerce Store API into sealed listings."

  @behaviour TcgCheap.Catalogue.SealedRetailerAdapter

  alias TcgCheap.Catalogue.SealedRetailers.WooCommerceStoreAPI

  @specification WooCommerceStoreAPI.new!(%{
                   endpoint: "https://colligere.pl/wp-json/wc/store/v1/products",
                   category: 23,
                   canonical_host: "colligere.pl",
                   product_path: ~r|\A/sklep/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
                   eligible_category_slugs: ["pokemon-tcg"],
                   exclusion:
                     ~r/(japan(?:ese)?|jpn|japoń|japons|korea(?:n|ń)?|korean|china|chinese|chiń|chins|import|single|singles|pojedyncz|accessor|akcesori|acrylic|sleeve|protection|ochron|gadget|gadżet|toy|zabawk|mystery|preorder|pre-order|back-?order|przedsprzeda|przedpremier|event|wydarzen|ticket|bilet)/iu,
                   required_title: ~r/pok(?:e|é)mon\s+tcg/iu
                 })

  @impl true
  def source_key, do: "colligere"

  @impl true
  def fetch_listings(%{source_key: "colligere", status: "active"}, options)
      when is_list(options),
      do: WooCommerceStoreAPI.fetch(@specification, options)

  def fetch_listings(%{source_key: "colligere"}, _options), do: {:error, :retailer_disabled}
  def fetch_listings(_retailer, _options), do: {:error, :invalid_retailer}
end
