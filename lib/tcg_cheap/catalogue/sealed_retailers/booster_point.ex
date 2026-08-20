defmodule TcgCheap.Catalogue.SealedRetailers.BoosterPoint do
  @moduledoc """
  This fixed-policy adapter is approved for agreed recurring internal MVP acquisition. Persisted
  provider controls, request budgets, exact source policy, and Coolify/app takedown are operational
  safeguards.
  """

  @behaviour TcgCheap.Catalogue.SealedRetailerAdapter

  alias TcgCheap.Catalogue.SealedRetailers.WooCommerceStoreAPI

  @booster_point_spec WooCommerceStoreAPI.new!(%{
                        endpoint: "https://boosterpoint.pl/wp-json/wc/store/v1/products",
                        category: 61,
                        canonical_host: "boosterpoint.pl",
                        product_path: ~r|\A/produkt/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
                        eligible_category_slugs: [
                          "boostery",
                          "booster-box",
                          "blistry",
                          "boostery-i-blistry",
                          "puszki-tins",
                          "boxy-vmax-vstar-ex",
                          "gotowe-talie-deck",
                          "puszki-decki-box-tcg",
                          "elite-trainer-boxy",
                          "zestawy-kolekcjonerskie"
                        ],
                        exclusion:
                          ~r/(japan(?:ese)?|jpn|japoń|japons|korea(?:n|ń)?|china|chinese|chiń|chins|import|single|singles|pojedyncz|accessor|akcesori|gadget|gadżet|toy|zabawk|sleeve|preorder|pre-order|back-?order|przedsprzeda|przedpremier|event|wydarzen|ticket|bilet)/iu,
                        required_title: ~r/pok(?:e|é)mon\s+tcg/iu
                      })

  @impl true
  def source_key, do: "boosterpoint"

  @impl true
  def fetch_listings(%{source_key: "boosterpoint", status: "active"}, options)
      when is_list(options),
      do: WooCommerceStoreAPI.fetch(@booster_point_spec, options)

  def fetch_listings(%{source_key: "boosterpoint"}, _options), do: {:error, :retailer_disabled}
  def fetch_listings(_retailer, _options), do: {:error, :invalid_retailer}
end
