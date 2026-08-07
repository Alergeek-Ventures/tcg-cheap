defmodule TcgCheapWeb.HomeLiveTest do
  import Phoenix.LiveViewTest
  use TcgCheapWeb.ConnCase

  alias TcgCheap.Core

  test "mounts the archive search surface", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#archive-header")
    assert has_element?(view, "#archive-wordmark")
    assert has_element?(view, "#card-search-form")
    assert has_element?(view, "#card-search-query[type=search]")
    assert has_element?(view, "#card-search-query[maxlength=\"100\"]")
    assert has_element?(view, "#card-search-results[phx-update=stream]")
    assert has_element?(view, "#card-search-idle")
  end

  test "CSP allows only the TCGdex image host", %{conn: conn} do
    response = get(conn, "/")
    [policy] = get_resp_header(response, "content-security-policy")

    assert Regex.match?(~r/img-src 'self' data: https:\/\/assets\.tcgdex\.net(?:;|$)/, policy)
    refute policy =~ "img-src 'self' data: https://assets.tcgdex.net https://"
  end

  test "requires two effective characters", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_change(view, "search", %{"search" => %{"query" => "é"}})

    assert has_element?(view, "#card-search-short")
    refute has_element?(view, ".printing-label")
  end

  test "shows separate exact printings with the same name", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    name = "Archive Pikachu #{suffix}"

    {:ok, set} =
      Core.import_card_set(%{
        tcgdex_id: "set-#{suffix}",
        name: "Archive Set #{suffix}",
        standard_legal: true,
        expanded_legal: true
      })

    {:ok, first} =
      Core.import_card_printing(%{
        tcgdex_id: "card-#{suffix}-a",
        name: name,
        set_name: set.name,
        collector_number: "01",
        card_set_id: set.id,
        rarity: "Common",
        standard_legal: true
      })

    {:ok, second} =
      Core.import_card_printing(%{
        tcgdex_id: "card-#{suffix}-b",
        name: name,
        set_name: set.name,
        collector_number: "02",
        card_set_id: set.id,
        expanded_legal: true
      })

    {:ok, view, _html} = live(conn, ~p"/")
    render_change(view, "search", %{"search" => %{"query" => name}})

    assert has_element?(view, "#card-search-result-#{first.id}")
    assert has_element?(view, "#card-search-result-#{second.id}")
    assert has_element?(view, "#card-search-summary", "2 exact printings")
    assert has_element?(view, "#card-search-result-#{first.id} .label-data", "01")
    assert has_element?(view, "#card-search-result-#{second.id} .label-data", "02")
    assert has_element?(view, "#card-detail-link-#{first.id}[href='/cards/#{first.tcgdex_id}']")

    assert has_element?(
             view,
             "#card-detail-link-#{first.id}[aria-label='#{name}, Archive Set #{suffix}, collector number 01']"
           )

    assert has_element?(
             view,
             "#card-search-result-#{first.id}[aria-labelledby=card-search-name-#{first.id}]"
           )
  end

  test "renders a valid low WebP thumbnail and fallback for missing images", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    name = "Image Archive Card #{suffix}"

    {:ok, set} =
      Core.import_card_set(%{
        tcgdex_id: "image-set-#{suffix}",
        name: "Image Set #{suffix}"
      })

    {:ok, imported} =
      Core.import_card_printing(%{
        tcgdex_id: "image-card-#{suffix}",
        name: name,
        set_name: set.name,
        collector_number: "01",
        card_set_id: set.id,
        image_url: "https://assets.tcgdex.net/en/swsh/swshp/1"
      })

    {:ok, missing} =
      Core.import_card_printing(%{
        tcgdex_id: "missing-image-card-#{suffix}",
        name: name,
        set_name: set.name,
        collector_number: "02",
        card_set_id: set.id
      })

    {:ok, view, _html} = live(conn, ~p"/")
    render_change(view, "search", %{"search" => %{"query" => name}})

    assert has_element?(
             view,
             "#card-search-image-#{imported.id}[src='https://assets.tcgdex.net/en/swsh/swshp/1/low.webp'][width='245'][height='337'][loading='lazy'][decoding='async'][referrerpolicy='no-referrer']"
           )

    assert has_element?(view, "#card-search-image-missing-#{missing.id}")
  end

  test "uses singular summary and clears previous results", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    name = "Solo Archive Card #{suffix}"

    {:ok, _set} =
      Core.import_card_set(%{tcgdex_id: "solo-set-#{suffix}", name: "Solo Set #{suffix}"})

    {:ok, _printing} =
      Core.import_card_printing(%{
        tcgdex_id: "solo-card-#{suffix}",
        name: name,
        set_name: "Solo Set #{suffix}",
        collector_number: "001"
      })

    {:ok, view, _html} = live(conn, ~p"/")
    render_change(view, "search", %{"search" => %{"query" => name}})
    assert has_element?(view, "#card-search-summary", "1 exact printing")
    assert has_element?(view, ".printing-label")

    padded_query = String.duplicate(" ", 101) <> name
    render_change(view, "search", %{"search" => %{"query" => padded_query}})
    assert has_element?(view, "#card-search-summary", "1 exact printing")
    refute has_element?(view, "#card-search-invalid")
    refute has_element?(view, "#card-search-error")

    render_change(view, "search", %{"search" => %{"query" => ""}})
    assert has_element?(view, "#card-search-idle")
    refute has_element?(view, ".printing-label")
  end

  test "rejects a normalized query over 100 characters", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    query = String.duplicate("é", 101)

    render_change(view, "search", %{"search" => %{"query" => query}})

    assert has_element?(view, "#card-search-invalid")
    assert has_element?(view, "#card-search-summary", "Query too long")
    refute has_element?(view, ".printing-label")
  end

  test "shows recovery for a local no-match", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_change(view, "search", %{
      "search" => %{"query" => "nothing-#{System.unique_integer()}"}
    })

    assert has_element?(view, "#card-search-empty")
    assert has_element?(view, "#card-search-summary", "0 printings")
  end
end
