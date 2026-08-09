defmodule TcgCheap.Pricing.SealedDailyAggregateEvidence do
  @moduledoc "Immutable source row retained with a sealed daily aggregate."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :mapping_id, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1]

    attribute :confidence, :decimal,
      allow_nil?: false,
      public?: true,
      constraints: [greater_than: 0, max: 1]

    attribute :approved_at, :utc_datetime_usec, allow_nil?: false, public?: true

    attribute :listing_id, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1]

    attribute :retailer_id, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1]

    attribute :retailer_category, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/^(regular_retailer|lgs)$/]

    attribute :stock_status, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/^(in_stock|sold_out)$/]

    attribute :price_pln, :decimal,
      public?: true,
      constraints: [greater_than: 0]

    attribute :checked_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end
end
