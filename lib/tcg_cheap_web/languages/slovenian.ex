defmodule TcgCheapWeb.Languages.Slovenian do
  @moduledoc """
  Slovenian (`TcgCheapWeb.Language`): an ordinal day with its period, then the
  month in the genitive, lower case ("15. novembra 2026"), as CLDR writes it.
  """

  @behaviour TcgCheapWeb.Language

  # A no-break space keeps "17. nov." on one line.
  @nbsp " "
  @months ~w(januarja februarja marca aprila maja junija julija avgusta septembra oktobra novembra decembra)
  @short_months ~w(jan. feb. mar. apr. maj jun. jul. avg. sep. okt. nov. dec.)

  @impl true
  def code, do: "sl"

  @impl true
  def name, do: "Slovenščina"

  @impl true
  def date(date), do: "#{day_month(date)} #{date.year}"

  @impl true
  def day_month(date), do: "#{date.day}. #{month(date)}"

  @impl true
  def days_in_month(from, to), do: "#{from.day}.–#{day_month(to)}"

  @impl true
  def short_date(date), do: "#{date.day}.#{@nbsp}#{Enum.at(@short_months, date.month - 1)}"

  @impl true
  def mid_sentence(name), do: String.downcase(name)

  @impl true
  def decimal_separator, do: ","

  @impl true
  def currency_first?, do: false

  @impl true
  # Slovenian shops group thousands with a period: "1.299,00 €".
  def thousands_separator, do: "."

  defp month(date), do: Enum.at(@months, date.month - 1)
end
