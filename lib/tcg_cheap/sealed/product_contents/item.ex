defmodule TcgCheap.Sealed.ProductContents.Item do
  @moduledoc """
  One kind of thing in a sealed product, with how many there are.
  A deck has either fixed `cards` or `variants`: quantity copies of one random
  deck from the named variants, never every variant in the same box.
  """

  use Ash.Resource, data_layer: :embedded

  @types ~w(booster promo_card oversize_card card deck sleeves energy_cards dice damage_counters
            coin condition_markers deck_box storage_box card_dividers player_guide rule_sheet
            code_card sticker pin figure binder playmat other)a

  @doc "Every item type."
  @spec types() :: [atom()]
  def types, do: @types

  validations do
    validate present([:cards, :variants], at_most: 1)

    validate attribute_equals(:type, :deck) do
      where present(:variants)
    end
  end

  attributes do
    attribute :quantity, :integer do
      allow_nil? false
      public? true
      constraints min: 1, max: 1_000
    end

    attribute :type, :atom do
      description "booster: name is the set; promo_card, oversize_card, card: name is the card."
      allow_nil? false
      public? true
      constraints one_of: @types
    end

    attribute :name, :string do
      description "English: the set of a booster, the card's name (TCGdex's when omitted), a deck's featured Pokémon, or what an item of type other is. Accessories are shown by type only."
      public? true
      constraints max_length: 200
    end

    attribute :tcgdex_id, :string do
      description "The TCGdex card id of a card, e.g. svp-085; its set, number, picture and Cardmarket product come from TCGdex."
      public? true
      constraints max_length: 40, match: ~r/\A[A-Za-z0-9.\-]+\z/
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
      description "A picture of this item (sleeves, dice, coin...): an https image URL on an allowed image host, e.g. a REBEL component picture. Shown from our own storage once mirrored."
      public? true
      constraints max_length: 2_000
    end

    attribute :variants, {:array, TcgCheap.Sealed.ProductContents.DeckVariant} do
      description "One random deck from these variants per quantity; only for type deck. Mutually exclusive with cards."
      public? true
      constraints min_length: 1
    end

    attribute :cards, {:array, TcgCheap.Sealed.ProductContents.DeckCard} do
      description "The full card list of a deck, or of a row of fixed cards (type card, e.g. a deck-building box's), as the publisher prints it: every card with its copies."
      public? true
    end
  end
end
