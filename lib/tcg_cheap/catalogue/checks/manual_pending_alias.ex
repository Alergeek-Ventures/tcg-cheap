defmodule TcgCheap.Catalogue.Checks.ManualPendingAlias do
  @moduledoc "Policy check that permits revision only for pending aliases without provider evidence."

  use Ash.Policy.SimpleCheck

  alias Ash.Changeset
  alias TcgCheap.Catalogue.SealedProductAlias

  @impl true
  def describe(_opts), do: "alias is pending and manually curated"

  @impl true
  def match?(
        _actor,
        %{subject: %Changeset{data: %SealedProductAlias{} = alias_record}},
        _opts
      ) do
    {:ok, alias_record.review_status == "pending" and is_nil(alias_record.source)}
  end

  def match?(_actor, _context, _opts), do: {:ok, false}
end
