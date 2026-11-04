defmodule TcgCheapWeb.Polish do
  @moduledoc "Guide formatting: Polish PLN prices and locale-aware dates and counts."
  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.PullRates.Rate

  # A no-break space keeps "1 299,99 zł" on one line.
  @nbsp "\u00A0"

  @months ~w(stycznia lutego marca kwietnia maja czerwca lipca sierpnia września października listopada grudnia)

  @doc ~S'Formats a price in PLN with grosze: "1 299,99 zł".'
  @spec price(Decimal.t()) :: String.t()
  def price(%Decimal{} = value) do
    rounded = Decimal.round(value, 2)
    [whole, fraction] = rounded |> Decimal.to_string(:normal) |> String.split(".")
    group(whole) <> "," <> fraction <> @nbsp <> "zł"
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

  @doc ~S'Formats a whole number of złoty: "1 299 zł".'
  @spec zloty(integer() | Decimal.t()) :: String.t()
  def zloty(%Decimal{} = value), do: value |> Decimal.round(0) |> Decimal.to_integer() |> zloty()
  def zloty(value) when is_integer(value), do: number(value) <> @nbsp <> "zł"

  @doc ~S'A rough amount: whole złoty, with grosze below 10 zł, where whole złoty would read "0 zł".'
  @spec rough_zloty(Decimal.t()) :: String.t()
  def rough_zloty(%Decimal{} = value),
    do: if(Decimal.lt?(value, 10), do: price(value), else: zloty(value))

  @doc "A rounded estimate of a pack-opening cost."
  def about(%Decimal{} = value) do
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
        step = if Decimal.gte?(value, 1_000), do: 100, else: 10
        amount = value |> Decimal.div(step) |> Decimal.round(0) |> Decimal.mult(step) |> zloty()
        gettext("ok. %{amount}", amount: amount)
    end
  end

  @doc "A localized number of packs."
  def packs(count),
    do: ngettext("%{packs} paczka", "%{packs} paczki", count, packs: number(count))

  @doc ~S'Formats a whole number with Polish digit grouping: "1 299".'
  @spec number(integer()) :: String.t()
  def number(value) when is_integer(value), do: group(Integer.to_string(value))

  @doc ~S'Formats a date: "17 lipca 2026".'
  @spec date(Date.t()) :: String.t()
  def date(%Date{} = date) do
    if Gettext.get_locale(TcgCheapWeb.Gettext) == "en",
      do: Calendar.strftime(date, "%d %B %Y") |> String.trim_leading("0"),
      else: "#{date.day} #{Enum.at(@months, date.month - 1)} #{date.year}"
  end

  @doc ~S'A day and month: "6 listopada".'
  @spec day_month(Date.t()) :: String.t()
  def day_month(%Date{} = date) do
    if Gettext.get_locale(TcgCheapWeb.Gettext) == "en",
      do: Calendar.strftime(date, "%d %B") |> String.trim_leading("0"),
      else: "#{date.day} #{Enum.at(@months, date.month - 1)}"
  end

  @short_months ~w(sty lut mar kwi maj cze lip sie wrz paź lis gru)

  @doc ~S'A short date for chart axes: "17 lip".'
  @spec short_date(Date.t()) :: String.t()
  def short_date(%Date{} = date) do
    month =
      if Gettext.get_locale(TcgCheapWeb.Gettext) == "en",
        do: Calendar.strftime(date, "%b"),
        else: Enum.at(@short_months, date.month - 1)

    "#{date.day}#{@nbsp}#{month}"
  end

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

  @doc ~S'Polish plural form: plural(5, "produkt", "produkty", "produktów") == "5 produktów".'
  @spec plural(integer(), String.t(), String.t(), String.t()) :: String.t()
  def plural(count, "produkt", "produkty", "produktów"),
    do: ngettext("%{count} produkt", "%{count} produkty", count, count: number(count))

  def plural(count, "oferta", "oferty", "ofert"),
    do: ngettext("%{count} oferta", "%{count} oferty", count, count: number(count))

  def plural(count, "dnia", "dni", "dni"),
    do: ngettext("%{count} dnia", "%{count} dni", count, count: number(count))

  def plural(count, "karta", "karty", "kart"),
    do: ngettext("%{count} karta", "%{count} karty", count, count: number(count))

  def plural(count, "sklepie", "sklepach", "sklepach"),
    do: ngettext("%{count} sklepie", "%{count} sklepach", count, count: number(count))

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
      ngettext("1 na %{count} paczkę", "1 na %{count} paczki", count, count: number(count))
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

  defp decimal_separator,
    do: if(Gettext.get_locale(TcgCheapWeb.Gettext) == "en", do: ".", else: ",")

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
