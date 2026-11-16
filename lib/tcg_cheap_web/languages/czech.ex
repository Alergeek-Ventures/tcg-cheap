defmodule TcgCheapWeb.Languages.Czech do
  @moduledoc "Czech (`TcgCheapWeb.Language`): numeric dates with spaced full stops."

  @behaviour TcgCheapWeb.Language

  @nbsp " "

  @impl true
  def code, do: "cs"

  @impl true
  def name, do: "Čeština"

  @impl true
  def date(date), do: "#{day_month(date)} #{date.year}"

  @impl true
  def day_month(date), do: "#{date.day}. #{date.month}."

  @impl true
  def days_in_month(from, to), do: "#{from.day}.–#{to.day}. #{from.month}."

  @impl true
  def short_date(date), do: "#{date.day}.#{@nbsp}#{date.month}."

  @impl true
  def mid_sentence(name), do: String.downcase(name)

  @impl true
  def decimal_separator, do: ","

  @impl true
  def currency_first?, do: false

  @impl true
  # Czech groups thousands with a no-break space: "1 299 Kč".
  def thousands_separator, do: @nbsp
end
