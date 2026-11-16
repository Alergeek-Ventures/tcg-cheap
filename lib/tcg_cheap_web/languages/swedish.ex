defmodule TcgCheapWeb.Languages.Swedish do
  @moduledoc ~S{Swedish (`TcgCheapWeb.Language`): "16 februari 2026", months in lower case.}

  @behaviour TcgCheapWeb.Language

  @nbsp " "
  @months ~w(januari februari mars april maj juni juli augusti september oktober november december)
  @short_months ~w(jan feb mar apr maj jun jul aug sep okt nov dec)

  @impl true
  def code, do: "sv"

  @impl true
  def name, do: "Svenska"

  @impl true
  def date(date), do: "#{day_month(date)} #{date.year}"

  @impl true
  def day_month(date), do: "#{date.day} #{Enum.at(@months, date.month - 1)}"

  @impl true
  def days_in_month(from, to), do: "#{from.day}–#{day_month(to)}"

  @impl true
  def short_date(date), do: "#{date.day}#{@nbsp}#{Enum.at(@short_months, date.month - 1)}"

  @impl true
  def mid_sentence(name), do: String.downcase(name)

  @impl true
  def decimal_separator, do: ","

  @impl true
  def currency_first?, do: false

  @impl true
  def thousands_separator, do: @nbsp
end
