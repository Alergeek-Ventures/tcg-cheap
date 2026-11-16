defmodule TcgCheapWeb.Languages.Portuguese do
  @moduledoc ~S{European Portuguese (`TcgCheapWeb.Language`): "14 de novembro de 2026".}

  @behaviour TcgCheapWeb.Language

  @nbsp " "
  @months ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)
  @short_months ~w(jan fev mar abr mai jun jul ago set out nov dez)

  @impl true
  def code, do: "pt"

  @impl true
  def name, do: "Português (Portugal)"

  @impl true
  def date(date), do: "#{day_month(date)} de #{date.year}"

  @impl true
  def day_month(date), do: "#{date.day} de #{Enum.at(@months, date.month - 1)}"

  @impl true
  def days_in_month(from, to), do: "#{from.day}–#{day_month(to)}"

  @impl true
  def short_date(date), do: "#{date.day}#{@nbsp}#{Enum.at(@short_months, date.month - 1)}"

  @impl true
  def mid_sentence(name), do: name

  @impl true
  def decimal_separator, do: ","
end
