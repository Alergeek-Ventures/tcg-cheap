defmodule TcgCheap.Sealed.ProductContents do
  @moduledoc """
  What a sealed product holds, as facts gathered by an agent or admin from
  shop and publisher pages: the items (boosters, promo cards, accessories)
  and, for a fixed deck, its card list. Stored on the product and shown on
  its page with the sources and the day they were checked.
  """

  use Ash.Resource, data_layer: :embedded

  alias TcgCheap.Sealed.ProductContents.{DeckCard, Item}

  validations do
    validate {TcgCheap.Sealed.Validations.HttpsUrls, attribute: :sources}
  end

  attributes do
    attribute :items, {:array, Item} do
      description "Everything in the box, in the order a buyer would list it."
      allow_nil? false
      default []
      public? true
    end

    attribute :deck, {:array, DeckCard} do
      description "The full card list of a fixed deck (theme, battle, league battle deck); [] otherwise."
      allow_nil? false
      default []
      public? true
    end

    attribute :sources, {:array, :string} do
      description "The https pages the facts were read from."
      allow_nil? false
      public? true
      constraints min_length: 1, items: [max_length: 2_000]
    end

    attribute :checked_on, :date do
      description "The day the sources were read."
      allow_nil? false
      public? true
    end
  end
end
