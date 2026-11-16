defmodule TcgCheapWeb.SiteFooter do
  @moduledoc "The sets the public pages' footer links, for every guide LiveView."

  import Phoenix.Component, only: [assign: 3]

  alias TcgCheap.Sealed.Expansions

  @sets 12

  def on_mount(:default, _params, _session, socket),
    do: {:cont, assign(socket, :footer_sets, Expansions.newest(@sets))}
end
