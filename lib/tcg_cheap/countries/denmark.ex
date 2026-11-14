defmodule TcgCheap.Countries.Denmark do
  @moduledoc "Denmark: shops there sell to the guide's regions (`TcgCheap.Country`)."

  @behaviour TcgCheap.Country

  use Gettext, backend: TcgCheapWeb.Gettext

  @impl true
  def code, do: "DK"

  @impl true
  def shipped_from, do: dgettext("denmark", "wysyłka z Danii")

  @impl true
  def delivered_from, do: dgettext("denmark", "z wysyłką z Danii")

  @impl true
  def region, do: nil
end
