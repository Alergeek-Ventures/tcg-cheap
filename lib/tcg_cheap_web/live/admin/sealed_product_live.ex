defmodule TcgCheapWeb.Admin.SealedProductLive do
  @moduledoc "Authenticated AshBackpex catalogue surface for sealed-product curation."

  use AshBackpex.LiveResource

  @product_type_options [
    {"Booster pack", "booster_pack"},
    {"Sleeved booster", "sleeved_booster"},
    {"Booster bundle", "booster_bundle"},
    {"Booster box", "booster_box"},
    {"Elite Trainer Box", "elite_trainer_box"},
    {"Tin", "tin"},
    {"Collection box", "collection_box"},
    {"Deck", "deck"},
    {"Trainer toolkit", "trainer_toolkit"},
    {"Other", "other"}
  ]

  backpex do
    resource TcgCheap.Catalogue.SealedProduct
    layout({TcgCheapWeb.Layouts, :admin})
    create_action(:admin_create_draft)
    read_action :admin_catalogue
    update_action(:revise_draft)
    update_changeset(&__MODULE__.update_changeset/3)
    singular_name("Sealed product")
    plural_name "Sealed products"
    init_order(%{by: :inserted_at, direction: :desc})
    per_page_default(15)
    per_page_options([15, 50])

    panels(
      identity: "Identity",
      market: "Polish market evidence",
      details: "Product details",
      reference_price: "Official reference price",
      image_provenance: "Image provenance",
      review: "Review state"
    )

    fields do
      field :name do
        searchable(true)
        panel(:identity)
      end

      field :slug do
        searchable(true)
        panel(:identity)
        help_text("Stable lowercase URL slug.")
      end

      field :product_type do
        module Backpex.Fields.Select
        options(@product_type_options)
        panel(:identity)
      end

      field :series_name do
        searchable(true)
        panel(:identity)
      end

      field :set_name do
        searchable(true)
        panel(:identity)
      end

      field :release_date do
        panel(:market)
      end

      field :msrp_pln do
        module Backpex.Fields.Number
        label("MSRP (PLN)")
        panel(:market)
        help_text("Leave blank when no authoritative Polish recommendation is known.")
      end

      field :msrp_source do
        label("MSRP source")
        panel(:market)
      end

      field :msrp_source_url do
        label("MSRP source URL")
        panel(:market)
      end

      field :image_url do
        label("Image URL")
        panel(:market)
      end

      field :officially_distributed do
        label("Official Polish distribution")
        panel(:market)
      end

      field :description, panel: :details

      field :contents do
        only([:show])
        panel(:details)
      end

      field :pack_count, module: Backpex.Fields.Number, panel: :details
      field :cards_per_pack, module: Backpex.Fields.Number, panel: :details
      field :official_url, panel: :details
      field :details_source, panel: :details
      field :details_source_url, panel: :details
      field :official_price_amount, module: Backpex.Fields.Number, panel: :reference_price
      field :official_price_currency, panel: :reference_price
      field :official_price_source, panel: :reference_price
      field :official_price_source_url, panel: :reference_price
      field :image_source, panel: :image_provenance
      field :image_source_url, panel: :image_provenance

      field :publication_status do
        only([:index, :show, :edit])
        readonly(true)
        panel(:review)
      end

      field :distribution_status do
        only([:index, :show, :edit])
        readonly(true)
        panel(:review)
      end

      field :approved_at do
        only([:show])
        panel(:review)
      end

      field :archived_at do
        only([:show])
        panel(:review)
      end

      field :inserted_at do
        only([:show])
        panel(:review)
      end

      field :updated_at do
        label("Record version")
        only([:show, :edit])
        readonly(true)
        panel(:review)
      end
    end

    item_actions do
      strip_default([:delete])
    end
  end

  def update_changeset(product, params, metadata) do
    actor = metadata |> Keyword.fetch!(:assigns) |> Map.fetch!(:current_user)

    params =
      params
      |> normalize_params()
      |> Map.put("expected_updated_at", product.updated_at)

    Ash.Changeset.for_update(product, :revise_draft, params, actor: actor)
  end

  defp normalize_params(params) do
    Map.new(params, fn
      {key, value} when is_binary(value) ->
        case String.trim(value) do
          "" -> {key, nil}
          value -> {key, value}
        end

      pair ->
        pair
    end)
  end
end
