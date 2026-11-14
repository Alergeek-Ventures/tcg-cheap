defmodule TcgCheap.Countries.UnitedKingdom do
  @moduledoc "The United Kingdom: shops there sell to the guide's regions (`TcgCheap.Country`)."

  @behaviour TcgCheap.Country

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl true
  def code, do: "GB"

  @impl true
  def shipped_from, do: dgettext("united_kingdom", "wysyłka z Wielkiej Brytanii")

  @impl true
  def delivered_from, do: dgettext("united_kingdom", "z wysyłką z Wielkiej Brytanii")

  @impl true
  def region, do: nil
end
