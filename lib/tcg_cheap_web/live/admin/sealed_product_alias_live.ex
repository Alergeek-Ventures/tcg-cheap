defmodule TcgCheapWeb.Admin.SealedProductAliasLive do
  @moduledoc "Authenticated AshBackpex catalogue surface for sealed-product aliases."

  use AshBackpex.LiveResource

  @kind_options [{"Name", "name"}, {"EAN / GTIN", "ean"}]

  backpex do
    resource TcgCheap.Catalogue.SealedProductAlias
    layout({TcgCheapWeb.Layouts, :admin})
    create_action(:admin_create)
    read_action(:admin_catalogue)
    update_action(:admin_revise_pending)
    update_changeset(&__MODULE__.update_changeset/3)
    load([:sealed_product])
    singular_name("Sealed-product alias")
    plural_name("Sealed-product aliases")
    init_order(%{by: :id, direction: :asc})
    per_page_default(15)
    per_page_options([15, 50])

    panels(identity: "Identity", review: "Review", origin: "Origin evidence")

    fields do
      field :sealed_product do
        module AshBackpex.Fields.BelongsTo
        display_field(:name)
        typeahead(true)
        typeahead_limit(10)
        live_resource(TcgCheapWeb.Admin.SealedProductLive)
        panel(:identity)
      end

      field :kind do
        module Backpex.Fields.Select
        options(@kind_options)
        panel(:identity)
      end

      field :original_value do
        searchable(true)
        panel(:identity)
      end

      field :normalized_value do
        searchable(true)
        only([:index, :show, :edit])
        readonly(true)
        panel(:identity)
      end

      field :review_status do
        only([:index, :show, :edit])
        readonly(true)
        panel(:review)
      end

      field :approved_at do
        only([:show])
        readonly(true)
        panel(:review)
      end

      field :rejected_at do
        only([:show])
        readonly(true)
        panel(:review)
      end

      field :inserted_at do
        only([:show])
        readonly(true)
        panel(:review)
      end

      field :updated_at do
        only([:show, :edit])
        readonly(true)
        label("Record version")
        panel(:review)
      end

      field :source do
        only([:index, :show, :edit])
        readonly(true)
        label("Source")
        panel(:origin)
      end

      field :source_id do
        only([:show])
        readonly(true)
        label("Source reference")
        panel(:origin)
      end
    end

    item_actions do
      strip_default([:delete])
    end
  end

  def update_changeset(alias_record, params, metadata) do
    actor = metadata |> Keyword.fetch!(:assigns) |> Map.fetch!(:current_user)
    params = Map.put(params, "expected_updated_at", alias_record.updated_at)

    Ash.Changeset.for_update(alias_record, :admin_revise_pending, params, actor: actor)
  end
end
