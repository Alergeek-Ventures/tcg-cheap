defmodule TcgCheapWeb.Region do
  @moduledoc """
  The part of the guide a page belongs to: its first path segment (`/pl/…`,
  `/hu/…`), the market whose shops and currency it prices with
  (`TcgCheap.Sealed.Market`) and the language it renders in unless the
  visitor chose another (`TcgCheapWeb.Locale`). Region and language are
  separate: a Polish page can render in English. Each region is defined
  in its country's file (`TcgCheap.Country.region/0`).

  The region a request or LiveView renders is set once with `put/1` and read
  with `current/0`, as Gettext keeps the language: formatting
  (`TcgCheapWeb.Format`) and links (`TcgCheapWeb.Paths`) deep in shared
  components follow it without every caller passing it. Like the Gettext
  locale it is process state: spawned work must be given it explicitly.
  """

  alias TcgCheap.Countries
  alias TcgCheap.Sealed.{Market, Shops}
  alias TcgCheapWeb.Languages

  @enforce_keys [
    :code,
    :market,
    :currency_symbol,
    :language,
    :languages,
    :hreflang,
    :slugs,
    :pages,
    :country
  ]
  defstruct @enforce_keys ++ [visitors_from: [], whole_prices_from: nil]

  @typedoc """
  A region as `TcgCheap.Country.region/0` defines it, with its market and
  `country`, the module of its words and sentences (`TcgCheapWeb.RegionText`).
  `languages` are the ones its language menu lists first: its own, English,
  then those popular there that the guide renders.
  """
  @type t :: %__MODULE__{
          code: String.t(),
          market: Market.t(),
          currency_symbol: String.t(),
          language: String.t(),
          languages: [String.t()],
          hreflang: String.t(),
          slugs: %{products: String.t(), expansions: String.t(), cards: String.t()},
          pages: %{optional(atom()) => String.t()},
          country: module(),
          visitors_from: [String.t()],
          whole_prices_from: Decimal.t() | nil
        }

  @doc "Every region, Poland first."
  @spec all() :: [t()]
  def all do
    # Market.all/0 lists the same regions in the same order.
    for {region, market} <- Enum.zip(Countries.regions(), Market.all()) do
      %__MODULE__{
        code: region.code,
        market: market,
        currency_symbol: region.currency_symbol,
        language: region.language,
        languages:
          [region.language, "en" | region.popular_languages]
          |> Enum.uniq()
          |> Enum.filter(&(&1 in Languages.codes())),
        hreflang: region.hreflang,
        slugs: region.slugs,
        pages: region.pages,
        country: region.module,
        visitors_from: Map.get(region, :visitors_from, []),
        whole_prices_from: Map.get(region, :whole_prices_from)
      }
    end
  end

  @spec poland() :: t()
  def poland, do: hd(all())

  @spec fetch(String.t() | nil) :: {:ok, t()} | :error
  def fetch(code) do
    case Enum.find(all(), &(&1.code == code)) do
      nil -> :error
      region -> {:ok, region}
    end
  end

  @spec fetch!(String.t()) :: t()
  def fetch!(code) do
    {:ok, region} = fetch(code)
    region
  end

  @doc """
  The region for a visitor in a country (Cloudflare's `cf-ipcountry`): its
  own, else the one it is among the `visitors_from` of, else Poland's.
  """
  @spec for_country(String.t() | nil) :: t()
  def for_country(country),
    do:
      Enum.find(all(), &(&1.market.country == country)) ||
        Enum.find(all(), &(country in &1.visitors_from)) || poland()

  @doc "The languages the guide renders in (`TcgCheapWeb.Languages`)."
  @spec languages() :: [String.t()]
  def languages, do: Languages.codes()

  @doc "The language a visitor chose, if it is one of the guide's."
  @spec language(String.t() | nil) :: String.t() | nil
  def language(code), do: if(code in Languages.codes(), do: code)

  @doc "Whether the region prices with Poland's market, which every other part of the guide assumes."
  @spec poland?(t()) :: boolean()
  def poland?(%__MODULE__{code: code}), do: code == "pl"

  @doc """
  Whether the region's card pages show shops' offers and verdicts: shops
  sell singles in its market (`TcgCheap.Sealed.Shops.singles?/1`). Without
  them its card pages list every card with its Cardmarket trend alone.
  """
  @spec singles?(t()) :: boolean()
  def singles?(%__MODULE__{market: market}), do: Shops.singles?(market)

  @doc "Sets the region this process renders."
  @spec put(t()) :: t()
  def put(%__MODULE__{} = region) do
    Process.put(__MODULE__, region)
    region
  end

  @doc "The region this process renders; Poland's when none was set."
  @spec current() :: t()
  def current, do: Process.get(__MODULE__) || poland()
end
