defmodule TcgCheapWeb.SiteFooter do
  @moduledoc "The sets the public pages' footer links, for every guide LiveView."

  import Phoenix.Component, only: [assign: 3]

  alias TcgCheap.Sealed.Guide

  @sets 12

  def on_mount(:default, _params, _session, socket),
    do: {:cont, assign(socket, :footer_sets, Guide.newest_expansions(@sets))}
end
