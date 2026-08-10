defmodule TcgCheapWeb.Admin.ListingProductMappingLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Phoenix.Plug, as: AuthenticationPlug
  alias TcgCheap.Accounts
  alias TcgCheap.Core

  test "mapping catalogue roots require authentication", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/admin/catalogue/mappings")) == "/admin/sign-in"
    assert redirected_to(get(conn, ~p"/admin/catalogue/mapping-history")) == "/admin/sign-in"

    assert redirected_to(get(conn, ~p"/admin/catalogue/mappings/not-a-uuid/correct")) ==
             "/admin/sign-in"
  end

  test "administrator can inspect mapping and history without evidence payloads", %{conn: conn} do
    admin = admin()
    retailer = retailer()
    listing = listing(retailer)
    product = product()

    mapping =
      Core.create_review_listing_mapping!(%{
        retailer_listing_id: listing.id,
        candidate_product_id: product.id,
        confidence: Decimal.new("0.7"),
        evidence: %{method: "ean", provider_secret: "do-not-render"},
        reason: "Needs confirmation"
      })

    {:ok, mapping_view, _html} =
      live(authenticated_conn(conn, admin), ~p"/admin/catalogue/mappings")

    assert has_element?(mapping_view, "#row-item-#{mapping.id}", listing.source_title)
    assert has_element?(mapping_view, "#item-action-reopen-#{mapping.id}") == false
    refute has_element?(mapping_view, "#item-action-edit-#{mapping.id}")
    refute has_element?(mapping_view, "#item-action-delete-#{mapping.id}")
    refute has_element?(mapping_view, "#admin-catalogue", "do-not-render")

    {:ok, show_view, _html} =
      live(authenticated_conn(conn, admin), ~p"/admin/catalogue/mappings/#{mapping.id}/show")

    assert has_element?(show_view, "dt", "Reason")
    assert has_element?(show_view, "a[href=\"/admin/catalogue/products/#{product.id}/show\"]")
    refute has_element?(show_view, "#admin-catalogue", "provider_secret")

    {:ok, history_view, _html} =
      live(authenticated_conn(conn, admin), ~p"/admin/catalogue/mapping-history")

    assert has_element?(history_view, "#row-item-#{mapping.id}") == false
    assert has_element?(history_view, "a[href=\"/admin/catalogue/mappings/#{mapping.id}/show\"]")
    assert has_element?(history_view, "td", "created")
  end

  test "reopen is offered only for terminal mappings", %{conn: conn} do
    admin = admin()
    retailer = retailer()
    terminal_listing = listing(retailer)
    pending_listing = listing(retailer)
    confirmed_product = product()

    confirmed_product =
      Core.approve_sealed_product!(
        confirmed_product,
        %{expected_updated_at: confirmed_product.updated_at},
        authorize?: false
      )

    terminal =
      Core.create_matched_listing_mapping!(
        %{
          retailer_listing_id: terminal_listing.id,
          confirmed_product_id: confirmed_product.id,
          confidence: Decimal.new("1"),
          evidence: %{method: "admin_review"}
        },
        authorize?: false
      )

    pending = Core.create_pending_listing_mapping!(%{retailer_listing_id: pending_listing.id})

    assert Ash.can?({terminal, :reopen}, admin)
    refute Ash.can?({pending, :reopen}, admin)

    {:ok, view, _html} = live(authenticated_conn(conn, admin), ~p"/admin/catalogue/mappings")

    assert has_element?(
             view,
             "#item-action-reopen-#{terminal.id}[href=\"/admin/catalogue/mappings/#{terminal.id}/correct\"]"
           )

    refute has_element?(view, "#item-action-reopen-#{pending.id}")
  end

  test "administrator reopens a terminal mapping into the review queue", %{conn: conn} do
    admin = admin()
    product = approved_product()

    mapping =
      Core.create_matched_listing_mapping!(%{
        retailer_listing_id: listing(retailer()).id,
        confirmed_product_id: product.id,
        confidence: Decimal.new("1"),
        evidence: %{method: "admin_review"}
      })

    {:ok, correction_view, _html} =
      live(authenticated_conn(conn, admin), ~p"/admin/catalogue/mappings/#{mapping.id}/correct")

    assert has_element?(correction_view, "#mapping-correction-form")

    result =
      correction_view
      |> form("#mapping-correction-form", mapping_correction: %{reason: "Operator correction"})
      |> render_submit()

    reopened = Core.get_listing_mapping!(mapping.retailer_listing_id)

    assert {reopened.status, reopened.candidate_product_id, reopened.confirmed_product_id} ==
             {"review", product.id, nil}

    assert {:ok, decisions} =
             Core.list_listing_mapping_decision_history(mapping.id, authorize?: false)

    assert %{
             event: "reopened",
             actor_type: "administrator",
             actor_id: actor_id,
             reason: "Operator correction"
           } =
             List.last(decisions)

    assert actor_id == admin.id

    {:ok, review_view, _html} =
      follow_redirect(result, authenticated_conn(conn, admin), "/admin/review#listing-mappings")

    assert has_element?(review_view, "#listing-mapping-queue article", product.name)
  end

  test "stale reopen shows a safe error without adding another decision", %{conn: conn} do
    admin = admin()
    product = approved_product()

    mapping =
      Core.create_matched_listing_mapping!(%{
        retailer_listing_id: listing(retailer()).id,
        confirmed_product_id: product.id,
        confidence: Decimal.new("1"),
        evidence: %{method: "admin_review"}
      })

    {:ok, view, _html} =
      live(authenticated_conn(conn, admin), ~p"/admin/catalogue/mappings/#{mapping.id}/correct")

    Core.reopen_listing_mapping!(
      mapping,
      %{expected_updated_at: mapping.updated_at, reason: "Concurrent correction"},
      actor: admin
    )

    assert {:ok, before_decisions} =
             Core.list_listing_mapping_decision_history(mapping.id, authorize?: false)

    view
    |> form("#mapping-correction-form", mapping_correction: %{reason: "Concurrent correction"})
    |> render_submit()

    assert has_element?(view, "#flash-error", "The mapping could not be reopened")

    assert {:ok, after_decisions} =
             Core.list_listing_mapping_decision_history(mapping.id, authorize?: false)

    assert length(after_decisions) == length(before_decisions)
    assert Core.get_listing_mapping!(mapping.retailer_listing_id).status == "review"
  end

  test "blank correction reason is rejected", %{conn: conn} do
    admin = admin()

    mapping =
      Core.create_matched_listing_mapping!(%{
        retailer_listing_id: listing(retailer()).id,
        confirmed_product_id: approved_product().id,
        confidence: Decimal.new("1"),
        evidence: %{method: "admin_review"}
      })

    {:ok, view, _html} =
      live(authenticated_conn(conn, admin), ~p"/admin/catalogue/mappings/#{mapping.id}/correct")

    view
    |> form("#mapping-correction-form", mapping_correction: %{reason: "   "})
    |> render_submit()

    assert has_element?(view, "#flash-error", "Enter a reason")
    assert has_element?(view, "#mapping-correction-reason")
    assert Core.get_listing_mapping!(mapping.retailer_listing_id).status == "matched"
  end

  defp authenticated_conn(conn, admin) do
    conn
    |> init_test_session(%{})
    |> AuthenticationPlug.store_in_session(admin)
  end

  defp admin do
    Accounts.register_admin!(
      %{
        email: "mapping-admin-#{System.unique_integer([:positive])}@example.test",
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple"
      },
      authorize?: false
    )
  end

  defp retailer do
    unique = System.unique_integer([:positive])

    Core.register_retailer!(%{
      slug: "mapping-shop-#{unique}",
      source_key: "mapping-shop-#{unique}",
      name: "Mapping Shop",
      category: "lgs",
      homepage_url: "https://shop.example"
    })
  end

  defp listing(retailer) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Core.ingest_retailer_listing!(%{
      retailer_id: retailer.id,
      source_listing_id: "mapping-listing-#{System.unique_integer([:positive])}",
      source_title: "Mapping Booster Box",
      direct_url: "https://shop.example/products/booster-box",
      first_seen_at: now,
      last_seen_at: now,
      last_checked_at: now
    })
  end

  defp product do
    Core.create_sealed_product_draft!(%{
      slug: "mapping-product-#{System.unique_integer([:positive])}",
      name: "Mapping Product",
      product_type: "booster_box",
      officially_distributed: true,
      release_date: Date.utc_today()
    })
  end

  defp approved_product do
    product = product()

    Core.approve_sealed_product!(
      product,
      %{expected_updated_at: product.updated_at},
      authorize?: false
    )
  end
end
