defmodule TcgCheap.Countries.Belgium do
  @moduledoc "Belgium: shops there sell to the guide's regions (`TcgCheap.Country`)."

  @behaviour TcgCheap.Country

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl true
  def code, do: "BE"

  @impl true
  def shipped_from, do: dgettext("belgium", "wysyłka z Belgii")

  @impl true
  def delivered_from, do: dgettext("belgium", "z wysyłką z Belgii")

  @impl true
  def region, do: nil
end
