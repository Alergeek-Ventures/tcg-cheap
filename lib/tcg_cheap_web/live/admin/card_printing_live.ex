defmodule TcgCheapWeb.Admin.CardPrintingLive do
  @moduledoc "Authenticated, read-only AshBackpex inspection of exact card printings."

  use AshBackpex.LiveResource

  backpex do
    resource TcgCheap.Catalogue.CardPrinting
    layout({TcgCheapWeb.Layouts, :admin})
    read_action(:admin_catalogue)
    load([:card_set])
    singular_name("Card printing")
    plural_name("Card printings")
    init_order(%{by: :tcgdex_id, direction: :asc})
    per_page_default(15)
    per_page_options([15, 50])

    panels(
      identity: "Identity",
      metadata: "Card metadata",
      mapping: "Cardmarket mapping",
      timing: "Timing"
    )

    fields do
      field :tcgdex_id, label: "TCGdex ID", panel: :identity
      field :name, searchable: true, orderable: false, panel: :identity
      field :set_name, label: "Set", orderable: false, panel: :identity
      field :collector_number, label: "Collector number", orderable: false, panel: :identity

      field :card_set do
        module AshBackpex.Fields.BelongsTo
        display_field(:name)
        orderable(false)
        panel(:identity)
      end

      field :image_url,
        module: Backpex.Fields.URL,
        label: "Image URL",
        orderable: false,
        panel: :metadata

      field :rarity, orderable: false, panel: :metadata
      field :category, orderable: false, panel: :metadata
      field :illustrator, orderable: false, panel: :metadata
      field :regulation_mark, label: "Regulation mark", orderable: false, panel: :metadata
      field :standard_legal, label: "Standard legal", orderable: false, panel: :metadata
      field :expanded_legal, label: "Expanded legal", orderable: false, panel: :metadata

      field :mapping_status, label: "Mapping status", orderable: false, panel: :mapping

      field :cardmarket_product_id,
        label: "Cardmarket product ID",
        orderable: false,
        panel: :mapping

      field :mapping_review_reason, label: "Review reason", orderable: false, panel: :mapping
      field :mapping_updated_at, label: "Mapping updated", orderable: false, panel: :mapping

      field :source_updated_at, label: "Source updated", orderable: false, panel: :timing
      field :last_synced_at, label: "Last synced", orderable: false, panel: :timing
      field :created_at, only: [:show], orderable: false, panel: :timing
      field :updated_at, only: [:show], orderable: false, panel: :timing
    end

    item_actions do
      strip_default([:edit, :delete])
    end
  end
end
