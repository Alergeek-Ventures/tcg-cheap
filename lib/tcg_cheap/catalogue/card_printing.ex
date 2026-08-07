defmodule TcgCheap.Catalogue.CardPrinting do
  @moduledoc """
  One exact Pokémon card printing from the canonical TCGdex catalogue.

  The TCGdex ID is the stable external identity used by provider acquisition;
  public display metadata can expand as the catalogue importer is introduced.
  """

  use Ash.Resource,
    domain: TcgCheap.Core,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "card_printings"
    repo TcgCheap.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:tcgdex_id, :name, :set_name, :collector_number]
    end

    read :by_tcgdex_id do
      argument :tcgdex_id, :string, allow_nil?: false
      get? true
      filter expr(tcgdex_id == ^arg(:tcgdex_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :tcgdex_id, :string do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :set_name, :string do
      allow_nil? false
      public? true
    end

    attribute :collector_number, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :valuation_snapshots, TcgCheap.Pricing.Singles.SingleValuationSnapshot
  end

  identities do
    identity :unique_tcgdex_id, [:tcgdex_id]
  end
end
