defmodule TcgCheapWeb.Languages.Hungarian do
  @moduledoc "Hungarian (`TcgCheapWeb.Language`): the year and month come first."

  @behaviour TcgCheapWeb.Language

  @nbsp " "
  @months ~w(január február március április május június július augusztus szeptember október november december)
  @short_months ~w(jan. febr. márc. ápr. máj. jún. júl. aug. szept. okt. nov. dec.)

  @impl true
  def code, do: "hu"

  @impl true
  def name, do: "Magyar"

  @impl true
  def date(date), do: "#{date.year}. #{day_month(date)}"

  @impl true
  def day_month(date), do: "#{month(date)} #{date.day}."

  @impl true
  def days_in_month(from, to), do: "#{month(from)} #{from.day}–#{to.day}."

  @impl true
  def short_date(date), do: "#{Enum.at(@short_months, date.month - 1)}#{@nbsp}#{date.day}."

  @impl true
  def mid_sentence(name), do: String.downcase(name)

  @impl true
  def decimal_separator, do: ","

  defp month(date), do: Enum.at(@months, date.month - 1)
end
