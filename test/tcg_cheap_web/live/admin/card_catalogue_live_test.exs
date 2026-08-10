defmodule TcgCheapWeb.Admin.CardCatalogueLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TcgCheap.Accounts
  alias TcgCheap.Catalogue.CardPrinting
  alias TcgCheap.Catalogue.CardPrintingMappingDecision
  alias TcgCheap.Catalogue.CardSet
  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.{SingleValuationSnapshot, ValuationAcquisition}

  test "catalogue roots redirect unauthenticated visitors", %{conn: conn} do
    for path <- [
          "/admin/catalogue/card-sets",
          "/admin/catalogue/cards",
          "/admin/catalogue/valuations",
          "/admin/catalogue/card-mapping-history",
          "/admin/catalogue/cards/not-a-uuid/correct"
        ] do
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, path)
    end
  end

  test "catalogue reads are administrator-only" do
    admin = admin_fixture()

    assert {:error, _} = Ash.read(CardSet, domain: Core)
    assert {:error, _} = Ash.read(CardPrinting, domain: Core)
    assert {:error, _} = Ash.read(CardPrintingMappingDecision, domain: Core)
    assert {:error, _} = Ash.read(SingleValuationSnapshot, domain: Core)

    assert {:ok, _} = Core.list_admin_card_sets(actor: admin)
    assert {:ok, _} = Core.list_admin_card_printings(actor: admin)
    assert {:ok, _} = Core.list_admin_card_printing_mapping_decisions(actor: admin)
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
    assert has_element?(card_view, "a[href='/admin/catalogue/cards/#{card.id}/correct']")
    refute has_element?(card_view, "a", "Edit")
    refute has_element?(card_view, "button", "Delete")

    {:ok, card_show, _} = live(conn, "/admin/catalogue/cards/#{card.id}/show")
    assert has_element?(card_show, "p", card.tcgdex_id)
    assert has_element?(card_show, "p", "#{card.cardmarket_product_id}")
    assert has_element?(card_show, "p", set.name)
    refute has_element?(card_show, "body", "variant-data-secret")
    refute has_element?(card_show, "body", "source-payload-secret")
    refute has_element?(card_show, "a[href*='/edit']")
    refute has_element?(card_show, "button", "Delete")

    {:ok, correction_view, _} = live(conn, "/admin/catalogue/cards/#{card.id}/correct")
    assert has_element?(correction_view, "#card-printing-correction-form")
    assert has_element?(correction_view, "#card-printing-tcgdex-id", card.tcgdex_id)
    assert has_element?(correction_view, "#card-printing-mapping-warning")
    refute has_element?(correction_view, "body", "source-payload-secret")
    refute has_element?(correction_view, "body", "variant-data-secret")

    {:ok, history_view, _} = live(conn, "/admin/catalogue/card-mapping-history")
    assert has_element?(history_view, "main")
    refute has_element?(history_view, "a[href*='/edit']")
    refute has_element?(history_view, "button", "Delete")

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

  test "administrator corrects and reopens a mapping with retained history", %{conn: conn} do
    {card, _set, current, _archived} = catalogue_fixture()
    admin = admin_fixture()
    conn = authenticated_conn(conn, admin)

    {:ok, correction_view, _html} =
      live(conn, "/admin/catalogue/cards/#{card.id}/correct")

    correction_view
    |> form("#card-printing-correction-form",
      card_printing_correction: %{cardmarket_product_id: "0", reason: " "}
    )
    |> render_submit()

    assert has_element?(
             correction_view,
             "#card-printing-correction-form",
             "Enter a positive Cardmarket product ID."
           )

    unchanged = Core.get_card_printing_by_tcgdex_id!(card.tcgdex_id)
    assert unchanged.cardmarket_product_id == card.cardmarket_product_id
    assert Ash.get!(SingleValuationSnapshot, current.id, domain: Core, authorize?: false).current?

    corrected_product_id = card.cardmarket_product_id + 10
    Phoenix.PubSub.subscribe(TcgCheap.PubSub, ValuationAcquisition.topic(card))

    correction_result =
      correction_view
      |> form("#card-printing-correction-form",
        card_printing_correction: %{
          cardmarket_product_id: Integer.to_string(corrected_product_id),
          reason: "Verified against the Cardmarket product page"
        }
      )
      |> render_submit()

    assert_receive {:card_mapping_changed, %{card_printing_id: card_id}}
    assert card_id == card.id

    {:ok, corrected_show, _html} =
      follow_redirect(
        correction_result,
        conn,
        "/admin/catalogue/cards/#{card.id}/show"
      )

    assert has_element?(corrected_show, "p", "administrator")
    corrected = Core.get_card_printing_by_tcgdex_id!(card.tcgdex_id)

    assert {corrected.mapping_status, corrected.mapping_authority,
            corrected.cardmarket_product_id} ==
             {"matched", "administrator", corrected_product_id}

    refute Ash.get!(SingleValuationSnapshot, current.id, domain: Core, authorize?: false).current?

    assert {:ok, [correction]} =
             Core.list_card_printing_mapping_decision_history(card.id, actor: admin)

    assert %{
             event: "corrected",
             reason: "Verified against the Cardmarket product page",
             actor_id: actor_id
           } = correction

    assert actor_id == admin.id

    {:ok, history_view, _html} = live(conn, "/admin/catalogue/card-mapping-history")
    assert has_element?(history_view, "td", "Verified against the Cardmarket product page")
    assert has_element?(history_view, "td", to_string(admin.email))

    {:ok, reopen_view, _html} = live(conn, "/admin/catalogue/cards/#{card.id}/correct")

    reopen_result =
      reopen_view
      |> form("#card-printing-reopen-form",
        card_printing_reopen: %{reason: "Provider identity needs another review"}
      )
      |> render_submit()

    assert_receive {:card_mapping_changed, %{card_printing_id: reopened_card_id}}
    assert reopened_card_id == card.id

    {:ok, reopened_show, _html} =
      follow_redirect(reopen_result, conn, "/admin/catalogue/cards/#{card.id}/show")

    assert has_element?(reopened_show, "p", "review")
    reopened = Core.get_card_printing_by_tcgdex_id!(card.tcgdex_id)

    assert {reopened.mapping_status, reopened.mapping_authority, reopened.cardmarket_product_id,
            reopened.mapping_review_reason} ==
             {"review", "administrator", nil, "Provider identity needs another review"}

    assert {:ok, decisions} =
             Core.list_card_printing_mapping_decision_history(card.id, actor: admin)

    assert Enum.map(decisions, & &1.event) == ["corrected", "reopened"]
  end

  test "stale correction preserves submitted evidence and adds no duplicate decision", %{
    conn: conn
  } do
    {card, _set, _current, _archived} = catalogue_fixture()
    admin = admin_fixture()
    conn = authenticated_conn(conn, admin)

    {:ok, stale_view, _html} = live(conn, "/admin/catalogue/cards/#{card.id}/correct")

    Core.correct_cardmarket_mapping!(
      card,
      %{
        cardmarket_product_id: card.cardmarket_product_id + 1,
        reason: "First correction",
        expected_updated_at: card.updated_at
      },
      actor: admin
    )

    stale_view
    |> form("#card-printing-correction-form",
      card_printing_correction: %{
        cardmarket_product_id: Integer.to_string(card.cardmarket_product_id + 2),
        reason: "Stale correction evidence"
      }
    )
    |> render_submit()

    assert has_element?(
             stale_view,
             "#card-printing-correction-form",
             "The mapping changed or could not be corrected."
           )

    assert has_element?(
             stale_view,
             "#card-printing-correction-cardmarket-id[value='#{card.cardmarket_product_id + 2}']"
           )

    assert has_element?(
             stale_view,
             "#card-printing-correction-reason",
             "Stale correction evidence"
           )

    assert {:ok, [%{event: "corrected", reason: "First correction"}]} =
             Core.list_card_printing_mapping_decision_history(card.id, actor: admin)
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
      TcgCheap.TestSupport.import_card_printing!(%{
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

  defp authenticated_conn(conn), do: authenticated_conn(conn, admin_fixture())

  defp authenticated_conn(conn, admin) do
    conn
    |> post(~p"/admin/sign-in", %{
      "admin" => %{
        "email" => to_string(admin.email),
        "password" => "correct horse battery staple"
      }
    })
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
