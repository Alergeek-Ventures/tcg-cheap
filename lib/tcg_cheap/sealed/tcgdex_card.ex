defmodule TcgCheap.Sealed.TcgdexCard do
  @moduledoc """
  One card of an English TCGdex set, with its number and rarity, for the
  list of cards a booster can hold, and its Cardmarket product id, which
  links it to Cardmarket and to its price (`TcgCheap.Sealed.CardPrice`).
  Copied from TCGdex by `TcgCheap.Sealed.CardSync`.
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
      accept [:tcgdex_set_id, :tcgdex_id, :number, :name, :rarity, :variants]
      upsert? true
      upsert_identity :tcgdex_id
      upsert_fields [:number, :name, :rarity, :variants, :updated_at]
    end

    read :cardmarket_due do
      description """
      Cards without a Cardmarket product id never looked up, or looked up
      before `checked_before`, never looked up first, then of the newest sets.
      Cards of an unofficial list wait for TCGdex's, which TCGdex has documents for.
      """

      argument :checked_before, :utc_datetime_usec, allow_nil?: false

      filter expr(
               is_nil(cardmarket_id) and is_nil(tcgdex_set.cards_source_url) and
                 (is_nil(cardmarket_checked_at) or cardmarket_checked_at < ^arg(:checked_before))
             )

      prepare build(
                sort: [
                  cardmarket_checked_at: :asc_nils_first,
                  set_released_on: :desc_nils_last,
                  tcgdex_id: :asc
                ]
              )
    end

    update :record_cardmarket_id do
      description "Records the Cardmarket product id TCGdex gives the card, nil when none."
      accept [:cardmarket_id]
      change set_attribute(:cardmarket_checked_at, &DateTime.utc_now/0)
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

    attribute :variants, {:array, :string}, public?: true, default: []

    attribute :cardmarket_id, :integer do
      description "The Cardmarket product id TCGdex gives the card, nil when unknown."
      public? true
      constraints min: 1
    end

    attribute :cardmarket_checked_at, :utc_datetime_usec do
      description "When TCGdex was last asked for the Cardmarket product id."
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :tcgdex_set, TcgCheap.Sealed.TcgdexSet, allow_nil?: false, public?: true

    has_one :cardmarket_price, TcgCheap.Sealed.CardPrice do
      source_attribute :cardmarket_id
      destination_attribute :cardmarket_id
      public? true
    end
  end

  aggregates do
    first :set_released_on, :tcgdex_set, :released_on
  end

  identities do
    identity :tcgdex_id, [:tcgdex_set_id, :tcgdex_id]
  end
end
