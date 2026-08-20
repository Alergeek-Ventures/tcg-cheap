defmodule TcgCheap.Catalogue.SealedRetailers.CardzHouse do
  @moduledoc """
  Normalizes CardzHouse's WooCommerce Store API into sealed listing values.

  This fixed-policy adapter is approved for agreed recurring internal MVP acquisition. Persisted
  provider controls, request budgets, exact source policy, and Coolify/app takedown are operational
  safeguards.
  """

  @behaviour TcgCheap.Catalogue.SealedRetailerAdapter

  alias TcgCheap.Catalogue.SealedRetailers.WooCommerceStoreAPI

  @cardz_house_spec WooCommerceStoreAPI.new!(%{
                      endpoint: "https://cardzhouse.pl/wp-json/wc/store/v1/products",
                      category: 742,
                      canonical_host: "cardzhouse.pl",
                      product_path: ~r|\A/product/[a-z0-9]+(?:-[a-z0-9]+)*/\z|,
                      eligible_category_slugs: [
                        "boostery",
                        "3-packi-blistry",
                        "booster-bundle",
                        "booster-boxy",
                        "elite-trainer-boxy",
                        "kolekcjonerskie",
                        "premium-boxy",
                        "puszki",
                        "theme-decki"
                      ],
                      exclusion:
                        ~r/(japan|jpn|japoń|japons|korea|korean|koreań|china|chinese|chiń|import|single|singles|pojedyncz|accessor|akcesori|acrylic|sleeve|protection|ochron|mystery|preorder|pre-order|backorder|przedsprzeda|przedpremier)/iu,
                      required_title: ~r/pok(?:é|e)mon\s+tcg/iu
                    })

  @impl true
  def source_key, do: "cardzhouse"

  @impl true
  def fetch_listings(%{source_key: "cardzhouse", status: "active"}, options)
      when is_list(options),
      do: WooCommerceStoreAPI.fetch(@cardz_house_spec, options)

  def fetch_listings(%{source_key: "cardzhouse"}, _options), do: {:error, :retailer_disabled}
  def fetch_listings(_retailer, _options), do: {:error, :invalid_retailer}
end
