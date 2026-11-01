defmodule TcgCheap.Sealed.TcgdexSet do
  @moduledoc """
  An English or Japanese TCGdex set and the Cardmarket expansion holding its
  cards, found through the Cardmarket product id TCGdex gives its cards
  (`TcgCheap.Sealed.ExpansionSync`). It names the language of the expansion's
  sealed products and, for English sets, gives the logo.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_tcgdex_sets"
    repo TcgCheap.Repo
  end

  actions do
    defaults [:read]

    create :record do
      accept [:language, :tcgdex_id, :cardmarket_expansion_id, :name, :logo_url, :released_on]
      upsert? true
      upsert_identity :tcgdex_id

      upsert_fields [
        :cardmarket_expansion_id,
        :name,
        :logo_url,
        :released_on,
        :checked_at,
        :updated_at
      ]

      change set_attribute(:checked_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :language, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A(en|ja)\z/]

    attribute :tcgdex_id, :string, allow_nil?: false, public?: true, constraints: [max_length: 40]
    attribute :cardmarket_expansion_id, :integer, public?: true
    attribute :name, :string, public?: true, constraints: [max_length: 200]
    attribute :logo_url, :string, public?: true, constraints: [max_length: 500]
    attribute :released_on, :date, public?: true
    attribute :checked_at, :utc_datetime_usec, allow_nil?: false, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :tcgdex_id, [:language, :tcgdex_id]
  end

  @doc """
  One set per resolved expansion, which names it and gives its logo. An
  expansion holding several (a set and its gallery subset) takes an English
  one with a name, the shortest.
  """
  @spec by_expansion([t()]) :: %{integer() => t()}
  def by_expansion(sets) do
    sets
    |> Enum.filter(& &1.cardmarket_expansion_id)
    |> Enum.group_by(& &1.cardmarket_expansion_id)
    |> Map.new(fn {id, sets} ->
      {id,
       Enum.min_by(sets, &{&1.language != "en", is_nil(&1.name), String.length(&1.name || "")})}
    end)
  end
end
