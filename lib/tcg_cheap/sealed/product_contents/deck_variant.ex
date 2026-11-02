defmodule TcgCheap.Sealed.ProductContents.DeckVariant do
  @moduledoc """
  One possible random deck in a sealed product. Record only the publisher's
  known cards, even when its published list is incomplete; never invent copies.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :name, :string do
      description "English: the deck's featured Pokémon."
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 200
    end

    attribute :cards, {:array, TcgCheap.Sealed.ProductContents.DeckCard} do
      description "Known cards of this variant with their copies and TCGdex ids, enriched and checked like a fixed deck's cards. May be incomplete."
      allow_nil? false
      public? true
      constraints min_length: 1
    end
  end
end
