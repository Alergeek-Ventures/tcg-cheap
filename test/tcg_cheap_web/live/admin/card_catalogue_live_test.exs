defmodule TcgCheapWeb.Admin.CardCatalogueLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TcgCheap.Accounts
  alias TcgCheap.Catalogue.CardPrinting
  alias TcgCheap.Catalogue.CardSet
  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.SingleValuationSnapshot

  test "catalogue roots redirect unauthenticated visitors", %{conn: conn} do
    for path <- [
          "/admin/catalogue/card-sets",
          "/admin/catalogue/cards",
          "/admin/catalogue/valuations"
        ] do
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, path)
    end
  end

  test "catalogue reads are administrator-only" do
    admin = admin_fixture()

    assert {:error, _} = Ash.read(CardSet, domain: Core)
    assert {:error, _} = Ash.read(CardPrinting, domain: Core)
    assert {:error, _} = Ash.read(SingleValuationSnapshot, domain: Core)

    assert {:ok, _} = Core.list_admin_card_sets(actor: admin)
    assert {:ok, _} = Core.list_admin_card_printings(actor: admin)
    assert {:ok, _} = Core.list_admin_single_valuation_snapshots(actor: admin)
  end

  test "anonymous card search keeps only its public relationships authorized" do
    {card, set, current, _archived} = catalogue_fixture()

    assert {:ok, [result]} = Core.search_card_printings(card.name)
    assert result.card_set.tcgdex_id == set.tcgdex_id
    valuation = result.tcgdex_cardmarket_v1_current_valuation
    assert valuation.current? == true
    assert %Ash.NotLoaded{} = result.variant_data
    assert %Ash.NotLoaded{} = result.source_payload
    assert %Ash.NotLoaded{} = result.search_name
    assert %Ash.NotLoaded{} = result.card_set.source_payload

    loaded_valuation = Ash.load!(current, :card_printing)
    assert loaded_valuation.card_printing.tcgdex_id == card.tcgdex_id
    assert %Ash.NotLoaded{} = loaded_valuation.card_printing.variant_data
    assert %Ash.NotLoaded{} = loaded_valuation.card_printing.source_payload
  end

  test "authenticated catalogue pages expose safe card provenance and immutable history", %{
    conn: conn
  } do
    {card, set, current, archived} = catalogue_fixture()
    conn = authenticated_conn(conn)

    {:ok, set_view, _} = live(conn, "/admin/catalogue/card-sets")
    assert has_element?(set_view, "a[href*='/admin/catalogue/card-sets/#{set.id}/show']")
    assert has_element?(set_view, "td", set.tcgdex_id)
    assert has_element?(set_view, "td", set.name)
    refute has_element?(set_view, "a[href*='/edit']")
    refute has_element?(set_view, "button", "Delete")
    refute has_element?(set_view, "td", "source-payload-secret")

    {:ok, set_show, _} = live(conn, "/admin/catalogue/card-sets/#{set.id}/show")
    assert has_element?(set_show, "p", set.series_name)
    assert has_element?(set_show, "a[href='#{set.logo_url}']")
    refute has_element?(set_show, "body", "source-payload-secret")
    refute has_element?(set_show, "a[href*='/edit']")
    refute has_element?(set_show, "button", "Delete")

    {:ok, card_view, _} = live(conn, "/admin/catalogue/cards")
    assert has_element?(card_view, "a[href*='/admin/catalogue/cards/#{card.id}/show']")
    assert has_element?(card_view, "td", card.tcgdex_id)
    assert has_element?(card_view, "td", card.name)
    assert has_element?(card_view, "td", "matched")
    assert has_element?(card_view, "td", "#{card.cardmarket_product_id}")
    assert has_element?(card_view, "td", set.name)
    refute has_element?(card_view, "a[href*='/edit']")
    refute has_element?(card_view, "button", "Delete")
    refute has_element?(card_view, "td", "variant-data-secret")
    refute has_element?(card_view, "td", "source-payload-secret")

    {:ok, card_show, _} = live(conn, "/admin/catalogue/cards/#{card.id}/show")
    assert has_element?(card_show, "p", card.tcgdex_id)
    assert has_element?(card_show, "p", "#{card.cardmarket_product_id}")
    assert has_element?(card_show, "p", set.name)
    refute has_element?(card_show, "body", "variant-data-secret")
    refute has_element?(card_show, "body", "source-payload-secret")
    refute has_element?(card_show, "a[href*='/edit']")
    refute has_element?(card_show, "button", "Delete")

    {:ok, valuation_view, _} = live(conn, "/admin/catalogue/valuations")

    assert has_element?(
             valuation_view,
             "a[href*='/admin/catalogue/valuations/#{current.id}/show']"
           )

    assert has_element?(
             valuation_view,
             "a[href*='/admin/catalogue/valuations/#{archived.id}/show']"
           )

    assert has_element?(valuation_view, "td", "0.99")
    assert has_element?(valuation_view, "td", "0.75")
    assert has_element?(valuation_view, "td", "tcgdex_cardmarket_v1")
    assert has_element?(valuation_view, "a[href*='/admin/catalogue/cards/#{card.id}/show']")
    refute has_element?(valuation_view, "a[href*='/edit']")
    refute has_element?(valuation_view, "button", "Delete")
    refute has_element?(valuation_view, "td", "source-payload-secret")
    refute has_element?(valuation_view, "td", "variant-data-secret")

    {:ok, valuation_show, _} = live(conn, "/admin/catalogue/valuations/#{archived.id}/show")
    assert has_element?(valuation_show, "p", "0.75")
    assert has_element?(valuation_show, "p", "tcgdex_cardmarket_v1")
    assert has_element?(valuation_show, "a[href*='/admin/catalogue/cards/#{card.id}/show']")
    refute has_element?(valuation_show, "body", "source-payload-secret")
    refute has_element?(valuation_show, "body", "variant-data-secret")
    refute has_element?(valuation_show, "a[href*='/edit']")
    refute has_element?(valuation_show, "button", "Delete")
  end

  defp catalogue_fixture do
    suffix = System.unique_integer([:positive])
    tcgdex_id = "set-admin-#{suffix}"

    set =
      Core.import_card_set!(%{
        tcgdex_id: tcgdex_id,
        name: "Admin Set #{suffix}",
        series_id: "series-admin-#{suffix}",
        series_name: "Admin Series #{suffix}",
        logo_url: "https://assets.tcgdex.net/logo-admin-#{suffix}.png",
        symbol_url: "https://assets.tcgdex.net/symbol-admin-#{suffix}.png",
        source_payload: %{secret: "source-payload-secret"}
      })

    card =
      Core.import_card_printing!(%{
        tcgdex_id: "card-admin-#{suffix}",
        name: "Admin Card #{suffix}",
        set_name: set.name,
        collector_number: "#{suffix}/100",
        card_set_id: set.id,
        mapping_status: "matched",
        cardmarket_product_id: suffix,
        mapping_updated_at: DateTime.utc_now(),
        mapping_review_reason: nil,
        variant_data: %{secret: "variant-data-secret"},
        source_payload: %{secret: "source-payload-secret"}
      })

    now = DateTime.utc_now()

    archived =
      Core.record_single_valuation!(
        %{
          card_printing_id: card.id,
          value_eur: Decimal.new("0.75"),
          currency: "EUR",
          policy_version: "tcgdex_cardmarket_v1",
          source: "Cardmarket",
          source_metric: "average",
          fetched_at: DateTime.add(now, -60, :second),
          cardmarket_product_id: suffix
        },
        authorize?: false
      )

    current =
      Core.record_single_valuation!(
        %{
          card_printing_id: card.id,
          value_eur: Decimal.new("0.99"),
          currency: "EUR",
          policy_version: "tcgdex_cardmarket_v1",
          source: "Cardmarket",
          source_metric: "average",
          fetched_at: now,
          cardmarket_product_id: suffix
        },
        authorize?: false
      )

    {card, set, current, archived}
  end

  defp authenticated_conn(conn) do
    email = "catalogue-admin-#{System.unique_integer([:positive])}@example.test"
    password = "correct horse battery staple"

    Accounts.register_admin!(
      %{email: email, password: password, password_confirmation: password},
      authorize?: false
    )

    conn
    |> post(~p"/admin/sign-in", %{"admin" => %{"email" => email, "password" => password}})
    |> recycle()
  end

  defp admin_fixture do
    email = "catalogue-actor-#{System.unique_integer([:positive])}@example.test"
    password = "correct horse battery staple"

    Accounts.register_admin!(
      %{email: email, password: password, password_confirmation: password},
      authorize?: false
    )
  end
end
