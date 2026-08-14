defmodule TcgCheapWeb.Admin.CardSetLive do
  @moduledoc "Authenticated, read-only AshBackpex inspection of imported card sets."

  use AshBackpex.LiveResource

  backpex do
    resource TcgCheap.Catalogue.CardSet
    layout({TcgCheapWeb.Layouts, :admin})
    read_action(:admin_catalogue)
    singular_name("Card set")
    plural_name("Card sets")
    init_order(%{by: :tcgdex_id, direction: :asc})
    per_page_default(15)
    per_page_options([15, 50])

    panels(identity: "Identity", catalogue: "Catalogue", timing: "Timing")

    fields do
      field :tcgdex_id, label: "TCGdex ID", panel: :identity
      field :name, searchable: true, orderable: false, panel: :identity
      field :series_id, label: "Series ID", orderable: false, panel: :identity
      field :series_name, label: "Series", orderable: false, panel: :identity
      field :release_date, orderable: false, panel: :catalogue
      field :official_count, label: "Official count", orderable: false, panel: :catalogue
      field :total_count, label: "Total count", orderable: false, panel: :catalogue
      field :imported_printings, label: "Imported printings", orderable: false, panel: :catalogue
      field :standard_legal, label: "Standard legal", orderable: false, panel: :catalogue
      field :expanded_legal, label: "Expanded legal", orderable: false, panel: :catalogue

      field :logo_url,
        module: Backpex.Fields.URL,
        label: "Logo URL",
        orderable: false,
        panel: :catalogue

      field :symbol_url,
        module: Backpex.Fields.URL,
        label: "Symbol URL",
        orderable: false,
        panel: :catalogue

      field :created_at, only: [:show], orderable: false, panel: :timing
      field :updated_at, only: [:show], orderable: false, panel: :timing
      field :last_synced_at, label: "Last synced", orderable: false, panel: :timing
    end

    item_actions do
      strip_default([:edit, :delete])
    end
  end
end
