defmodule TcgCheapWeb.Admin.SealedProductAliasLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Phoenix.Plug, as: AuthenticationPlug
  alias TcgCheap.Accounts
  alias TcgCheap.Catalogue.SealedProductAlias
  alias TcgCheap.Core

  test "unauthenticated catalogue access redirects to sign in", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/admin/catalogue/aliases")) == "/admin/sign-in"
  end

  test "generic reads and catalogue actions require an administrator actor" do
    administrator = admin()
    product = product()
    manual = manual_alias(product, administrator)

    imported =
      Core.import_sealed_product_alias!(%{
        sealed_product_id: product.id,
        kind: "name",
        original_value: "Imported policy alias",
        source: "fixture"
      })

    refute Ash.can?({SealedProductAlias, :admin_create}, nil)
    refute Ash.can?({SealedProductAlias, :admin_catalogue}, nil)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(SealedProductAlias)
    assert Ash.can?({SealedProductAlias, :admin_create}, administrator)
    assert Ash.can?({SealedProductAlias, :admin_catalogue}, administrator)
    assert Ash.can?({manual, :admin_revise_pending}, administrator)
    refute Ash.can?({manual, :admin_revise_pending}, nil)
    refute Ash.can?({imported, :admin_revise_pending}, administrator)
  end

  test "administrator creates and revises a normalized manual alias", %{conn: conn} do
    product = product()
    unique = System.unique_integer([:positive])

    {:ok, new_view, _html} = live(authenticated_conn(conn), ~p"/admin/catalogue/aliases/new")

    new_view
    |> form("#resource-form",
      change: %{
        sealed_product_id: product.id,
        kind: "name",
        original_value: "  Manual   Alias #{unique}  "
      }
    )
    |> render_submit(%{"save-type" => "save"})

    [alias_record] = Ash.read!(SealedProductAlias, authorize?: false)
    assert alias_record.review_status == "pending"
    assert alias_record.normalized_value == "manual alias #{unique}"
    assert alias_record.sealed_product_id == product.id

    {:ok, edit_view, _html} =
      live(authenticated_conn(conn), ~p"/admin/catalogue/aliases/#{alias_record.id}/edit")

    assert has_element?(edit_view, "#resource-form")

    edit_view
    |> form("#resource-form", change: %{original_value: "Revised alias #{unique}"})
    |> render_submit(%{"save-type" => "save"})

    revised = Ash.get!(SealedProductAlias, alias_record.id, authorize?: false)
    assert revised.original_value == "Revised alias #{unique}"
    assert revised.normalized_value == "revised alias #{unique}"
  end

  test "invalid GTIN remains in the form and is not persisted", %{conn: conn} do
    product = product()

    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/catalogue/aliases/new")

    view
    |> form("#resource-form",
      change: %{
        sealed_product_id: product.id,
        kind: "ean",
        original_value: "4006381333932"
      }
    )
    |> render_submit(%{"save-type" => "save"})

    assert has_element?(view, "#resource-form", "must be a valid EAN/GTIN")
    assert [] == Ash.read!(SealedProductAlias, authorize?: false)
  end

  test "stale manual edit cannot overwrite a newer revision", %{conn: conn} do
    administrator = admin()
    alias_record = manual_alias(product(), administrator)

    {:ok, view, _html} =
      live(authenticated_conn(conn), ~p"/admin/catalogue/aliases/#{alias_record.id}/edit")

    newer =
      Core.admin_revise_pending_sealed_product_alias!(
        alias_record,
        %{
          expected_updated_at: alias_record.updated_at,
          original_value: "Newer operator alias"
        },
        actor: administrator
      )

    view
    |> form("#resource-form", change: %{original_value: "Stale operator alias"})
    |> render_submit(%{"save-type" => "save"})

    assert Ash.get!(SealedProductAlias, alias_record.id, authorize?: false).original_value ==
             newer.original_value

    assert has_element?(view, "#resource-form")
  end

  test "provider, approved, and rejected aliases are inspectable but read-only", %{conn: conn} do
    product = product()

    imported =
      Core.create_sealed_product_alias!(%{
        sealed_product_id: product.id,
        kind: "name",
        original_value: "Imported #{System.unique_integer([:positive])}",
        source: "fixture",
        source_id: "source-#{System.unique_integer([:positive])}",
        source_payload: %{secret: "must not be shown"}
      })

    approved =
      Core.approve_sealed_product_alias!(
        imported,
        %{expected_updated_at: imported.updated_at},
        authorize?: false
      )

    provider_pending =
      Core.import_sealed_product_alias!(%{
        sealed_product_id: product.id,
        kind: "name",
        original_value: "Provider pending #{System.unique_integer([:positive])}",
        source: "fixture"
      })

    rejected_alias = manual_alias(product, admin())

    rejected =
      Core.reject_sealed_product_alias!(
        rejected_alias,
        %{expected_updated_at: rejected_alias.updated_at},
        authorize?: false
      )

    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/catalogue/aliases")

    for alias_record <- [approved, provider_pending, rejected] do
      assert has_element?(view, "#row-item-#{alias_record.id}")
      assert has_element?(view, "#item-action-show-#{alias_record.id}")
      refute has_element?(view, "#item-action-edit-#{alias_record.id}")
      refute has_element?(view, "#item-action-delete-#{alias_record.id}")
    end

    refute has_element?(view, "#admin-catalogue", "must not be shown")

    {:ok, show_view, _html} =
      live(authenticated_conn(conn), ~p"/admin/catalogue/aliases/#{approved.id}/show")

    assert has_element?(show_view, ~s|a[href="/admin/catalogue/products/#{product.id}/show"]|)
    refute has_element?(show_view, "#admin-catalogue", "must not be shown")
  end

  defp authenticated_conn(conn) do
    conn
    |> init_test_session(%{})
    |> AuthenticationPlug.store_in_session(admin())
  end

  defp admin do
    Accounts.register_admin!(
      %{
        email: "alias-admin-#{System.unique_integer([:positive])}@example.test",
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple"
      },
      authorize?: false
    )
  end

  defp product do
    unique = System.unique_integer([:positive])

    Core.create_sealed_product_draft!(%{
      slug: "alias-product-#{unique}",
      name: "Alias Product #{unique}",
      product_type: "booster_box"
    })
  end

  defp manual_alias(product, administrator) do
    Core.admin_create_sealed_product_alias!(
      %{
        sealed_product_id: product.id,
        kind: "name",
        original_value: "Manual alias #{System.unique_integer([:positive])}"
      },
      actor: administrator
    )
  end
end
