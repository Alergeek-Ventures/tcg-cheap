defmodule TcgCheapWeb.Polish do
  @moduledoc "Guide formatting: Polish PLN prices and locale-aware dates and counts."
  use Gettext, backend: TcgCheapWeb.Gettext

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

  @doc ~S'Polish plural form: plural(5, "produkt", "produkty", "produktów") == "5 produktów".'
  @spec plural(integer(), String.t(), String.t(), String.t()) :: String.t()
  def plural(count, "produkt", "produkty", "produktów"),
    do: ngettext("%{count} produkt", "%{count} produkty", count, count: number(count))

  def plural(count, "oferta", "oferty", "ofert"),
    do: ngettext("%{count} oferta", "%{count} oferty", count, count: number(count))

  def plural(count, "dnia", "dni", "dni"),
    do: ngettext("%{count} dnia", "%{count} dni", count, count: number(count))

  def plural(count, one, few, many) do
    word =
      cond do
        count == 1 -> one
        rem(count, 10) in 2..4 and rem(count, 100) not in 12..14 -> few
        true -> many
      end

    "#{number(count)} #{word}"
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
      |> Enum.map_join(@nbsp, &Enum.join/1)
      |> String.reverse()

    sign <> grouped
  end
end
