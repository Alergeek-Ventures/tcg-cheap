defmodule TcgCheapWeb.SealedProductDetailLiveTest do
  import Phoenix.LiveViewTest
  use TcgCheapWeb.ConnCase, async: false

  alias TcgCheap.Core
  alias TcgCheapWeb.SealedProductDetailLive

  test "renders public identity, optional MSRP, and the limited-data state", %{conn: conn} do
    product = product(%{msrp_pln: Decimal.new("129.99"), msrp_source: "official product sheet"})

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    assert has_element?(view, ".sealed-detail-world")
    assert has_element?(view, "#decision-header")
    assert has_element?(view, "#decision-wordmark")
    assert has_element?(view, "#sealed-detail-title", product.name)
    assert has_element?(view, "#sealed-detail-type", "Booster Box")
    assert has_element?(view, "#sealed-detail-msrp", "129.99 PLN")
    assert has_element?(view, "#sealed-detail-msrp-provenance", "official product sheet")
    assert has_element?(view, "#sealed-detail-limited-data", "Buying bands")
    refute has_element?(view, "#sealed-detail-limited-data", "graph")
    assert has_element?(view, "#sealed-current-empty", "No current local offers yet")
    assert has_element?(view, "#sealed-sold-out-empty")
  end

  test "keeps current and sold-out evidence separate with safe direct links", %{conn: conn} do
    product = product()
    retailer = Core.register_retailer!(retailer_attrs())
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    current =
      listing(retailer.id, now, %{
        stock_status: "in_stock",
        current_price_pln: Decimal.new("99.90")
      })

    sold_out =
      listing(retailer.id, DateTime.add(now, -3600, :second), %{
        stock_status: "sold_out",
        current_price_pln: nil
      })

    map_listing(product.id, current)
    map_listing(product.id, sold_out)

    {:ok, view, _html} = live(conn, ~p"/sealed/#{product.slug}")

    assert has_element?(view, "#sealed-current-offers #sealed-current-offer-#{current.id}")
    assert has_element?(view, "#sealed-sold-out-offers #sealed-sold-out-offer-#{sold_out.id}")
    assert has_element?(view, "#sealed-current-price-#{current.id}", "99.90 PLN")
    assert has_element?(view, "#sealed-sold-out-price-#{sold_out.id}", "unavailable")

    assert has_element?(
             view,
             "#sealed-current-direct-link-#{current.id}[target='_blank'][rel='noopener noreferrer']"
           )

    assert has_element?(view, "#sealed-sold-out-checked-#{sold_out.id}", "UTC")

    assert has_element?(
             view,
             "#sealed-current-direct-link-#{current.id}[aria-label*='#{retailer.name}'][aria-label*='In stock']"
           )

    refute has_element?(view, "#sealed-current-empty")
    refute has_element?(view, "#sealed-sold-out-empty")
  end

  test "does not expose draft or nonexistent products", %{conn: conn} do
    draft =
      Core.create_sealed_product_draft!(%{
        slug: "hidden-#{suffix()}",
        name: "Hidden Draft",
        product_type: "tin"
      })

    {:ok, draft_view, _html} = live(conn, ~p"/sealed/#{draft.slug}")
    assert has_element?(draft_view, "#sealed-detail-not-found")
    refute has_element?(draft_view, "#sealed-detail-title", draft.name)

    {:ok, missing_view, _html} = live(conn, "/sealed/not-a-real-product-#{suffix()}")
    assert has_element?(missing_view, "#sealed-detail-not-found")
    refute has_element?(missing_view, "#sealed-current-offers")
  end

  test "data-read error component distinguishes an outage from not found" do
    html = render_component(&SealedProductDetailLive.data_error/1, flash: %{})
    document = LazyHTML.from_fragment(html)

    assert document
           |> LazyHTML.query("#sealed-detail-data-error")
           |> LazyHTML.to_tree() != []

    assert document
           |> LazyHTML.query("#sealed-detail-data-error-back")
           |> LazyHTML.to_tree() != []

    assert document
           |> LazyHTML.query("#sealed-detail-not-found")
           |> LazyHTML.to_tree() == []
  end

  defp product(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          slug: "detail-product-#{suffix()}",
          name: "Detail Booster Box",
          product_type: "booster_box",
          officially_distributed: true,
          release_date: Date.utc_today()
        },
        overrides
      )

    draft = Core.create_sealed_product_draft!(attrs)

    Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
      authorize?: false
    )
  end

  defp retailer_attrs do
    %{
      slug: "detail-retailer-#{suffix()}",
      source_key: "detail-source-#{suffix()}",
      name: "Detail Shop",
      category: "regular_retailer",
      homepage_url: "https://shop.example"
    }
  end

  defp listing(retailer_id, checked_at, overrides) do
    Core.ingest_retailer_listing!(
      Map.merge(
        %{
          retailer_id: retailer_id,
          source_listing_id: "detail-listing-#{suffix()}",
          source_title: "Detail product",
          direct_url: "https://shop.example/product",
          current_price_pln: Decimal.new("10.00"),
          stock_status: "in_stock",
          first_seen_at: checked_at,
          last_seen_at: checked_at,
          last_checked_at: checked_at
        },
        overrides
      )
    )
  end

  defp map_listing(product_id, listing) do
    review =
      Core.create_review_listing_mapping!(%{
        retailer_listing_id: listing.id,
        confidence: Decimal.new("1"),
        evidence: %{"source" => "test"},
        reason: "test"
      })

    Core.approve_listing_mapping!(
      review,
      %{
        confirmed_product_id: product_id,
        confidence: Decimal.new("1"),
        evidence: %{"source" => "test"},
        expected_updated_at: review.updated_at
      },
      authorize?: false
    )
  end

  defp suffix, do: System.unique_integer([:positive])
end
