defmodule TcgCheap.Sealed.CardOffer do
  @moduledoc """
  A shop's single card. Feed data never overwrites a manual identity decision.
  Unknown language means English; patterned prints keep their identity but have
  no reference price. Current offers use the latest card fetch independently
  of sealed offers, including shops selling only singles.
  """
  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  alias TcgCheap.Sealed.CardMatcher

  postgres do
    table "sealed_card_offers"
    repo TcgCheap.Repo

    references do
      reference :card, on_delete: :nilify
    end

    custom_indexes do
      index [:last_seen_at]
      index [:shop, :last_seen_at]
      index [:card_id, :last_seen_at]
    end
  end

  actions do
    defaults [:read]

    create :upsert do
      accept [
        :shop,
        :shop_product_id,
        :title,
        :category,
        :url,
        :image_url,
        :price,
        :shop_price,
        :currency,
        :in_stock,
        :last_seen_at,
        :language,
        :condition,
        :grading
      ]

      upsert? true
      upsert_identity :shop_product

      upsert_fields [
        :title,
        :category,
        :url,
        :image_url,
        :price,
        :shop_price,
        :currency,
        :in_stock,
        :last_seen_at,
        :language,
        :condition,
        :grading,
        :updated_at
      ]
    end

    create :rematch_batch do
      description "Updates matching fields in batches, preserving every manual decision."

      accept [
        :shop,
        :shop_product_id,
        :title,
        :url,
        :price,
        :in_stock,
        :last_seen_at,
        :card_id,
        :variant,
        :match_note,
        :match_set_ids,
        :language,
        :condition,
        :grading
      ]

      upsert? true
      upsert_identity :shop_product
      upsert_condition expr(manual? == false)

      upsert_fields [
        :card_id,
        :variant,
        :match_note,
        :match_set_ids,
        :language,
        :condition,
        :grading,
        :updated_at
      ]
    end

    update :match do
      accept [:card_id, :variant, :match_note, :match_set_ids, :language, :condition, :grading]
      validate attribute_equals(:manual?, false)
    end

    update :assign_manually do
      accept [:card_id, :variant]
      validate present(:card_id)
      require_atomic? false

      change fn changeset, _context ->
        parsed = CardMatcher.parse(changeset.data)

        changeset =
          Ash.Changeset.change_attributes(
            changeset,
            Map.take(parsed, [:language, :condition, :grading])
          )

        if parsed.language in [nil, "en"],
          do: changeset,
          else:
            Ash.Changeset.add_error(changeset,
              field: :language,
              message: "only English cards can be assigned"
            )
      end

      change set_attribute(:manual?, true)
      change set_attribute(:match_note, "manual_assignment")
    end

    update :exclude_manually do
      accept [:match_note]
      change set_attribute(:manual?, true)
      change set_attribute(:card_id, nil)
    end

    update :clear_manual do
      change set_attribute(:manual?, false)
      change set_attribute(:card_id, nil)
      change set_attribute(:match_note, nil)
    end

    read :seen_since do
      argument :since, :utc_datetime_usec, allow_nil?: false
      filter expr(last_seen_at >= ^arg(:since))
      prepare build(sort: [shop: :asc, title: :asc, id: :asc])
    end

    read :manual do
      filter expr(manual? == true)
      prepare build(sort: [shop: :asc, title: :asc, id: :asc])
    end

    action :latest_fetches, :map do
      argument :since, :utc_datetime_usec, allow_nil?: false
      run {TcgCheap.Sealed.Offer.LatestFetches, resource: __MODULE__}
    end
  end

  validations do
    validate compare(:price, greater_than: 0)
    validate compare(:shop_price, greater_than: 0)
  end

  attributes do
    uuid_primary_key :id
    attribute :match_set_ids, {:array, :string}, default: []
    attribute :shop, :string, allow_nil?: false, public?: true, constraints: [max_length: 40]

    attribute :shop_product_id, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 40]

    attribute :title, :string, allow_nil?: false, public?: true, constraints: [max_length: 300]
    attribute :category, :string, public?: true, constraints: [max_length: 300]
    attribute :url, :string, allow_nil?: false, public?: true, constraints: [max_length: 2_000]
    attribute :image_url, :string, public?: true, constraints: [max_length: 2_000]
    attribute :price, :decimal, allow_nil?: false, public?: true

    attribute :shop_price, :decimal do
      description "The shop's own price, in `currency`; `price` is it in PLN as of the fetch. Nil until the shop's first fetch that records it."
      public? true
    end

    attribute :currency, :string do
      description "The ISO code of `shop_price`'s currency, the shop's."
      public? true
      constraints max_length: 3
    end

    attribute :in_stock, :boolean, allow_nil?: false, public?: true
    attribute :last_seen_at, :utc_datetime_usec, allow_nil?: false, public?: true

    attribute :variant, :atom,
      allow_nil?: false,
      default: :normal,
      public?: true,
      constraints: [one_of: [:normal, :reverse, :special]]

    attribute :manual?, :boolean, allow_nil?: false, default: false, public?: true
    attribute :match_note, :string, public?: true, constraints: [max_length: 300]
    attribute :language, :string, public?: true, constraints: [max_length: 10]

    attribute :condition, :atom,
      public?: true,
      constraints: [one_of: [:mint, :near_mint, :excellent, :good, :light_played, :played, :poor]]

    attribute :grading, :string, public?: true, constraints: [max_length: 40]
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :card, TcgCheap.Sealed.TcgdexCard, public?: true
  end

  identities do
    identity :shop_product, [:shop, :shop_product_id]
  end
end
