defmodule TcgCheapWeb.Admin.RetailerListingLive do
  @moduledoc "Authenticated, read-only AshBackpex projection of retailer listings."

  use AshBackpex.LiveResource

  backpex do
    resource TcgCheap.Catalogue.RetailerListing
    layout({TcgCheapWeb.Layouts, :admin})
    read_action(:admin_catalogue)
    load([:retailer])
    singular_name("Listing")
    plural_name("Listings")
    # AshBackpex 0.1.12 applies one UI sort on its generic query path. UUID order is not
    # chronological, but it is stable when many listings share one provider check time.
    init_order(%{by: :id, direction: :asc})
    per_page_default(15)
    per_page_options([15, 50])

    panels(source: "Source", evidence: "Current evidence", timing: "Timing")

    fields do
      field :retailer do
        display_field(:name)
        live_resource(TcgCheapWeb.Admin.RetailerLive)
        panel(:source)
      end

      field :source_title do
        searchable(true)
        label("Source title")
        panel(:source)
      end

      field :source_listing_id do
        searchable(true)
        label("Source listing ID")
        panel(:source)
      end

      field :normalized_title do
        only([:show])
        label("Normalized title")
        panel(:source)
      end

      field :gtin do
        label("GTIN")
        panel(:source)
      end

      field :current_price_pln do
        module Backpex.Fields.Number
        label("Current price (PLN)")
        panel(:evidence)
      end

      field :currency do
        panel(:evidence)
      end

      field :stock_status do
        label("Stock state")
        panel(:evidence)
      end

      field :status do
        label("Projection status")
        panel(:evidence)
      end

      field :direct_url do
        module Backpex.Fields.URL
        label("Direct URL")
        panel(:source)
      end

      field :first_seen_at do
        label("First seen")
        panel(:timing)
      end

      field :last_seen_at do
        label("Last seen")
        panel(:timing)
      end

      field :last_checked_at do
        label("Last checked")
        panel(:timing)
      end

      field :inserted_at do
        only([:show])
        panel(:timing)
      end

      field :updated_at do
        only([:show])
        label("Updated")
        panel(:timing)
      end
    end

    item_actions do
      strip_default([:edit, :delete])
    end
  end
end
