defmodule TcgCheapWeb.Languages.Croatian do
  @moduledoc """
  Croatian (`TcgCheapWeb.Language`): an ordinal day with its period, then the
  month in the genitive, lower case ("14. studenoga 2026."), as CLDR writes it.
  """

  @behaviour TcgCheapWeb.Language

  @nbsp " "
  @months ~w(siječnja veljače ožujka travnja svibnja lipnja srpnja kolovoza rujna listopada studenoga prosinca)
  @short_months ~w(sij velj ožu tra svi lip srp kol ruj lis stu pro)

  @impl true
  def code, do: "hr"

  @impl true
  def name, do: "Hrvatski"

  @impl true
  def date(date), do: "#{day_month(date)} #{date.year}."

  @impl true
  def day_month(date), do: "#{date.day}.#{@nbsp}#{month(date)}"

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
  def thousands_separator, do: @nbsp

  defp month(date), do: Enum.at(@months, date.month - 1)
end
