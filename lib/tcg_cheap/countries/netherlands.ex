defmodule TcgCheap.Countries.Netherlands do
  @moduledoc "The Netherlands: shops there sell to the guide's regions (`TcgCheap.Country`)."

  @behaviour TcgCheap.Country

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl true
  def code, do: "NL"

  @impl true
  def shipped_from, do: dgettext("netherlands", "wysyłka z Holandii")

  @impl true
  def delivered_from, do: dgettext("netherlands", "z wysyłką z Holandii")

  @impl true
  def region, do: nil
end
