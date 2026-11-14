defmodule TcgCheap.Countries.Czechia do
  @moduledoc "Czechia: shops there sell to the guide's regions (`TcgCheap.Country`)."

  @behaviour TcgCheap.Country

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl true
  def code, do: "CZ"

  @impl true
  def shipped_from, do: dgettext("czechia", "wysyłka z Czech")

  @impl true
  def delivered_from, do: dgettext("czechia", "z wysyłką z Czech")

  @impl true
  def region, do: nil
end
