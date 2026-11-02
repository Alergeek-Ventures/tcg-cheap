defmodule TcgCheap.Sealed.PullRates.Source do
  @moduledoc "A page pull rates were read from, with how many packs its estimate rests on and whose data it cites. `TcgCheap.Sealed.PullRates` checks that it is https."

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :url, :string do
      allow_nil? false
      public? true
      constraints max_length: 2_000
    end

    attribute :sample_packs, :integer do
      description "Packs opened for the estimate, when the source says."
      public? true
      constraints min: 1
    end

    attribute :data_from, :string do
      description "Who gathered the data, when the page cites someone else's, e.g. TCGplayer."
      public? true
      constraints max_length: 100
    end
  end
end
