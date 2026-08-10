defmodule TcgCheapWeb.Admin.SingleValuationSnapshotLive do
  @moduledoc "Authenticated, read-only AshBackpex inspection of immutable single valuations."

  use AshBackpex.LiveResource

  backpex do
    resource TcgCheap.Pricing.Singles.SingleValuationSnapshot
    layout({TcgCheapWeb.Layouts, :admin})
    read_action(:admin_catalogue)
    load([:card_printing])
    singular_name("Valuation snapshot")
    plural_name("Valuation snapshots")
    # AshBackpex 0.1.12 applies one UI sort on its generic query path. UUID order is not
    # chronological, but it keeps pagination stable when snapshots share a fetch time.
    init_order(%{by: :id, direction: :asc})
    per_page_default(15)
    per_page_options([15, 50])

    panels(card: "Card", valuation: "Valuation", provenance: "Provenance", timing: "Timing")

    fields do
      field :card_printing do
        module AshBackpex.Fields.BelongsTo
        display_field(:tcgdex_id)
        live_resource(TcgCheapWeb.Admin.CardPrintingLive)
        orderable(false)
        panel(:card)
      end

      field :value_eur do
        module Backpex.Fields.Number
        label("Value (EUR)")
        orderable(false)
        panel(:valuation)
      end

      field :currency, orderable: false, panel: :valuation
      field :current?, label: "Current", orderable: false, panel: :valuation
      field :policy_version, label: "Policy", orderable: false, panel: :provenance
      field :source, orderable: false, panel: :provenance
      field :source_metric, label: "Metric", orderable: false, panel: :provenance

      field :cardmarket_product_id,
        label: "Cardmarket product ID",
        orderable: false,
        panel: :provenance

      field :fetched_at, label: "Fetched", orderable: false, panel: :timing
      field :provider_updated_at, label: "Provider updated", orderable: false, panel: :timing
      field :created_at, label: "Inserted", orderable: false, panel: :timing
    end

    item_actions do
      strip_default([:edit, :delete])
    end
  end
end
