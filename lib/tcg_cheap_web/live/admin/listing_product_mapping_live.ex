defmodule TcgCheapWeb.Admin.ListingProductMappingLive do
  @moduledoc "Authenticated, read-only AshBackpex projection of listing-product mappings."

  use AshBackpex.LiveResource

  backpex do
    resource TcgCheap.Catalogue.ListingProductMapping
    layout({TcgCheapWeb.Layouts, :admin})
    read_action(:admin_catalogue)
    load([:retailer_listing, :candidate_product, :confirmed_product])
    singular_name("Listing-product mapping")
    plural_name("Listing-product mappings")
    init_order(%{by: :updated_at, direction: :desc})
    per_page_default(15)
    per_page_options([15, 50])

    panels(source: "Source", decision: "Decision", timing: "Timing")

    fields do
      field :status do
        label("Status")
        panel(:decision)
      end

      field :retailer_listing do
        module AshBackpex.Fields.BelongsTo
        display_field(:source_title)
        live_resource(TcgCheapWeb.Admin.RetailerListingLive)
        panel(:source)
      end

      field :candidate_product do
        module AshBackpex.Fields.BelongsTo
        display_field(:name)
        live_resource(TcgCheapWeb.Admin.SealedProductLive)
        panel(:decision)
      end

      field :confirmed_product do
        module AshBackpex.Fields.BelongsTo
        display_field(:name)
        live_resource(TcgCheapWeb.Admin.SealedProductLive)
        panel(:decision)
      end

      field :confidence do
        module Backpex.Fields.Number
        label("Confidence")
        panel(:decision)
      end

      field :reason do
        label("Reason")
        panel(:decision)
      end

      field :approved_at do
        label("Approved")
        panel(:timing)
      end

      field :rejected_at do
        label("Rejected")
        panel(:timing)
      end

      field :inserted_at do
        only([:show])
        label("Inserted")
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

      action :reopen, TcgCheapWeb.Admin.ListingProductMappingReopenAction do
        only([:row, :show])
      end
    end
  end
end
