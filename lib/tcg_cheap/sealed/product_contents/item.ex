defmodule TcgCheap.Sealed.ProductContents.Item do
  @moduledoc "One kind of thing in a sealed product, with how many there are."

  use Ash.Resource, data_layer: :embedded

  @types ~w(booster promo_card oversize_card card deck sleeves energy_cards dice damage_counters
            coin condition_markers deck_box storage_box card_dividers player_guide rule_sheet
            code_card sticker pin figure binder playmat other)a

  @doc "Every item type."
  @spec types() :: [atom()]
  def types, do: @types

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
      description "English: the set of a booster, the card's name, or what an accessory is."
      public? true
      constraints max_length: 200
    end

    attribute :tcgdex_id, :string do
      description "The TCGdex card id of a card, e.g. me06-023."
      public? true
      constraints max_length: 40, match: ~r/\A[A-Za-z0-9.\-]+\z/
    end

    attribute :image, :string do
      description "The card's TCGdex image base URL, exactly as TCGdex returns it."
      public? true
      constraints max_length: 300, match: ~r{\Ahttps://assets\.tcgdex\.net/[A-Za-z0-9./\-]+\z}
    end
  end
end
