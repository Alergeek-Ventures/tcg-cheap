defmodule TcgCheap.Sealed.ProductContents.DeckCard do
  @moduledoc "One card of a fixed deck or random variant's list, with how many copies the deck has."

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :quantity, :integer do
      allow_nil? false
      public? true
      constraints min: 1, max: 60
    end

    attribute :name, :string do
      description "English: the card's name (TCGdex's when omitted)."
      public? true
      constraints max_length: 200
    end

    attribute :tcgdex_id, :string do
      description "The TCGdex card id of the printing in the deck, e.g. me04-022; its category, set, number, picture and Cardmarket product come from TCGdex."
      public? true
      constraints max_length: 40, match: ~r/\A[A-Za-z0-9.\-]+\z/
    end

    attribute :category, :string do
      description "Pokemon, Trainer or Energy, from TCGdex."
      public? true
      constraints max_length: 20
    end

    attribute :set, :string do
      description "The card's set, from TCGdex."
      public? true
      constraints max_length: 100
    end

    attribute :number, :string do
      description "The card's number in its set, from TCGdex."
      public? true
      constraints max_length: 20
    end

    attribute :cardmarket_id, :integer do
      description "The card's Cardmarket product id, from TCGdex."
      public? true
      constraints min: 1
    end

    attribute :image, :string do
      description "The card's TCGdex image base URL, exactly as TCGdex returns it."
      public? true
      constraints max_length: 300, match: ~r{\Ahttps://assets\.tcgdex\.net/[A-Za-z0-9./\-]+\z}
    end

    attribute :photo, :string do
      description "A picture of the card when TCGdex has none (image null, e.g. basic Energy): an https image URL on an allowed image host, checked by eye to show this printing. Shown from our own storage once mirrored."
      public? true
      constraints max_length: 2_000
    end
  end
end
