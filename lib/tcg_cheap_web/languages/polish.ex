defmodule TcgCheapWeb.Languages.Polish do
  @moduledoc "Polish, the guide's default language (`TcgCheapWeb.Language`)."

  @behaviour TcgCheapWeb.Language

  # A no-break space keeps "17 lip" on one line.
  @nbsp " "
  @months ~w(stycznia lutego marca kwietnia maja czerwca lipca sierpnia września października listopada grudnia)
  @short_months ~w(sty lut mar kwi maj cze lip sie wrz paź lis gru)

  @impl true
  def code, do: "pl"

  @impl true
  def name, do: "Polski"

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
end
