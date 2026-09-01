defmodule TcgCheap.Catalogue.SealedRetailers.PokeBooster do
  @moduledoc "Normalizes PokeBooster's WooCommerce Store API into sealed listings."

  @behaviour TcgCheap.Catalogue.SealedRetailerAdapter

  alias TcgCheap.Catalogue.SealedRetailers.WooCommerceStoreAPI

  @poke_booster_spec WooCommerceStoreAPI.new!(%{
                       endpoint: "https://pokebooster.pl/wp-json/wc/store/v1/products",
                       category: "26,27,42,57",
                       canonical_host: "pokebooster.pl",
                       product_path: ~r|\A/produkt/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
                       eligible_category_slugs: [
                         "booster",
                         "elite-trainer-box",
                         "premium-collection",
                         "puszki"
                       ],
                       exclusion:
                         ~r/(japan(?:ese)?|jpn|japoń|japons|korea(?:n|ń)?|korean|china|chinese|chiń|chins|import|single|singles|pojedyncz|accessor|akcesori|acrylic|sleeve|protection|ochron|gadget|gadżet|toy|zabawk|mystery|preorder|pre-order|back-?order|przedsprzeda|przedpremier|event|wydarzen|ticket|bilet)/iu,
                       required_title: ~r/pok(?:e|é)mon\s+tcg/iu
                     })

  @impl true
  def source_key, do: "pokebooster"

  @impl true
  def fetch_listings(%{source_key: "pokebooster", status: "active"}, options)
      when is_list(options),
      do: WooCommerceStoreAPI.fetch(@poke_booster_spec, options)

  def fetch_listings(%{source_key: "pokebooster"}, _options), do: {:error, :retailer_disabled}
  def fetch_listings(_retailer, _options), do: {:error, :invalid_retailer}
end
