defmodule TcgCheapWeb.Format do
  @moduledoc """
  Guide formatting: prices in the current region's currency
  (`TcgCheapWeb.Region.current/0`, its symbol and decimals) and dates,
  numbers and counted phrases in the page language (`TcgCheapWeb.Language`).
  Złoty are written to the grosz ("1 299,99 zł"); forints are whole
  ("22 999 Ft"), and so are kronor from 10 kr and whole amounts below it
  ("999 kr", "8 kr", but "3,50 kr"); koruna and forint amounts below one unit
  keep their hundredths ("0,30 Kč"). Euro always keeps its cents, a delivery
  of "20,00 €" included. The separators are the page language's, so the same
  price reads "1,299.99 zł" in English.
  """
  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Cards.PullRates.Rate
  alias TcgCheap.Sealed.Market
  alias TcgCheapWeb.{Languages, Region}

  # A no-break space keeps "1 299,99 zł" on one line.
  @nbsp "\u00A0"

  @doc ~S(The current region's currency as its prices write it: "zł", "Ft".)
  @spec currency_symbol() :: String.t()
  def currency_symbol, do: Region.current().currency_symbol

  @doc ~S(A region's currency as prices write it: "zł" for "PLN", "Ft" for "HUF".)
  @spec currency_symbol(String.t()) :: String.t()
  def currency_symbol(currency), do: symbol(currency)

  defp currency, do: Region.current().market.currency

  defp symbol(currency),
    do: Enum.find(Region.all(), &(&1.market.currency == currency)).currency_symbol

  @doc ~S(Formats a price in the region's currency: "1 299,99 zł" with grosze, "22 999 Ft" in whole forints.)
  @spec price(Decimal.t()) :: String.t()
  def price(%Decimal{} = value), do: price(value, Region.current())

  # Below one whole unit a price keeps its hundredths, so a cheap card never
  # reads "0 Kč" or "0 Ft"; from one unit up it is whole.
  defp price(value, %Region{market: %{decimals: 0}} = region) do
    # Rounded first: 0,996 is "1 Kč", not "1,00 Kč".
    hundredths = Decimal.round(value, 2)

    if Decimal.positive?(hundredths) and Decimal.lt?(hundredths, 1),
      do: fractional_price(value, %{region | market: %{region.market | decimals: 2}}),
      else: whole_price(value)
  end

  defp price(value, %Region{whole_prices_from: %Decimal{} = from} = region) do
    # Rounded first: 9,996 is "10 kr", not "10,00 kr". Below the limit a
    # whole amount stays whole too: "8 kr" beside "12 kr", but "3,50 kr".
    rounded = Decimal.round(value, region.market.decimals)

    if Decimal.lt?(rounded, from) and not Decimal.integer?(rounded),
      do: fractional_price(value, region),
      else: whole_price(value)
  end

  defp price(value, region), do: fractional_price(value, region)

  defp fractional_price(value, region) do
    rounded = Decimal.round(value, region.market.decimals)
    [whole, fraction] = rounded |> Decimal.to_string(:normal) |> String.split(".")
    with_currency(group(whole) <> decimal_separator() <> fraction, region.currency_symbol)
  end

  @doc """
  A wording recorded with the catalogue's facts (a contents item's name, a
  retail deal's note) in the page language. Such texts are data, so their
  translations are the hand-kept `catalogue` Gettext domain
  (`priv/gettext/catalogue.pot`); one without an entry, as a card's or a
  set's name, is shown as recorded.
  """
  @spec recorded(String.t()) :: String.t()
  def recorded(text) when is_binary(text),
    do: Gettext.dgettext(TcgCheapWeb.Gettext, "catalogue", text)

  @doc ~S'Prices from–to: "129 zł–139 zł", one amount ("129 zł") when both ends read the same.'
  @spec price_range(Decimal.t(), Decimal.t()) :: String.t()
  def price_range(low, high) do
    case {price(low), price(high)} do
      {same, same} -> same
      {low, high} -> low <> "–" <> high
    end
  end

  @doc ~S'Formats a Cardmarket price in euro: "1 299,99 €".'
  @spec eur(Decimal.t()) :: String.t()
  def eur(%Decimal{} = value) do
    [whole, fraction] =
      value |> Decimal.round(2) |> Decimal.to_string(:normal) |> String.split(".")

    with_currency(group(whole) <> decimal_separator() <> fraction, "€")
  end

  @doc ~S'Formats an exchange rate, to four places unless given: "4,2563", "365,64".'
  @spec rate(Decimal.t(), non_neg_integer()) :: String.t()
  def rate(%Decimal{} = value, places \\ 4),
    do:
      value
      |> Decimal.round(places)
      |> Decimal.to_string(:normal)
      |> String.replace(".", decimal_separator())

  @doc ~S(Formats a whole amount of the region's currency: "1 299 zł", "22 999 Ft".)
  @spec whole_price(integer() | Decimal.t()) :: String.t()
  def whole_price(%Decimal{} = value),
    do: value |> Decimal.round(0) |> Decimal.to_integer() |> whole_price()

  def whole_price(value) when is_integer(value),
    do: with_currency(number(value), currency_symbol())

  @doc ~S'Whole amounts from–to with one currency symbol: "9 570–12 228 zł", "€ 9.570–12.228".'
  @spec whole_price_range(integer(), integer()) :: String.t()
  def whole_price_range(low, high) when is_integer(low) and is_integer(high),
    do: with_currency(number(low) <> "–" <> number(high), currency_symbol())

  @doc ~S'The lower bound of a range whose upper bound is a whole price: bare where the symbol follows the amount ("od 10 do 20 zł"), priced where it leads ("van € 10 tot € 20").'
  @spec range_start(integer()) :: String.t()
  def range_start(value) when is_integer(value),
    do: if(language().currency_first?(), do: whole_price(value), else: number(value))

  @doc ~S'A verdict limit or reference: whole currency units, or decimals for a market with a fractional step.'
  @spec limit_price(integer() | Decimal.t()) :: String.t()
  def limit_price(value) do
    case Market.limit_step(Region.current().market) do
      1 ->
        # A Cardmarket trend below one unit keeps its hundredths, as `price/1` does.
        if is_struct(value, Decimal), do: price(value), else: whole_price(value)

      %Decimal{} ->
        price(value)
    end
  end

  @doc ~S'Whole units rounded up, for an upper bound: "do 4 zł" still holds for 3,40 zł.'
  @spec whole_price_ceiling(Decimal.t()) :: String.t()
  def whole_price_ceiling(%Decimal{} = value),
    do: value |> Decimal.round(0, :ceiling) |> whole_price()

  @doc ~S'A rough amount: whole units, with the fraction below 10 zł, where whole złoty would read "0 zł".'
  @spec rough_price(Decimal.t()) :: String.t()
  def rough_price(%Decimal{} = value),
    do: if(Decimal.lt?(value, 10), do: price(value), else: whole_price(value))

  @doc ~S'A shop price: whole units when it has no fraction, else `price/1`: "89 zł", "89,99 zł". Euro always keeps its cents: "20,00 €".'
  @spec shop_price(Decimal.t()) :: String.t()
  def shop_price(%Decimal{} = value),
    do:
      if(Decimal.integer?(value) and currency() != "EUR",
        do: whole_price(value),
        else: price(value)
      )

  @doc "A rounded estimate of a pack-opening cost."
  def about(%Decimal{} = value), do: about(value, currency())

  defp about(value, currency) when currency != "PLN" do
    cond do
      Decimal.gte?(value, 1_000_000) ->
        gettext("ok. %{amount} mln %{currency}",
          amount: value |> Decimal.div(1_000_000) |> Decimal.round(1) |> decimal(),
          currency: symbol(currency)
        )

      Decimal.gte?(value, 10_000) ->
        gettext("ok. %{amount} tys. %{currency}",
          amount: value |> Decimal.div(1_000) |> Decimal.round(0) |> decimal(),
          currency: symbol(currency)
        )

      true ->
        about_rounded(value)
    end
  end

  defp about(value, _pln) do
    cond do
      Decimal.gte?(value, 1_000_000) ->
        gettext("ok. %{amount} mln zł",
          amount: value |> Decimal.div(1_000_000) |> Decimal.round(1) |> decimal()
        )

      Decimal.gte?(value, 10_000) ->
        gettext("ok. %{amount} tys. zł",
          amount: value |> Decimal.div(1_000) |> Decimal.round(0) |> decimal()
        )

      true ->
        about_rounded(value)
    end
  end

  defp about_rounded(value) do
    step = if Decimal.gte?(value, 1_000), do: 100, else: 10
    amount = value |> Decimal.div(step) |> Decimal.round(0) |> Decimal.mult(step) |> whole_price()
    gettext("ok. %{amount}", amount: amount)
  end

  @doc "A localized number of packs."
  def packs(count),
    do: ngettext("%{packs} paczka", "%{packs} paczki", count, packs: number(count))

  @doc ~S'Formats a whole number with no-break digit grouping: "1 299".'
  @spec number(integer()) :: String.t()
  def number(value) when is_integer(value), do: group(Integer.to_string(value))

  @doc ~S'Formats a date in the page language: "17 lipca 2026", "17 July 2026", "2026. július 17.".'
  @spec date(Date.t()) :: String.t()
  def date(%Date{} = date), do: language().date(date)

  @doc """
  A sentence with a date before its full stop, with one period: a Hungarian
  or Croatian date ends with its own ("2026. november 13."), so a sentence
  that adds one after it would show two, at its end or before the next
  sentence. `VerdictComponents.euro_rate_note/1`, the product's "on
  Cardmarket since" line and the pull-rate notes rely on it.
  """
  @spec sentence(String.t()) :: String.t()
  def sentence(text), do: String.replace(text, ~r/(?<!\.)\.\.(?!\.)/, ".")

  @doc ~S'A day and month: "6 listopada", "6 November", "november 6.".'
  @spec day_month(Date.t()) :: String.t()
  def day_month(%Date{} = date), do: language().day_month(date)

  @doc ~S'The days a deal runs: "2–8 listopada", "30 października – 5 listopada", "od 17 sierpnia".'
  @spec days(Date.t(), Date.t() | nil) :: String.t()
  def days(%Date{} = from, nil), do: gettext("od %{day}", day: day_month(from))
  def days(%Date{} = day, day), do: day_month(day)

  def days(%Date{month: month, year: year} = from, %Date{month: month, year: year} = to),
    do: language().days_in_month(from, to)

  def days(%Date{} = from, %Date{} = to), do: "#{day_month(from)} – #{day_month(to)}"

  @doc ~S'A short date for chart axes: "17 lip", "17 Jul", "júl. 17.".'
  @spec short_date(Date.t()) :: String.t()
  def short_date(%Date{} = date), do: language().short_date(date)

  defp language, do: Languages.get(Gettext.get_locale(TcgCheapWeb.Gettext))

  @doc ~S'How long ago a day was: "dziś", "wczoraj", "3 dni temu".'
  @spec days_ago(Date.t(), Date.t()) :: String.t()
  def days_ago(%Date{} = date, %Date{} = today) do
    case Date.diff(today, date) do
      days when days <= 0 -> gettext("dziś")
      1 -> gettext("wczoraj")
      days -> ngettext("%{count} dzień temu", "%{count} dni temu", days)
    end
  end

  @doc ~S'Days until a coming day: "dziś", "jutro", "za 4 dni".'
  @spec days_until(non_neg_integer()) :: String.t()
  def days_until(0), do: gettext("dziś")
  def days_until(1), do: gettext("jutro")
  def days_until(days), do: ngettext("za %{count} dzień", "za %{count} dni", days)

  # Gettext binds `count` to the raw integer, so the grouped number ("1 299")
  # goes in as `number`; any counted phrase with a grouped number needs it.
  @doc ~S'The count with its noun: "1 produkt", "5 produktów".'
  @spec products(integer()) :: String.t()
  def products(count),
    do: ngettext("%{number} produkt", "%{number} produkty", count, number: number(count))

  @doc ~S'The count with its noun: "1 oferta", "5 ofert".'
  @spec offers(integer()) :: String.t()
  def offers(count),
    do: ngettext("%{number} oferta", "%{number} oferty", count, number: number(count))

  @doc ~S'The count with its noun: "1 dnia", "5 dni".'
  @spec days(integer()) :: String.t()
  def days(count),
    do: ngettext("%{number} dnia", "%{number} dni", count, number: number(count))

  @doc ~S'The count with its noun: "1 karta", "5 kart".'
  @spec cards(integer()) :: String.t()
  def cards(count),
    do: ngettext("%{number} karta", "%{number} karty", count, number: number(count))

  @doc ~S'The count with its noun: "1 sklepie", "5 sklepach"; follows "w".'
  @spec in_shops(integer()) :: String.t()
  def in_shops(count),
    do: ngettext("%{number} sklepie", "%{number} sklepach", count, number: number(count))

  @doc """
  The count with its noun after "at least": in the genitive in Polish ("co
  najmniej 3 sklepów"), in the form the sentence needs elsewhere ("alespoň 3
  obchody").
  """
  @spec shops(integer()) :: String.t()
  def shops(count),
    do: ngettext("%{number} sklepu", "%{number} sklepów", count, number: number(count))

  @doc ~S'The count with its noun: "1 booster", "5 boosterów".'
  @spec boosters(integer()) :: String.t()
  def boosters(count),
    do: ngettext("%{number} booster", "%{number} boostery", count, number: number(count))

  @doc ~S'The count with its noun: "1 puszkę", "5 puszek".'
  @spec tins(integer()) :: String.t()
  def tins(count),
    do: ngettext("%{number} puszkę", "%{number} puszki", count, number: number(count))

  @doc ~S'The count with its noun: "1 kolekcję", "5 kolekcji".'
  @spec collections(integer()) :: String.t()
  def collections(count),
    do: ngettext("%{number} kolekcję", "%{number} kolekcje", count, number: number(count))

  @doc ~S'How often a pull rate hits, in the page language: "1 na 5 paczek", "3 w każdej paczce".'
  @spec odds(Rate.t()) :: String.t()
  def odds(rate) do
    case Rate.odds(rate) do
      {:one_in, packs, _about?} ->
        one_in(packs)

      {:per_pack, cards} ->
        gettext("%{count} w każdej paczce", count: cards)

      {:hits, _percent, hits, packs} ->
        gettext("%{hits} z %{packs} paczek", hits: decimal(hits), packs: decimal(packs))
    end
  end

  # Whole packs from 10 up ("1 na 58 paczek"), one decimal below ("1 na 2,5
  # paczki"). No "ok.": the note above the table says these are estimates.
  defp one_in(packs) do
    packs = Decimal.round(packs, if(Decimal.lt?(packs, 10), do: 1, else: 0))

    if Decimal.integer?(packs) do
      count = Decimal.to_integer(packs)
      ngettext("1 na %{number} paczkę", "1 na %{number} paczki", count, number: number(count))
    else
      gettext("1 na %{packs} paczki", packs: decimal(packs))
    end
  end

  @doc ~S'A decimal in the page language, grouped: "1,3" in Polish, "1.3" in English, "1 081".'
  @spec decimal(Decimal.t()) :: String.t()
  def decimal(value) do
    case value |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.split(".") do
      [whole] ->
        number(String.to_integer(whole))

      [whole, fraction] ->
        number(String.to_integer(whole)) <> decimal_separator() <> fraction
    end
  end

  defp decimal_separator, do: language().decimal_separator()

  # The currency after the amount ("1 299,99 zł") or, as Dutch writes it, before it ("€ 1.299,99").
  defp with_currency(amount, symbol) do
    if language().currency_first?(),
      do: symbol <> @nbsp <> amount,
      else: amount <> @nbsp <> symbol
  end

  defp group(digits) do
    {sign, digits} =
      case digits do
        "-" <> rest -> {"-", rest}
        rest -> {"", rest}
      end

    grouped =
      digits
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(language().thousands_separator(), &Enum.join/1)
      |> String.reverse()

    sign <> grouped
  end
end
