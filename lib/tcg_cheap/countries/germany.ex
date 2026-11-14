defmodule TcgCheap.Countries.Germany do
  @moduledoc "Germany: shops there sell to the guide's regions (`TcgCheap.Country`)."

  @behaviour TcgCheap.Country

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl true
  def code, do: "DE"

  @impl true
  def shipped_from, do: dgettext("germany", "wysyłka z Niemiec")

  @impl true
  def delivered_from, do: dgettext("germany", "z wysyłką z Niemiec")

  @impl true
  def region, do: nil
end
