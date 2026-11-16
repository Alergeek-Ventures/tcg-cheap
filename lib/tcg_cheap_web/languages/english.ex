defmodule TcgCheapWeb.Languages.English do
  @moduledoc "English (`TcgCheapWeb.Language`)."

  @behaviour TcgCheapWeb.Language

  @nbsp " "

  @impl true
  def code, do: "en"

  @impl true
  def name, do: "English"

  @impl true
  def date(date), do: Calendar.strftime(date, "%d %B %Y") |> String.trim_leading("0")

  @impl true
  def day_month(date), do: Calendar.strftime(date, "%d %B") |> String.trim_leading("0")

  @impl true
  def days_in_month(from, to), do: "#{from.day}–#{day_month(to)}"

  @impl true
  def short_date(date), do: "#{date.day}#{@nbsp}#{Calendar.strftime(date, "%b")}"

  @impl true
  def mid_sentence(name), do: name

  @impl true
  def decimal_separator, do: "."

  @impl true
  def currency_first?, do: false

  @impl true
  def thousands_separator, do: @nbsp
end
