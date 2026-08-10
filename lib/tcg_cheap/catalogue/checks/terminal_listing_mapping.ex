defmodule TcgCheap.Catalogue.Checks.TerminalListingMapping do
  @moduledoc "Policy check that permits correction only for matched or rejected mappings."

  use Ash.Policy.SimpleCheck

  alias Ash.Changeset
  alias TcgCheap.Catalogue.ListingProductMapping

  @impl true
  def describe(_opts), do: "mapping has a terminal decision"

  @impl true
  def match?(
        _actor,
        %{subject: %Changeset{data: %ListingProductMapping{status: status}}},
        _opts
      ) do
    {:ok, status in ["matched", "rejected"]}
  end

  def match?(_actor, _context, _opts), do: {:ok, false}
end
