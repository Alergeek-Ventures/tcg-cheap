defmodule TcgCheap.Sealed.ProductContents.DeckCard do
  @moduledoc "One line of a fixed deck's card list."

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :quantity, :integer do
      allow_nil? false
      public? true
      constraints min: 1, max: 60
    end

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints max_length: 200
    end

    attribute :category, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:pokemon, :trainer, :energy]
    end

    attribute :set, :string, public?: true, constraints: [max_length: 100]
    attribute :number, :string, public?: true, constraints: [max_length: 20]

    attribute :tcgdex_id, :string do
      public? true
      constraints max_length: 40, match: ~r/\A[A-Za-z0-9.\-]+\z/
    end

    attribute :image, :string do
      public? true
      constraints max_length: 300, match: ~r{\Ahttps://assets\.tcgdex\.net/[A-Za-z0-9./\-]+\z}
    end
  end
end
