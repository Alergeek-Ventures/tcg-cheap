defmodule TcgCheap.Sealed.Shops do
  @moduledoc """
  The shops whose product feeds the buying guide reads, fixed in code: Polish
  shops, Hungarian shops and shops in other countries that are compared by
  their delivery to Poland. Each is a `TcgCheap.Sealed.Shop`, which says where
  and how its feed is read and holds the delivery facts shown next to its
  offers; `nil` means the shop does not publish a fact. The entries live in
  `TcgCheap.Sealed.Shops.Poland`, `TcgCheap.Sealed.Shops.Hungary` and
  `TcgCheap.Sealed.Shops.OtherCountries`; this module validates them together
  and answers lookups.

  singleTCG and PokeKarty ask crawlers in their robots.txt not to read the
  endpoints used here (`/api`, and the Store API with its `per_page` and
  `stock_status` parameters). Their clients read them anyway, for the public
  prices only, at the usual pace and with the guide's own user agent.

  A shop's logo is `priv/static/images/shops/<key>.webp`, a 240×80 WebP on a
  white chip (dark for light logos); a shop without a file shows none. Morion
  Games and Hearts Pub have only their favicons: Morion's header image is a
  banner and Hearts Pub sits behind a bot check.
  """

  alias TcgCheap.Pricing.ExchangeRate
  alias TcgCheap.Sealed.{Market, Shop}

  alias TcgCheap.Sealed.ShopFeed.{
    Chasedex,
    GoogleFeed,
    NopCommerce,
    Shopify,
    Shoptet,
    WooCommerce
  }

  alias TcgCheap.Sealed.Shops.{Hungary, OtherCountries, Poland}

  @shops Poland.all() ++ Hungary.all() ++ OtherCountries.all()

  @keys Enum.map(@shops, & &1.key)

  # A shop abroad is read through a client that checks the currency of its
  # prices, in a currency with a daily NBP rate, from a country the offer list
  # can name (`OfferComponents`).
  @abroad_sources [Shopify, WooCommerce, Chasedex, NopCommerce, Shoptet, GoogleFeed]
  @countries ~w(NL DE BE GB SE DK CZ HU PT)

  for shop <- @shops, shop.currency != "PLN" or shop.country != "PL" do
    unless shop.source in @abroad_sources and
             shop.currency in ExchangeRate.currencies() and
             shop.country in @countries,
           do: raise(ArgumentError, "shop abroad #{shop.key} is misconfigured")
  end

  # Each delivery is in a currency with an NBP rate; one to Poland in PLN, as
  # the Polish pages show it in złoty.
  for shop <- @shops, {country, delivery} <- shop.deliveries do
    unless delivery.currency in ["PLN" | ExchangeRate.currencies()] and
             (country != "PL" or delivery.currency == "PLN"),
           do: raise(ArgumentError, "delivery of #{shop.key} to #{country} is misconfigured")
  end

  @doc """
  The price an offer is compared at with other shops' offers in Poland
  (verdicts, lowest prices, history), `Market.compared/3` for one offer: a
  Polish shop's item price; a shop abroad's with its cheapest delivery to
  Poland, none from its free-delivery threshold. Nil for a shop abroad whose
  delivery price is unknown: it is only listed.
  """
  @spec compared_price(String.t(), Decimal.t()) :: Decimal.t() | nil
  def compared_price(key, price) do
    case compared([%{shop: key, price: price}]) do
      [%{price: compared}] -> compared
      [] -> nil
    end
  end

  @doc "The offers that count in Polish prices, each at its `compared_price/2`."
  @spec compared([offer]) :: [offer] when offer: %{shop: String.t(), price: Decimal.t()}
  def compared(offers), do: Market.compared(offers, Market.poland(), Date.utc_today())

  @doc """
  An offer's place in an offer list, as a float: its `compared_price/2`, or
  its item price for a shop that is only listed.
  """
  @spec listing_price(%{shop: String.t(), price: Decimal.t()}) :: float()
  def listing_price(offer),
    do: Decimal.to_float(compared_price(offer.shop, offer.price) || offer.price)

  @doc "Shops abroad compared with their delivery to Poland: `{shipping, free from}` in PLN by key."
  @spec delivered() :: %{String.t() => {Decimal.t(), Decimal.t() | nil}}
  def delivered do
    for shop <- @shops,
        {:delivered, delivery} <- [Market.terms({:ok, shop}, Market.poland())],
        into: %{},
        do: {shop.key, {delivery.shipping_from, delivery.free_shipping_from}}
  end

  @doc "Shops whose offers never count in Polish prices: abroad without a known delivery price."
  @spec listed_only_keys() :: [String.t()]
  def listed_only_keys do
    for shop <- @shops,
        Market.terms({:ok, shop}, Market.poland()) in [:listed, :absent],
        do: shop.key
  end

  @spec all() :: [Shop.t()]
  def all, do: @shops

  @spec keys() :: [String.t()]
  def keys, do: @keys

  @doc "Every host a shop's product images may be shown from."
  @spec image_hosts() :: [String.t()]
  def image_hosts, do: @shops |> Enum.flat_map(& &1.source.image_hosts(&1)) |> Enum.uniq()

  @spec fetch(term()) :: {:ok, Shop.t()} | :error
  def fetch(key) when key in @keys, do: {:ok, Enum.find(@shops, &(&1.key == key))}
  def fetch(_key), do: :error

  @doc "The shop's display name, or the raw key for a shop no longer configured."
  @spec name(String.t()) :: String.t()
  def name(key) do
    case fetch(key) do
      {:ok, shop} -> shop.name
      :error -> key
    end
  end

  @logo_dir Path.expand("../../../priv/static/images/shops", __DIR__)
  @logos for file <- File.ls!(@logo_dir), Path.extname(file) == ".webp", do: Path.rootname(file)
  for logo <- @logos, do: @external_resource(Path.join(@logo_dir, logo <> ".webp"))

  # A newly added logo file is not an external resource yet; recompile when the set changes.
  @doc false
  def __mix_recompile__? do
    logos =
      for file <- File.ls!(@logo_dir), Path.extname(file) == ".webp", do: Path.rootname(file)

    MapSet.new(logos) != MapSet.new(@logos)
  end

  @doc "Whether the shop has a logo in `priv/static/images/shops`."
  @spec logo?(String.t()) :: boolean()
  def logo?(key), do: key in @logos
end
