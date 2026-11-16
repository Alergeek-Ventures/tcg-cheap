defmodule TcgCheapWeb.Languages.Dutch do
  @moduledoc """
  Dutch (`TcgCheapWeb.Language`): the day, the month in lower case and the
  year ("16 november 2026"), as the Dutch shops and price sites write dates.
  """

  @behaviour TcgCheapWeb.Language

  @nbsp " "
  @months ~w(januari februari maart april mei juni juli augustus september oktober november december)
  @short_months ~w(jan feb mrt apr mei jun jul aug sep okt nov dec)

  @impl true
  def code, do: "nl"

  @impl true
  def name, do: "Nederlands"

  @impl true
  def date(date), do: "#{day_month(date)} #{date.year}"

  @impl true
  def day_month(date), do: "#{date.day} #{Enum.at(@months, date.month - 1)}"

  @impl true
  def days_in_month(from, to), do: "#{from.day}–#{day_month(to)}"

  @impl true
  def short_date(date), do: "#{date.day}#{@nbsp}#{Enum.at(@short_months, date.month - 1)}"

  @impl true
  # Dutch writes language names with a capital letter mid-sentence too ("taal: Engels").
  def mid_sentence(name), do: name

  @impl true
  def decimal_separator, do: ","

  @impl true
  def currency_first?, do: true

  @impl true
  def thousands_separator, do: "."
end
