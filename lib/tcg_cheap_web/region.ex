defmodule TcgCheapWeb.Region do
  @moduledoc """
  The part of the guide a page belongs to: its first path segment (`/pl/…`,
  `/hu/…`), the market whose shops and currency it prices with
  (`TcgCheap.Sealed.Market`) and the language it renders in unless the
  visitor chose another (`TcgCheapWeb.Locale`). Region and language are
  separate: a Polish page can render in English.

  The region a request or LiveView renders is set once with `put/1` and read
  with `current/0`, as Gettext keeps the language: formatting
  (`TcgCheapWeb.Polish`) and links (`TcgCheapWeb.Paths`) deep in shared
  components follow it without every caller passing it. Like the Gettext
  locale it is process state: spawned work must be given it explicitly.
  """

  alias TcgCheap.Sealed.Market

  @enforce_keys [:code, :market, :language, :hreflang, :name]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          code: String.t(),
          market: Market.t(),
          language: String.t(),
          hreflang: String.t(),
          name: String.t()
        }

  @languages ~w(pl en hu)

  @doc "Every region, Poland first."
  @spec all() :: [t()]
  def all, do: [poland(), hungary()]

  @spec poland() :: t()
  def poland,
    do: %__MODULE__{
      code: "pl",
      market: Market.poland(),
      language: "pl",
      hreflang: "pl-PL",
      name: "Polska"
    }

  defp hungary do
    {:ok, market} = Market.fetch("hu")

    %__MODULE__{
      code: "hu",
      market: market,
      language: "hu",
      hreflang: "hu-HU",
      name: "Magyarország"
    }
  end

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

  @doc "The region for a visitor in a country (Cloudflare's `cf-ipcountry`): Hungary's, else Poland's."
  @spec for_country(String.t() | nil) :: t()
  def for_country("HU"), do: hungary()
  def for_country(_country), do: poland()

  @doc "The languages the guide renders in."
  @spec languages() :: [String.t()]
  def languages, do: @languages

  @doc "The language a visitor chose, if it is one of the guide's."
  @spec language(String.t() | nil) :: String.t() | nil
  def language(code) when code in @languages, do: code
  def language(_code), do: nil

  @doc "Whether the region prices with Poland's market, which every other part of the guide assumes."
  @spec poland?(t()) :: boolean()
  def poland?(%__MODULE__{code: code}), do: code == "pl"

  @doc "Sets the region this process renders, with its market's PLN rate for `from_pln/1`."
  @spec put(t()) :: t()
  def put(%__MODULE__{} = region) do
    Process.put(__MODULE__, region)
    Process.delete({__MODULE__, :pln_rate})
    region
  end

  @doc "The region this process renders; Poland's when none was set."
  @spec current() :: t()
  def current, do: Process.get(__MODULE__) || poland()

  @doc """
  A PLN amount in the current region's currency, at the latest NBP rate no
  older than a week (`Market.pln_rate/2`), rounded as that currency is; nil
  when that rate is unknown. Only for references with no market of their
  own yet, such as Cardmarket trends of single cards: a Polish shop's price
  converted would be a price no shop in the region asks.
  """
  @spec from_pln(Decimal.t() | nil) :: Decimal.t() | nil
  def from_pln(nil), do: nil

  def from_pln(%Decimal{} = amount) do
    %{market: market} = current()

    case pln_rate(market) do
      nil -> nil
      rate -> amount |> Decimal.div(rate) |> Market.rounded(market)
    end
  end

  defp pln_rate(%Market{currency: "PLN"}), do: Decimal.new(1)

  # Read once per process: a page converts many cards.
  defp pln_rate(market) do
    case Process.get({__MODULE__, :pln_rate}) do
      {currency, rate} when currency == market.currency ->
        rate

      _unread ->
        rate =
          case Market.pln_rate(market.currency, Date.utc_today()) do
            {:ok, %{rate: rate}} -> rate
            {:error, _reason} -> nil
          end

        Process.put({__MODULE__, :pln_rate}, {market.currency, rate})
        rate
    end
  end
end
