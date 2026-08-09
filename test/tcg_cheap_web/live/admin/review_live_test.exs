defmodule TcgCheapWeb.Admin.ReviewLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Phoenix.Plug, as: AuthenticationPlug
  alias TcgCheap.Accounts
  alias TcgCheap.Catalogue.{ListingProductMapping, SealedProduct, SealedProductAlias}
  alias TcgCheap.Core

  test "an administrator can revise and approve a complete product draft", %{conn: conn} do
    product =
      draft_product(%{
        name: "Review Me",
        officially_distributed: true,
        release_date: Date.utc_today()
      })

    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/review")

    assert has_element?(view, "#admin-review")
    assert has_element?(view, "#product-review-form-#{product.id}")
    assert has_element?(view, "#draft-product-queue article", "Review Me")

    view
    |> form("#product-review-form-#{product.id}",
      product: %{id: product.id, name: "Reviewed Product"}
    )
    |> render_submit()

    assert Core.get_sealed_product_by_slug!(product.slug).name == "Reviewed Product"

    view |> element("#approve-product-#{product.id}") |> render_click()

    refute has_element?(view, "#product-review-form-#{product.id}")
    assert Ash.get!(SealedProduct, product.id, authorize?: false).publication_status == "approved"
  end

  test "a stale product form cannot overwrite a newer review", %{conn: conn} do
    product = draft_product()
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/review")

    Core.revise_sealed_product_draft!(
      product,
      %{name: "Newer Review", expected_updated_at: product.updated_at},
      authorize?: false
    )

    view
    |> form("#product-review-form-#{product.id}",
      product: %{id: product.id, name: "Stale Review"}
    )
    |> render_submit()

    assert Core.get_sealed_product_by_slug!(product.slug).name == "Newer Review"
    assert has_element?(view, "#product-review-form-#{product.id}")
  end

  test "an administrator can approve and reject aliases with product evidence loaded", %{
    conn: conn
  } do
    product = draft_product()
    approved_alias = alias_record(product, "First Alias")
    rejected_alias = alias_record(product, "Second Alias")
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/review")

    assert has_element?(view, "#pending-alias-queue article", product.name)

    view |> element("#approve-alias-#{approved_alias.id}") |> render_click()
    view |> element("#reject-alias-#{rejected_alias.id}") |> render_click()

    refute has_element?(view, "#approve-alias-#{approved_alias.id}")
    refute has_element?(view, "#reject-alias-#{rejected_alias.id}")

    assert Ash.get!(SealedProductAlias, approved_alias.id, authorize?: false).review_status ==
             "approved"

    assert Ash.get!(SealedProductAlias, rejected_alias.id, authorize?: false).review_status ==
             "rejected"
  end

  test "an administrator confirms or rejects listing mappings one row at a time", %{conn: conn} do
    target = approved_product(%{name: "Confirmed Product"})
    shop = retailer()
    first_listing = listing(shop, "listing-approve")
    second_listing = listing(shop, "listing-reject")

    approve_mapping =
      Core.create_review_listing_mapping!(%{
        retailer_listing_id: first_listing.id,
        candidate_product_id: target.id,
        confidence: Decimal.new("0.7"),
        evidence: %{method: "ean"},
        reason: "Human confirmation required"
      })

    reject_mapping =
      Core.create_pending_listing_mapping!(%{retailer_listing_id: second_listing.id})

    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/review")

    assert has_element?(view, "#mapping-source-#{approve_mapping.id}")

    view
    |> form("#approve-mapping-form-#{approve_mapping.id}",
      mapping: %{id: approve_mapping.id, confirmed_product_id: target.id}
    )
    |> render_submit()

    assert Ash.get!(ListingProductMapping, approve_mapping.id, authorize?: false).status ==
             "matched"

    view
    |> form("#reject-mapping-form-#{reject_mapping.id}",
      mapping: %{id: reject_mapping.id, reason: "Not an official English product"}
    )
    |> render_submit()

    rejected = Ash.get!(ListingProductMapping, reject_mapping.id, authorize?: false)
    assert {rejected.status, rejected.reason} == {"rejected", "Not an official English product"}
    refute has_element?(view, "#reject-mapping-form-#{reject_mapping.id}")
  end

  defp authenticated_conn(conn) do
    email = "review-admin-#{System.unique_integer([:positive])}@example.test"

    admin =
      Accounts.register_admin!(
        %{
          email: email,
          password: "correct horse battery staple",
          password_confirmation: "correct horse battery staple"
        },
        authorize?: false
      )

    conn
    |> init_test_session(%{})
    |> AuthenticationPlug.store_in_session(admin)
  end

  defp draft_product(overrides \\ %{}) do
    Core.create_sealed_product_draft!(
      Map.merge(
        %{
          slug: "review-product-#{System.unique_integer([:positive])}",
          name: "Review Product",
          product_type: "booster_box"
        },
        overrides
      )
    )
  end

  defp approved_product(overrides) do
    product =
      overrides
      |> Map.merge(%{officially_distributed: true, release_date: Date.utc_today()})
      |> draft_product()

    Core.approve_sealed_product!(product, %{expected_updated_at: product.updated_at},
      authorize?: false
    )
  end

  defp alias_record(product, value) do
    Core.create_sealed_product_alias!(%{
      sealed_product_id: product.id,
      kind: "name",
      original_value: value
    })
  end

  defp retailer do
    unique = System.unique_integer([:positive])

    Core.register_retailer!(%{
      slug: "review-shop-#{unique}",
      source_key: "review-shop-#{unique}",
      name: "Review Shop",
      category: "lgs",
      homepage_url: "https://shop.example"
    })
  end

  defp listing(shop, source_listing_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Core.ingest_retailer_listing!(%{
      retailer_id: shop.id,
      source_listing_id: "#{source_listing_id}-#{System.unique_integer([:positive])}",
      source_title: "Retail Booster Box",
      direct_url: "https://shop.example/products/booster-box",
      current_price_pln: Decimal.new("199.99"),
      stock_status: "in_stock",
      first_seen_at: now,
      last_seen_at: now,
      last_checked_at: now
    })
  end
end
