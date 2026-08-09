defmodule TcgCheapWeb.Admin.SealedProductLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Phoenix.Plug, as: AuthenticationPlug
  alias TcgCheap.Accounts
  alias TcgCheap.Catalogue.SealedProduct
  alias TcgCheap.Core

  test "unauthenticated catalogue access redirects to sign in", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/admin/catalogue/products")) == "/admin/sign-in"
  end

  test "AshBackpex catalogue actions require an administrator actor" do
    admin = admin()

    refute Ash.can?({SealedProduct, :admin_create_draft}, nil)
    refute Ash.can?({SealedProduct, :admin_catalogue}, nil)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(SealedProduct)
    assert Ash.can?({SealedProduct, :admin_create_draft}, admin)
    assert Ash.can?({SealedProduct, :admin_catalogue}, admin)
    assert {:ok, _products} = Ash.read(SealedProduct, actor: admin)
  end

  test "authenticated catalogue lists products without destructive actions", %{conn: conn} do
    product = draft_product()
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/catalogue/products")

    assert has_element?(view, "#admin-catalogue")
    assert has_element?(view, "#row-item-#{product.id}", product.name)
    assert has_element?(view, "#item-action-show-#{product.id}")
    assert has_element?(view, "#item-action-edit-#{product.id}")
    refute has_element?(view, "#item-action-delete-#{product.id}")
    assert has_element?(view, ~s|a[href="/admin/review"]|)
    assert has_element?(view, ~s|a[href="/admin/operations"]|)
  end

  test "approved products remain inspectable but are not offered draft editing", %{conn: conn} do
    product = draft_product()

    complete_product =
      Core.revise_sealed_product_draft!(
        product,
        %{
          officially_distributed: true,
          release_date: Date.utc_today(),
          expected_updated_at: product.updated_at
        },
        authorize?: false
      )

    approved =
      Core.approve_sealed_product!(
        complete_product,
        %{expected_updated_at: complete_product.updated_at},
        authorize?: false
      )

    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/catalogue/products")

    assert has_element?(view, "#row-item-#{approved.id}", approved.name)
    assert has_element?(view, "#item-action-show-#{approved.id}")
    refute has_element?(view, "#item-action-edit-#{approved.id}")
  end

  test "administrator creates a draft through AshBackpex", %{conn: conn} do
    unique = System.unique_integer([:positive])
    slug = "backpex-product-#{unique}"
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/catalogue/products/new")

    view
    |> form("#resource-form",
      change: %{
        name: "Backpex Product #{unique}",
        slug: slug,
        product_type: "booster_box",
        officially_distributed: "false"
      }
    )
    |> render_submit(%{"save-type" => "save"})

    product = Core.get_sealed_product_by_slug!(slug)
    assert product.name == "Backpex Product #{unique}"
    assert product.publication_status == "draft"
  end

  test "administrator edits a draft with the displayed version", %{conn: conn} do
    product = draft_product()

    {:ok, view, _html} =
      live(authenticated_conn(conn), ~p"/admin/catalogue/products/#{product.id}/edit")

    view
    |> form("#resource-form", change: %{name: "Backpex Revised"})
    |> render_submit(%{"save-type" => "save"})

    assert Ash.get!(SealedProduct, product.id, authorize?: false).name == "Backpex Revised"
  end

  test "a stale edit cannot overwrite a newer review", %{conn: conn} do
    product = draft_product()

    {:ok, view, _html} =
      live(authenticated_conn(conn), ~p"/admin/catalogue/products/#{product.id}/edit")

    Core.revise_sealed_product_draft!(
      product,
      %{name: "Newer Review", expected_updated_at: product.updated_at},
      authorize?: false
    )

    view
    |> form("#resource-form", change: %{name: "Stale Backpex Edit"})
    |> render_submit(%{"save-type" => "save"})

    assert Ash.get!(SealedProduct, product.id, authorize?: false).name == "Newer Review"
    assert has_element?(view, "#resource-form")
  end

  defp authenticated_conn(conn) do
    admin = admin()

    conn
    |> init_test_session(%{})
    |> AuthenticationPlug.store_in_session(admin)
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

  defp draft_product do
    unique = System.unique_integer([:positive])

    Core.create_sealed_product_draft!(%{
      slug: "backpex-draft-#{unique}",
      name: "Backpex Draft #{unique}",
      product_type: "elite_trainer_box"
    })
  end
end
