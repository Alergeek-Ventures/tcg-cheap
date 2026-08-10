defmodule TcgCheap.TestSupport do
  @moduledoc "Low-level card printing fixtures for tests."

  alias TcgCheap.Catalogue.CardPrinting

  @doc "Creates a card printing through the importer-only action for low-level fixtures."
  def import_card_printing(attrs) do
    attrs
    |> changeset()
    |> Ash.create(authorize?: false)
  end

  @doc "Creates a card printing through the importer-only action, raising on failure."
  def import_card_printing!(attrs) do
    attrs
    |> changeset()
    |> Ash.create!(authorize?: false)
  end

  defp changeset(attrs), do: Ash.Changeset.for_create(CardPrinting, :import, attrs)
end
