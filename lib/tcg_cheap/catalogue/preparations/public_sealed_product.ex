defmodule TcgCheap.Catalogue.Preparations.PublicSealedProduct do
  @moduledoc "Restricts sealed-product reads to approved, released, factually complete products."
  use Ash.Resource.Preparation

  import Ash.Expr
  require Ash.Query

  @pack_bearing_types ~w(
    booster_pack
    sleeved_booster
    booster_bundle
    booster_box
    elite_trainer_box
    tin
    collection_box
    trainer_toolkit
  )

  @impl true
  def prepare(query, _opts, _context) do
    query
    |> Ash.Query.filter(expr(^public_filter()))
    |> Ash.Query.load(
      [public_image_mappings: [:id, :retailer_listing_id, retailer_listing: [:image_url]]],
      strict?: true
    )
  end

  defp public_filter do
    expr(^publication_filter() and ^factual_filter() and ^image_filter() and ^pack_filter())
  end

  defp publication_filter do
    expr(
      publication_status == "approved" and
        release_date <= today() and
        officially_distributed == true and
        market == "PL" and
        language == "en" and
        distribution_status in ["current", "discontinued"]
    )
  end

  defp factual_filter do
    expr(
      not is_nil(description) and fragment("btrim(?)", description) != "" and
        contents != [] and
        not is_nil(official_url) and fragment("btrim(?)", official_url) != "" and
        not is_nil(details_source) and fragment("btrim(?)", details_source) != "" and
        not is_nil(details_source_url) and fragment("btrim(?)", details_source_url) != ""
    )
  end

  defp image_filter do
    expr(^image_tuple_present() or exists(public_image_mappings))
  end

  defp pack_filter do
    pack_bearing_types = @pack_bearing_types

    expr(
      product_type not in ^pack_bearing_types or
        (not is_nil(pack_count) and pack_count > 0 and
           not is_nil(cards_per_pack) and cards_per_pack > 0)
    )
  end

  defp image_tuple_present do
    expr(
      not is_nil(image_url) and fragment("btrim(?)", image_url) != "" and
        not is_nil(image_source) and fragment("btrim(?)", image_source) != "" and
        not is_nil(image_source_url) and fragment("btrim(?)", image_source_url) != ""
    )
  end
end
