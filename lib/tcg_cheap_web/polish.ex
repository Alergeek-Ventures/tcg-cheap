defmodule TcgCheapWeb.Polish do
  @moduledoc """
  Guide formatting: prices in the current region's currency
  (`TcgCheapWeb.Region.current/0`) and dates and counts in the page
  language. The name predates regions: Polish formatting is the default,
  złoty to the grosz ("1 299,99 zł"); forints are whole ("22 999 Ft").
  """
  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.PullRates.Rate
  alias TcgCheapWeb.Region

  # A no-break space keeps "1 299,99 zł" on one line.
  @nbsp "\u00A0"

  @months ~w(stycznia lutego marca kwietnia maja czerwca lipca sierpnia września października listopada grudnia)
  @hungarian_months ~w(január február március április május június július augusztus szeptember október november december)
  @hungarian_short_months ~w(jan. febr. márc. ápr. máj. jún. júl. aug. szept. okt. nov. dec.)

  @doc ~S(The current region's currency as its prices write it: "zł", "Ft".)
  @spec currency_symbol() :: String.t()
  def currency_symbol, do: symbol(currency())

  @doc ~S(A currency as prices write it: "zł" for "PLN", "Ft" for "HUF".)
  @spec currency_symbol(String.t()) :: String.t()
  def currency_symbol(currency), do: symbol(currency)

  defp currency, do: Region.current().market.currency

  defp symbol("PLN"), do: "zł"
  defp symbol("HUF"), do: "Ft"

  @doc ~S(Formats a price in the region's currency: "1 299,99 zł" with grosze, "22 999 Ft" in whole forints.)
  @spec price(Decimal.t()) :: String.t()
  def price(%Decimal{} = value), do: price(value, currency())

  defp price(value, "HUF"), do: zloty(value)

  defp price(value, currency) do
    rounded = Decimal.round(value, 2)
    [whole, fraction] = rounded |> Decimal.to_string(:normal) |> String.split(".")
    group(whole) <> "," <> fraction <> @nbsp <> symbol(currency)
  end

  @doc ~S'Formats a Cardmarket price in euro: "1 299,99 €".'
  @spec eur(Decimal.t()) :: String.t()
  def eur(%Decimal{} = value) do
    [whole, fraction] =
      value |> Decimal.round(2) |> Decimal.to_string(:normal) |> String.split(".")

    group(whole) <> "," <> fraction <> @nbsp <> "€"
  end

  @doc ~S'Formats an exchange rate: "4,2563".'
  @spec rate(Decimal.t()) :: String.t()
  def rate(%Decimal{} = value),
    do: value |> Decimal.round(4) |> Decimal.to_string(:normal) |> String.replace(".", ",")

  @doc ~S(Formats a whole amount of the region's currency: "1 299 zł", "22 999 Ft".)
  @spec zloty(integer() | Decimal.t()) :: String.t()
  def zloty(%Decimal{} = value), do: value |> Decimal.round(0) |> Decimal.to_integer() |> zloty()
  def zloty(value) when is_integer(value), do: number(value) <> @nbsp <> currency_symbol()

  @doc ~S'Whole units rounded up, for an upper bound: "do 4 zł" still holds for 3,40 zł.'
  @spec zloty_ceiling(Decimal.t()) :: String.t()
  def zloty_ceiling(%Decimal{} = value), do: value |> Decimal.round(0, :ceiling) |> zloty()

  @doc ~S'A rough amount: whole units, with grosze below 10 zł, where whole złoty would read "0 zł".'
  @spec rough_zloty(Decimal.t()) :: String.t()
  def rough_zloty(%Decimal{} = value),
    do: if(Decimal.lt?(value, 10), do: price(value), else: zloty(value))

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
    amount = value |> Decimal.div(step) |> Decimal.round(0) |> Decimal.mult(step) |> zloty()
    gettext("ok. %{amount}", amount: amount)
  end

  @doc "A localized number of packs."
  def packs(count),
    do: ngettext("%{packs} paczka", "%{packs} paczki", count, packs: number(count))

  @doc ~S'Formats a whole number with Polish digit grouping: "1 299".'
  @spec number(integer()) :: String.t()
  def number(value) when is_integer(value), do: group(Integer.to_string(value))

  @doc ~S'Formats a date in the page language: "17 lipca 2026", "17 July 2026", "2026. július 17.".'
  @spec date(Date.t()) :: String.t()
  def date(%Date{} = date) do
    case language() do
      "en" -> Calendar.strftime(date, "%d %B %Y") |> String.trim_leading("0")
      "hu" -> "#{date.year}. #{day_month(date)}"
      _pl -> "#{date.day} #{Enum.at(@months, date.month - 1)} #{date.year}"
    end
  end

  @doc """
  A sentence ending in a date, with one period: a Hungarian date ends with
  its own ("2026. november 13."), so a sentence that adds one after it would
  end in two. `GuideComponents.euro_rate_note/1` and the product's "on
  Cardmarket since" line rely on it.
  """
  @spec sentence(String.t()) :: String.t()
  def sentence(text), do: String.replace(text, ~r/(?<!\.)\.\.$/, ".")

  @doc ~S'A day and month: "6 listopada", "6 November", "november 6.".'
  @spec day_month(Date.t()) :: String.t()
  def day_month(%Date{} = date) do
    case language() do
      "en" -> Calendar.strftime(date, "%d %B") |> String.trim_leading("0")
      "hu" -> "#{Enum.at(@hungarian_months, date.month - 1)} #{date.day}."
      _pl -> "#{date.day} #{Enum.at(@months, date.month - 1)}"
    end
  end

  @doc ~S'The days a deal runs: "2–8 listopada", "30 października – 5 listopada", "od 17 sierpnia".'
  @spec days(Date.t(), Date.t() | nil) :: String.t()
  def days(%Date{} = from, nil), do: gettext("od %{day}", day: day_month(from))
  def days(%Date{} = day, day), do: day_month(day)

  def days(%Date{month: month, year: year} = from, %Date{month: month, year: year} = to) do
    # Hungarian puts the month first: "november 2–8."
    if language() == "hu",
      do: "#{Enum.at(@hungarian_months, month - 1)} #{from.day}–#{to.day}.",
      else: "#{from.day}–#{day_month(to)}"
  end

  def days(%Date{} = from, %Date{} = to), do: "#{day_month(from)} – #{day_month(to)}"

  @short_months ~w(sty lut mar kwi maj cze lip sie wrz paź lis gru)

  @doc ~S'A short date for chart axes: "17 lip", "17 Jul", "júl. 17.".'
  @spec short_date(Date.t()) :: String.t()
  def short_date(%Date{} = date) do
    case language() do
      "en" -> "#{date.day}#{@nbsp}#{Calendar.strftime(date, "%b")}"
      "hu" -> "#{Enum.at(@hungarian_short_months, date.month - 1)}#{@nbsp}#{date.day}."
      _pl -> "#{date.day}#{@nbsp}#{Enum.at(@short_months, date.month - 1)}"
    end
  end

  defp language, do: Gettext.get_locale(TcgCheapWeb.Gettext)

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
  @doc ~S'Polish plural form: plural(5, "produkt", "produkty", "produktów") == "5 produktów".'
  @spec plural(integer(), String.t(), String.t(), String.t()) :: String.t()
  def plural(count, "produkt", "produkty", "produktów"),
    do: ngettext("%{number} produkt", "%{number} produkty", count, number: number(count))

  def plural(count, "oferta", "oferty", "ofert"),
    do: ngettext("%{number} oferta", "%{number} oferty", count, number: number(count))

  def plural(count, "dnia", "dni", "dni"),
    do: ngettext("%{number} dnia", "%{number} dni", count, number: number(count))

  def plural(count, "karta", "karty", "kart"),
    do: ngettext("%{number} karta", "%{number} karty", count, number: number(count))

  def plural(count, "sklepie", "sklepach", "sklepach"),
    do: ngettext("%{number} sklepie", "%{number} sklepach", count, number: number(count))

  def plural(count, "booster", "boostery", "boosterów"),
    do: ngettext("%{number} booster", "%{number} boostery", count, number: number(count))

  def plural(count, "puszkę", "puszki", "puszek"),
    do: ngettext("%{number} puszkę", "%{number} puszki", count, number: number(count))

  def plural(count, "kolekcję", "kolekcje", "kolekcji"),
    do: ngettext("%{number} kolekcję", "%{number} kolekcje", count, number: number(count))

  def plural(count, one, few, many) do
    word =
      cond do
        count == 1 -> one
        rem(count, 10) in 2..4 and rem(count, 100) not in 12..14 -> few
        true -> many
      end

    "#{number(count)} #{word}"
  end

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

  defp decimal_separator, do: if(language() == "en", do: ".", else: ",")

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
      |> Enum.map_join(@nbsp, &Enum.join/1)
      |> String.reverse()

    sign <> grouped
  end
end
