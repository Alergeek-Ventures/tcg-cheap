defmodule TcgCheap.Sealed.TcgdexCard do
  @moduledoc """
  One card of an English TCGdex set, with its number and rarity, for the
  list of cards a booster can hold. Copied from TCGdex by
  `TcgCheap.Sealed.CardSync`.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_tcgdex_cards"
    repo TcgCheap.Repo

    references do
      reference :tcgdex_set, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [:tcgdex_set_id, :tcgdex_id, :number, :name, :rarity]
      upsert? true
      upsert_identity :tcgdex_id
      upsert_fields [:number, :name, :rarity, :updated_at]
    end

    destroy :prune do
      description "Removes a card TCGdex no longer lists in its set."
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :tcgdex_id, :string do
      description "The TCGdex card id, e.g. sv09-011."
      allow_nil? false
      public? true
      constraints max_length: 60
    end

    attribute :number, :string do
      description "The number printed on the card, TCGdex's localId, e.g. 011 or TG05."
      allow_nil? false
      public? true
      constraints max_length: 20
    end

    attribute :name, :string, allow_nil?: false, public?: true, constraints: [max_length: 200]

    attribute :rarity, :string do
      description "TCGdex's rarity, nil when it gives none."
      public? true
      constraints max_length: 60
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :tcgdex_set, TcgCheap.Sealed.TcgdexSet, allow_nil?: false, public?: true
  end

  identities do
    identity :tcgdex_id, [:tcgdex_set_id, :tcgdex_id]
  end
end
