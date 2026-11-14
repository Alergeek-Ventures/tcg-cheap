defmodule TcgCheap.Countries.Sweden do
  @moduledoc "Sweden: shops there sell to the guide's regions (`TcgCheap.Country`)."

  @behaviour TcgCheap.Country

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl true
  def code, do: "SE"

  @impl true
  def shipped_from, do: dgettext("sweden", "wysyłka ze Szwecji")

  @impl true
  def delivered_from, do: dgettext("sweden", "z wysyłką ze Szwecji")

  @impl true
  def region, do: nil
end
