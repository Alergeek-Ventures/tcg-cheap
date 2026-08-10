defmodule TcgCheapWeb.Admin.ListingProductMappingDecisionLive do
  @moduledoc "Authenticated, read-only AshBackpex mapping decision history."

  use AshBackpex.LiveResource

  backpex do
    resource TcgCheap.Catalogue.ListingProductMappingDecision
    layout({TcgCheapWeb.Layouts, :admin})
    read_action(:admin_catalogue)
    load([:mapping, :candidate_product, :confirmed_product])
    singular_name("Mapping decision")
    plural_name("Mapping decisions")
    init_order(%{by: :inserted_at, direction: :desc})
    per_page_default(15)
    per_page_options([15, 50])

    panels(
      event: "Event",
      mapping: "Mapping",
      decision: "Decision",
      actor: "Actor",
      timing: "Timing"
    )

    fields do
      field :event, panel: :event
      field :from_status, label: "From status", panel: :event
      field :to_status, label: "To status", panel: :event

      field :mapping do
        module AshBackpex.Fields.BelongsTo
        display_field(:id)
        live_resource(TcgCheapWeb.Admin.ListingProductMappingLive)
        panel(:mapping)
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
        panel(:decision)
      end

      field :reason, panel: :decision
      field :evidence_method, label: "Evidence method", panel: :decision
      field :evidence_gtin, label: "Evidence GTIN", panel: :decision
      field :actor_type, label: "Actor type", panel: :actor
      field :actor_email, label: "Actor email", panel: :actor
      field :mapping_updated_at, label: "Mapping version", panel: :timing
      field :inserted_at, label: "Event time", panel: :timing
    end

    item_actions do
      strip_default([:edit, :delete])
    end
  end
end
