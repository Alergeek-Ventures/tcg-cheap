defmodule TcgCheap.Sealed.Shops do
  @moduledoc """
  The shops whose product feeds the buying guide reads, fixed in code, one
  file per country in `lib/tcg_cheap/sealed/shops/` (`TcgCheap.ModuleDir`).
  Each is a `TcgCheap.Sealed.Shop`, which says where and how its feed is read
  and holds the delivery facts shown next to its offers; `nil` means the shop
  does not publish a fact. This module validates them together and answers
  lookups.

  Each country's file holds its shops (`all/0`, every one from its
  `country/0`) and the deliveries to that country of shops abroad
  (`deliveries/0`, by shop key), which become those shops' `deliveries`: a
  new country's shops and deliveries are all in its own file.

  Shops abroad are priced in their own currency, mostly for their singles,
  and compared at their price with their delivery to the market's country; a
  shop without a known delivery price there is only listed
  (`TcgCheap.Sealed.Market`). A shop's delivery within its own country is
  recorded only where the guide has a market.

  singleTCG and PokeKarty ask crawlers in their robots.txt not to read the
  endpoints used here (`/api`, and the Store API with its `per_page` and
  `stock_status` parameters). Their clients read them anyway, for the public
  prices only, at the usual pace and with the guide's own user agent.

  A shop's logo is `priv/static/images/shops/<key>.webp`, a 240×80 WebP on a
  white chip (dark for light logos); a shop without a file shows none. Morion
  Games and Hearts Pub have only their favicons recorded.
  """

  alias TcgCheap.{Countries, ModuleDir}
  alias TcgCheap.Geo.Towns
  alias TcgCheap.Sealed.{Market, Shop, ShopFeed}

  alias TcgCheap.Sealed.ShopFeed.{
    BangerpackSe,
    Chasedex,
    GoogleFeed,
    Jumpseller,
    NopCommerce,
    RajZaIgrace,
    Shopify,
    Shoptet,
    TcgPark,
    WooCommerce,
    ZberiVse
  }

  @dir Path.expand("shops", __DIR__)
  @files ModuleDir.files(@dir)
  for file <- @files, do: @external_resource(Path.join(@dir, file))
  # Fetch jobs are queued in this order and each queue runs one at a time:
  # Polish shops first, then Hungarian, then the rest by country file.
  @countries @files
             |> Enum.map(&ModuleDir.module(__MODULE__, &1))
             |> Enum.sort_by(&{&1.country() != "PL", &1.country() != "HU"})

  # Each delivery is listed by the country it goes to.
  @deliveries (for country <- @countries,
                   {key, delivery} <- country.deliveries(),
                   reduce: %{} do
                 deliveries ->
                   Map.update(deliveries, key, %{country.country() => delivery}, fn by_country ->
                     Map.put(by_country, country.country(), delivery)
                   end)
               end)

  @shops (for country <- @countries, shop <- country.all() do
            unless shop.country == country.country(),
              do: raise(ArgumentError, "shop #{shop.key} is not from #{country.country()}")

            # The store of a shop with only a pickup town is that town's place,
            # found now so that an unknown town does not compile.
            pickup_location =
              case shop do
                %{pickup_location: nil, pickup_city: city} when is_binary(city) ->
                  try do
                    Towns.coords!(shop.country, city)
                  rescue
                    error in ArgumentError ->
                      reraise ArgumentError, "shop #{shop.key}: " <> error.message, __STACKTRACE__
                  end

                %{pickup_location: location} ->
                  location
              end

            %{
              shop
              | deliveries: Map.get(@deliveries, shop.key, %{}),
                pickup_location: pickup_location
            }
          end)

  @keys Enum.map(@shops, & &1.key)

  # The countries with a shop that has a pickup store.
  @pickup_countries for shop <- @shops, shop.pickup_location, uniq: true, do: shop.country

  for key <- Map.keys(@deliveries),
      key not in @keys,
      do: raise(ArgumentError, "delivery of unknown shop #{key}")

  # A shop abroad is read through a client that checks the currency of its
  # prices, from a country whose words the offer list has (`TcgCheap.Countries`).
  @abroad_sources [
    Shopify,
    WooCommerce,
    Chasedex,
    NopCommerce,
    Shoptet,
    GoogleFeed,
    BangerpackSe,
    Jumpseller,
    RajZaIgrace,
    TcgPark,
    ZberiVse
  ]

  for shop <- @shops, shop.currency != "PLN" or shop.country != "PL" do
    unless shop.source in @abroad_sources and Countries.fetch(shop.country) != :error,
      do: raise(ArgumentError, "shop abroad #{shop.key} is misconfigured")
  end

  # A delivery to Poland is in PLN, as the Polish pages show it in złoty, and
  # never to the shop's own country.
  for shop <- @shops, {country, delivery} <- shop.deliveries do
    unless country != shop.country and (country != "PL" or delivery.currency == "PLN"),
      do: raise(ArgumentError, "delivery of #{shop.key} to #{country} is misconfigured")
  end

  # Only a Shopify shop's prices are read per country, and Poland's are
  # stored as `price` in PLN: in złoty, or converted from the shop's currency.
  for shop <- @shops, {country, %{price_currency: currency}} <- shop.deliveries do
    unless shop.source == Shopify and (country != "PL" or currency in ["PLN", shop.currency]),
      do: raise(ArgumentError, "prices of #{shop.key} for #{country} are misconfigured")
  end

  @doc """
  The countries whose buyers the shop charges prices of their own, with the
  currency of each (`price_currency` of `Shop.deliveries`).
  """
  @spec price_currencies(Shop.t()) :: %{String.t() => String.t()}
  def price_currencies(%Shop{deliveries: deliveries}) do
    for {country, %{price_currency: currency}} <- deliveries, into: %{}, do: {country, currency}
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
  Whether the shop sells in the market at home, its price counting without
  delivery: one from the market's country that sells there (`Shop.home_market`).
  """
  @spec domestic?(String.t(), Market.t()) :: boolean()
  def domestic?(key, %Market{country: country}),
    do: match?({:ok, %Shop{country: ^country, home_market: true}}, fetch(key))

  @doc """
  Whether the market has single cards from shops: a shop reading singles
  (`singles_categories` or `singles_markers`) is at home there or has a
  delivery with a known price to its country, so its offers count there
  (`Market.terms/2`). Without one, the market's card pages give the
  Cardmarket trend alone: a shop only listed there could not set a price.
  """
  @spec singles?(Market.t()) :: boolean()
  def singles?(%Market{} = market), do: singles_shops(market) != []

  @doc "The shops reading singles whose offers count in the market (see `singles?/1`)."
  @spec singles_shops(Market.t()) :: [Shop.t()]
  def singles_shops(%Market{} = market) do
    Enum.filter(@shops, fn shop ->
      (shop.singles_categories != nil or shop.singles_markers != nil) and
        counted?(Market.terms({:ok, shop}, market))
    end)
  end

  @doc """
  Whether a shop reading singles is at home in the market (`domestic?/2`).
  Without one every card offer comes from a shop abroad, so a card's price is
  the shop's item price, its delivery stated beside it: a buyer takes many
  cards in one parcel, which one card's delivery would overstate.
  """
  @spec own_singles?(Market.t()) :: boolean()
  def own_singles?(%Market{} = market) do
    Enum.any?(@shops, fn shop ->
      (shop.singles_categories != nil or shop.singles_markers != nil) and
        Market.terms({:ok, shop}, market) == :domestic
    end)
  end

  defp counted?(:domestic), do: true
  defp counted?({:delivered, _delivery}), do: true
  defp counted?(_listed_or_absent), do: false

  @doc "Whether a shop of the country (its ISO code) has a pickup store, so that distances to it can be shown."
  @spec pickup?(String.t()) :: boolean()
  def pickup?(country), do: country in @pickup_countries

  @spec all() :: [Shop.t()]
  def all, do: @shops

  @spec keys() :: [String.t()]
  def keys, do: @keys

  @doc "Every host a shop's product images may be shown from."
  @spec image_hosts() :: [String.t()]
  def image_hosts, do: @shops |> Enum.flat_map(&ShopFeed.image_hosts/1) |> Enum.uniq()

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

  # A newly added country or logo file is not an external resource yet;
  # recompile when either set changes.
  @doc false
  def __mix_recompile__? do
    logos =
      for file <- File.ls!(@logo_dir), Path.extname(file) == ".webp", do: Path.rootname(file)

    ModuleDir.files(@dir) != @files or MapSet.new(logos) != MapSet.new(@logos)
  end

  @doc "Whether the shop has a logo in `priv/static/images/shops`."
  @spec logo?(String.t()) :: boolean()
  def logo?(key), do: key in @logos
end
