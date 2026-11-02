defmodule TcgCheap.Sealed.PullRates do
  @moduledoc """
  How often a set's boosters hold each rarity: community estimates from
  people who opened many packs, gathered by an agent or admin. Stored on the
  English TCGdex set and shown on the page of its single booster with the
  sources, their sample sizes and the day they were checked.
  """

  use Ash.Resource, data_layer: :embedded

  alias TcgCheap.Sealed.PullRates.{Rate, Source}

  validations do
    validate {TcgCheap.Sealed.Validations.HttpsUrls, attribute: :sources, key: :url}
  end

  attributes do
    attribute :cards_per_pack, :integer do
      description "Cards in one booster, when the sources say."
      public? true
      constraints min: 1, max: 100
    end

    attribute :rates, {:array, Rate} do
      description "One entry per rarity."
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 50
    end

    attribute :sources, {:array, Source} do
      description "The https pages the estimates were read from."
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 10
    end

    attribute :borrowed_from, :string do
      description "The set whose estimates stand in until this set's own are out, so unverified for this set."
      public? true
      constraints max_length: 100
    end

    attribute :checked_on, :date do
      description "The day the sources were read."
      allow_nil? false
      public? true
    end
  end
end
