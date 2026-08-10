defmodule TcgCheapWeb.Admin.CardPrintingMappingDecisionLive do
  @moduledoc "Authenticated, read-only Cardmarket mapping decision history."

  use AshBackpex.LiveResource

  backpex do
    resource TcgCheap.Catalogue.CardPrintingMappingDecision
    layout({TcgCheapWeb.Layouts, :admin})
    read_action(:admin_catalogue)
    load([:card_printing])
    singular_name("Card mapping decision")
    plural_name("Card mapping decisions")
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

      field :card_printing do
        module AshBackpex.Fields.BelongsTo
        display_field(:name)
        live_resource(TcgCheapWeb.Admin.CardPrintingLive)
        panel(:mapping)
      end

      field :from_cardmarket_product_id, label: "From Cardmarket ID", panel: :mapping
      field :cardmarket_product_id, label: "To Cardmarket ID", panel: :mapping
      field :mapping_authority, label: "Authority", panel: :decision
      field :reason, label: "Reason", panel: :decision
      field :source_mapping_evidence_at, label: "Source mapping evidence", panel: :timing
      field :printing_version_at, label: "Card version", panel: :timing
      field :actor_type, label: "Actor type", panel: :actor
      field :actor_email, label: "Actor email", panel: :actor
      field :inserted_at, label: "Event time", panel: :timing
    end

    item_actions do
      strip_default([:edit, :delete])
    end
  end
end
