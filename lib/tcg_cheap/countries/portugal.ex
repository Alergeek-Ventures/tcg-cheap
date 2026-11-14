defmodule TcgCheap.Countries.Portugal do
  @moduledoc "Portugal: shops there sell to the guide's regions (`TcgCheap.Country`)."

  @behaviour TcgCheap.Country

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl true
  def code, do: "PT"

  @impl true
  def shipped_from, do: dgettext("portugal", "wysyłka z Portugalii")

  @impl true
  def delivered_from, do: dgettext("portugal", "z wysyłką z Portugalii")

  @impl true
  def region, do: nil
end
