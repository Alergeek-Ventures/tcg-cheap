defmodule TcgCheapWeb.Admin.RetailerLive do
  @moduledoc "Authenticated AshBackpex catalogue surface for retailer curation."

  use AshBackpex.LiveResource

  @category_options [{"Regular retailer", "regular_retailer"}, {"LGS", "lgs"}]
  @status_options [{"Active", "active"}, {"Disabled", "disabled"}]

  backpex do
    resource TcgCheap.Catalogue.Retailer
    layout({TcgCheapWeb.Layouts, :admin})
    create_action(:admin_create)
    read_action(:admin_catalogue)
    update_action(:admin_update)
    update_changeset(&__MODULE__.update_changeset/3)
    singular_name("Retailer")
    plural_name("Retailers")
    # AshBackpex 0.1.12 applies one UI sort on its generic query path; the unique slug keeps
    # pagination deterministic even when retailer names collide.
    init_order(%{by: :slug, direction: :asc})
    per_page_default(15)
    per_page_options([15, 50])

    panels(identity: "Identity", configuration: "Configuration", record: "Record")

    fields do
      field :name do
        searchable(true)
        panel(:identity)
      end

      field :source_key do
        searchable(true)
        label("Source key")
        panel(:identity)
        readonly(fn assigns -> assigns.live_action == :edit end)
        help_text("Provider identity is fixed after creation.")
      end

      field :slug do
        searchable(true)
        help_text("Stable lowercase URL slug.")
        panel(:identity)
      end

      field :category do
        module Backpex.Fields.Select
        options(@category_options)
        panel(:configuration)
      end

      field :status do
        module Backpex.Fields.Select
        options(@status_options)
        only([:index, :show, :edit])
        panel(:configuration)
      end

      field :homepage_url do
        module Backpex.Fields.URL
        label("Homepage URL")
        panel(:configuration)
      end

      field :inserted_at do
        only([:show])
        panel(:record)
      end

      field :updated_at do
        only([:show, :edit])
        readonly(true)
        label("Record version")
        panel(:record)
      end
    end

    item_actions do
      strip_default([:delete])
    end
  end

  def update_changeset(retailer, params, metadata) do
    actor = metadata |> Keyword.fetch!(:assigns) |> Map.fetch!(:current_user)
    params = Map.put(params, "expected_updated_at", retailer.updated_at)

    Ash.Changeset.for_update(retailer, :admin_update, params, actor: actor)
  end
end
