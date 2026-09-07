defmodule TcgCheap.Pricing.CardmarketBulk.Product do
  @moduledoc "Latest Pokémon single product row imported from Cardmarket bulk data."
  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cardmarket_bulk_products"
    repo TcgCheap.Repo

    custom_indexes do
      index [:last_batch_id]
    end

    references do
      reference :last_batch, on_delete: :restrict
    end

    check_constraints do
      check_constraint [
                         :cardmarket_product_id,
                         :category_id,
                         :category_name,
                         :expansion_id,
                         :metacard_id
                       ],
                       "cardmarket_bulk_products_identity_invariant",
                       check:
                         "cardmarket_product_id > 0 AND category_id = 51 AND category_name = 'Pokémon Single' AND expansion_id > 0 AND metacard_id >= 0"

      check_constraint [:name, :source_date_added], "cardmarket_bulk_products_text_present",
        check: "btrim(name) <> '' AND btrim(source_date_added) <> ''"
    end
  end

  actions do
    read :read

    create :upsert do
      accept [
        :cardmarket_product_id,
        :name,
        :category_id,
        :category_name,
        :expansion_id,
        :metacard_id,
        :source_date_added,
        :last_batch_id,
        :source_updated_at
      ]

      upsert? true
      upsert_identity :unique_cardmarket_product_id

      upsert_fields [
        :name,
        :category_id,
        :category_name,
        :expansion_id,
        :metacard_id,
        :source_date_added,
        :last_batch_id,
        :source_updated_at
      ]

      upsert_condition expr(source_updated_at <= upsert_conflict(:source_updated_at))
    end

    read :by_product_ids do
      argument :cardmarket_product_ids, {:array, :integer},
        allow_nil?: false,
        constraints: [max_length: 1_000]

      filter expr(cardmarket_product_id in ^arg(:cardmarket_product_ids))
    end

    read :for_batch_and_expansion do
      argument :batch_id, :uuid, allow_nil?: false
      argument :expansion_id, :integer, allow_nil?: false, constraints: [min: 1]

      filter expr(last_batch_id == ^arg(:batch_id) and expansion_id == ^arg(:expansion_id))
      prepare build(sort: [cardmarket_product_id: :asc, id: :asc])
    end
  end

  policies do
    bypass action(:upsert) do
      authorize_if always()
    end

    policy action(:by_product_ids) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end

    policy action_type(:read) do
      forbid_unless TcgCheap.Accounts.Checks.Admin
      authorize_if always()
    end
  end

  validations do
    validate one_of(:category_id, [51])
    validate one_of(:category_name, ["Pokémon Single"])
    validate match(:name, ~r/\S+/)
    validate match(:source_date_added, ~r/\S+/)
  end

  attributes do
    uuid_primary_key :id

    attribute :cardmarket_product_id, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]

    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 500]

    attribute :category_id, :integer, allow_nil?: false, default: 51, public?: true
    attribute :category_name, :string, allow_nil?: false, default: "Pokémon Single", public?: true

    attribute :expansion_id, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]

    attribute :metacard_id, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0]

    attribute :source_date_added, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 100]

    attribute :source_updated_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :last_batch, TcgCheap.Pricing.CardmarketBulk.Batch,
      allow_nil?: false,
      public?: true
  end

  identities do
    identity :unique_cardmarket_product_id, [:cardmarket_product_id]
  end
end
