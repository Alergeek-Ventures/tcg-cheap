defmodule TcgCheap.Sealed.TcgdexSet do
  @moduledoc """
  An English or Japanese TCGdex set and the Cardmarket expansion holding its
  cards, found through the Cardmarket product id TCGdex gives its cards
  (`TcgCheap.Sealed.ExpansionSync`). It names the language of the expansion's
  sealed products and, for English sets, gives the logo, the cards
  (`TcgCheap.Sealed.CardSync`) and the pull rates its single booster's page
  shows.
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

    read :english do
      description "English sets, for finding one by TCGdex id or name."
      filter expr(language == "en")
    end

    read :english_of_expansion do
      description "The English sets of a Cardmarket expansion: a set and its gallery subsets."
      argument :expansion_id, :integer, allow_nil?: false
      filter expr(language == "en" and cardmarket_expansion_id == ^arg(:expansion_id))
    end

    read :cards_due do
      description """
      English sets of a Cardmarket expansion whose cards were never copied,
      or were copied before `checked_before` from a set released since
      `released_since`, newest first.
      """

      argument :released_since, :date, allow_nil?: false
      argument :checked_before, :utc_datetime_usec, allow_nil?: false

      filter expr(
               language == "en" and not is_nil(cardmarket_expansion_id) and
                 (is_nil(official_card_count) or is_nil(cards_checked_at) or
                    (released_on >= ^arg(:released_since) and
                       cards_checked_at < ^arg(:checked_before)))
             )

      prepare build(sort: [released_on: :desc_nils_last])
    end

    create :record_unofficial_cards do
      description """
      Records an English set TCGdex does not list yet, with an unofficial card list (a fan
      wiki's before release) whose page is `cards_source_url`. TCGdex's cards replace it once
      TCGdex lists as many, or two weeks after release whatever their number
      (`TcgCheap.Sealed.CardSync`).
      """

      accept [
        :tcgdex_id,
        :name,
        :abbreviation,
        :cardmarket_expansion_id,
        :released_on,
        :cards_source_url
      ]

      upsert? true
      upsert_identity :tcgdex_id
      # TCGdex's cards, once copied, are never overwritten by an unofficial list.
      upsert_condition expr(not is_nil(cards_source_url) or is_nil(cards_checked_at))

      upsert_fields [
        :name,
        :abbreviation,
        :cardmarket_expansion_id,
        :released_on,
        :cards_source_url,
        :cards_checked_at,
        :checked_at,
        :updated_at
      ]

      argument :cards, {:array, :map} do
        allow_nil? false

        constraints min_length: 1,
                    items: [
                      fields: [
                        tcgdex_id: [type: :string, allow_nil?: false],
                        number: [type: :string, allow_nil?: false],
                        name: [type: :string, allow_nil?: false],
                        rarity: [type: :string],
                        variants: [type: {:array, :string}],
                        cardmarket_id: [type: :integer, constraints: [min: 1]]
                      ]
                    ]
      end

      validate present([:name, :cardmarket_expansion_id, :released_on, :cards_source_url])
      validate {TcgCheap.Sealed.Validations.HttpsUrls, attribute: :cards_source_url}
      change set_attribute(:language, "en")
      change set_attribute(:checked_at, &DateTime.utc_now/0)
      change set_attribute(:cards_checked_at, &DateTime.utc_now/0)
      change {TcgCheap.Sealed.Changes.RecordCards, action: :record_unofficial}
    end

    update :set_pull_rates do
      description "Replaces the set's pull rates; nil removes them."
      accept [:pull_rates]
    end

    update :record_cards do
      accept [:abbreviation, :official_card_count, :card_images_url]
      description "Replaces the set's cards with those TCGdex lists now."

      argument :cards, {:array, :map} do
        allow_nil? false

        constraints items: [
                      fields: [
                        tcgdex_id: [type: :string, allow_nil?: false],
                        number: [type: :string, allow_nil?: false],
                        name: [type: :string, allow_nil?: false],
                        rarity: [type: :string],
                        variants: [type: {:array, :string}]
                      ]
                    ]
      end

      change set_attribute(:cards_checked_at, &DateTime.utc_now/0)
      change set_attribute(:cards_source_url, nil)
      change TcgCheap.Sealed.Changes.RecordCards
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
    attribute :abbreviation, :string, public?: true, constraints: [max_length: 30]
    attribute :official_card_count, :integer, public?: true, constraints: [min: 0]
    attribute :logo_url, :string, public?: true, constraints: [max_length: 500]

    attribute :card_images_url, :string do
      description """
      TCGdex's asset directory of the set's card images (`https://assets.tcgdex.net/en/sv/sv05`);
      a card's image is this plus `/` and its number. Nil while TCGdex has no card image of the set.
      """

      public? true
      constraints max_length: 500
    end

    attribute :released_on, :date, public?: true
    attribute :checked_at, :utc_datetime_usec, allow_nil?: false, public?: true

    attribute :cards_checked_at, :utc_datetime_usec do
      description "When the cards were last copied from TCGdex."
      public? true
    end

    attribute :cards_source_url, :string do
      description "The page an unofficial card list was copied from while TCGdex lists no cards of the set; nil for TCGdex's cards."
      public? true
      constraints max_length: 2_000
    end

    attribute :pull_rates, TcgCheap.Sealed.PullRates do
      description "How often a booster holds each rarity, maintained by an admin or agent."
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :cards, TcgCheap.Sealed.TcgdexCard, public?: true
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
