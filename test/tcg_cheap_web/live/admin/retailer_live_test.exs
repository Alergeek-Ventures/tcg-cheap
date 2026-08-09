defmodule TcgCheapWeb.Admin.RetailerLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Phoenix.Plug, as: AuthenticationPlug
  alias TcgCheap.Accounts
  alias TcgCheap.Catalogue.{Retailer, RetailerListing}
  alias TcgCheap.Core

  test "unauthenticated catalogue roots redirect to sign in", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/admin/catalogue/retailers")) == "/admin/sign-in"
    assert redirected_to(get(conn, ~p"/admin/catalogue/listings")) == "/admin/sign-in"
  end

  test "catalogue actions require an administrator actor while ingest remains operational" do
    admin = admin()

    refute Ash.can?({Retailer, :admin_create}, nil)
    refute Ash.can?({Retailer, :admin_catalogue}, nil)
    refute Ash.can?({RetailerListing, :admin_catalogue}, nil)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Retailer)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(RetailerListing)
    assert Ash.can?({Retailer, :admin_create}, admin)
    assert Ash.can?({Retailer, :admin_catalogue}, admin)
    assert Ash.can?({RetailerListing, :admin_catalogue}, admin)

    assert {:ok, retailer} = Core.register_retailer(unique_retailer())
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:ok, _listing} =
             Core.ingest_retailer_listing(%{
               retailer_id: retailer.id,
               source_listing_id: "operational-listing-#{System.unique_integer([:positive])}",
               source_title: "Operational listing",
               direct_url: "https://retailer.example/products/operational",
               first_seen_at: now,
               last_seen_at: now,
               last_checked_at: now
             })
  end

  test "administrator can inspect retailers and listing projections", %{conn: conn} do
    secret = "provider-secret-#{System.unique_integer([:positive])}"

    retailer =
      unique_retailer()
      |> Map.merge(%{metadata: %{secret => true}, source_payload: %{secret => true}})
      |> Core.register_retailer!()

    listing = listing(retailer)

    {:ok, retailer_view, _html} = live(authenticated_conn(conn), ~p"/admin/catalogue/retailers")
    assert has_element?(retailer_view, "#row-item-#{retailer.id}", retailer.name)
    assert has_element?(retailer_view, "#item-action-show-#{retailer.id}")
    assert has_element?(retailer_view, "#item-action-edit-#{retailer.id}")
    refute has_element?(retailer_view, "#item-action-delete-#{retailer.id}")

    {:ok, retailer_show, _html} =
      live(authenticated_conn(conn), ~p"/admin/catalogue/retailers/#{retailer.id}/show")

    assert has_element?(retailer_show, "dt", "Name")
    refute has_element?(retailer_show, "#admin-catalogue", secret)

    {:ok, listing_view, _html} = live(authenticated_conn(conn), ~p"/admin/catalogue/listings")
    assert has_element?(listing_view, "#row-item-#{listing.id}", retailer.name)
    refute has_element?(listing_view, "#item-action-edit-#{listing.id}")
    refute has_element?(listing_view, "#item-action-delete-#{listing.id}")
    refute has_element?(listing_view, "#admin-catalogue", "hidden-provider-value")

    {:ok, listing_show, _html} =
      live(authenticated_conn(conn), ~p"/admin/catalogue/listings/#{listing.id}/show")

    assert has_element?(listing_show, "dt", "Source title")
    assert has_element?(listing_show, "dt", "Normalized title")

    assert has_element?(
             listing_show,
             ~s|a[href="/admin/catalogue/retailers/#{retailer.id}/show"]|
           )

    assert has_element?(listing_show, "dt", "Current price (PLN)")
  end

  test "administrator creates a retailer and edits category and status", %{conn: conn} do
    unique = System.unique_integer([:positive])
    slug = "backpex-retailer-#{unique}"

    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/catalogue/retailers/new")

    view
    |> form("#resource-form",
      change: %{
        name: "Backpex Retailer #{unique}",
        source_key: "backpex-source-#{unique}",
        slug: slug,
        category: "regular_retailer",
        homepage_url: "https://retailer.example"
      }
    )
    |> render_submit(%{"save-type" => "save"})

    retailer = Core.get_retailer_by_source_key!("backpex-source-#{unique}")
    assert retailer.category == "regular_retailer"

    {:ok, edit_view, _html} =
      live(authenticated_conn(conn), ~p"/admin/catalogue/retailers/#{retailer.id}/edit")

    assert has_element?(edit_view, "#resource-form_category")

    edit_view
    |> form("#resource-form", change: %{category: "lgs", status: "disabled"})
    |> render_submit(%{"save-type" => "save"})

    updated = Ash.get!(Retailer, retailer.id, authorize?: false)

    assert updated.category == "lgs"
    assert updated.status == "disabled"
  end

  test "stale retailer edit cannot overwrite a newer update", %{conn: conn} do
    retailer = retailer()

    {:ok, view, _html} =
      live(authenticated_conn(conn), ~p"/admin/catalogue/retailers/#{retailer.id}/edit")

    newer =
      Ash.update!(
        retailer,
        %{name: "Newer operator update", expected_updated_at: retailer.updated_at},
        action: :admin_update,
        authorize?: false
      )

    assert {:error, stale_error} =
             Ash.update(
               retailer,
               %{name: "Stale domain update", expected_updated_at: retailer.updated_at},
               action: :admin_update,
               authorize?: false
             )

    assert Exception.message(stale_error) =~ "record changed after it was loaded"

    view
    |> form("#resource-form", change: %{name: "Stale operator update"})
    |> render_submit(%{"save-type" => "save"})

    assert Ash.get!(Retailer, retailer.id, authorize?: false).name == newer.name
    assert has_element?(view, "#resource-form")
  end

  defp authenticated_conn(conn) do
    conn
    |> init_test_session(%{})
    |> AuthenticationPlug.store_in_session(admin())
  end

  defp admin do
    Accounts.register_admin!(
      %{
        email: "catalogue-admin-#{System.unique_integer([:positive])}@example.test",
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple"
      },
      authorize?: false
    )
  end

  defp unique_retailer do
    unique = System.unique_integer([:positive])

    %{
      slug: "fixture-retailer-#{unique}",
      source_key: "fixture-source-#{unique}",
      name: "Fixture Retailer #{unique}",
      category: "lgs",
      homepage_url: "https://retailer.example"
    }
  end

  defp retailer do
    {:ok, retailer} = Core.register_retailer(unique_retailer())
    retailer
  end

  defp listing(retailer) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    unique = System.unique_integer([:positive])

    Core.ingest_retailer_listing!(%{
      retailer_id: retailer.id,
      source_listing_id: "fixture-listing-#{unique}",
      source_title: "Fixture Booster Box",
      direct_url: "https://retailer.example/products/booster-box",
      current_price_pln: Decimal.new("199.99"),
      stock_status: "in_stock",
      first_seen_at: now,
      last_seen_at: now,
      last_checked_at: now,
      source_payload: %{provider: "hidden-provider-value"}
    })
  end
end
