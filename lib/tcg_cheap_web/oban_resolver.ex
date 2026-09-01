defmodule TcgCheapWeb.ObanResolver do
  @moduledoc "Restricts Oban Web to authenticated administrators."

  @behaviour Oban.Web.Resolver

  alias TcgCheap.Accounts.Admin

  @impl true
  def resolve_user(conn), do: conn.assigns[:current_admin]

  @impl true
  def resolve_access(%Admin{}), do: :all
  def resolve_access(_user), do: {:forbidden, "/admin/sign-in"}

  @impl true
  def resolve_instances(%Admin{}), do: :all
  def resolve_instances(_user), do: []
end
