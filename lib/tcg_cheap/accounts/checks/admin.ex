defmodule TcgCheap.Accounts.Checks.Admin do
  @moduledoc "Policy check that permits only a persisted administrator actor."

  use Ash.Policy.SimpleCheck

  alias TcgCheap.Accounts.Admin

  @impl true
  def describe(_opts), do: "actor is an administrator"

  @impl true
  def match?(%Admin{}, _context, _opts), do: {:ok, true}
  def match?(_actor, _context, _opts), do: {:ok, false}
end
