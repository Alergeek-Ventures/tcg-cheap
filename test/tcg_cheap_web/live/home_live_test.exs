defmodule TcgCheapWeb.HomeLiveTest do
  import Phoenix.LiveViewTest
  use TcgCheapWeb.ConnCase

  alias TcgCheap.Core
  alias TcgCheapWeb.HomeLive

  test "mounts the singles decision surface by default", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#decision-header")
    assert has_element?(view, "#decision-wordmark")
    assert has_element?(view, "#decision-wordmark .fluent-icon")
    assert has_element?(view, "#mode-singles[aria-pressed=true]")
    assert has_element?(view, "#mode-sealed[aria-pressed=false]")
    assert has_element?(view, "#card-search-form")
    refute has_element?(view, "#card-search-form[phx-change]")
    assert has_element?(view, "#card-search-query[type=search]")
    assert has_element?(view, "#market-singles-panel:not([hidden])")
    assert has_element?(view, "#market-sealed-panel[hidden]")
    assert has_element?(view, "#market-singles-recent:not([hidden])")
    assert has_element?(view, "#market-sealed-recent[hidden]")

    assert has_element?(
             view,
             "#card-search-query[phx-hook='CardAutocomplete']"
           )

    assert has_element?(
             view,
             "#card-search-query[role=combobox][aria-autocomplete=list][aria-controls=card-search-results][aria-expanded=false]"
           )

    assert has_element?(view, "#card-search-query[maxlength=\"100\"]")
    refute has_element?(view, "#card-search-query[aria-describedby]")
    assert has_element?(view, "#card-search-results[phx-update=stream]")
    assert has_element?(view, "#decision-title", "Compare Pokémon prices")
    assert has_element?(view, "#card-search-query[placeholder='Name, set, or collector number']")
    assert has_element?(view, "#search-title:not(.sr-only)", "Find an exact printing")
    assert has_element?(view, "#market-movers-title", "Price movement")
    assert has_element?(view, "#price-details summary", "Method")
    assert has_element?(view, "#price-details", "most recent 30 UTC dates")
    refute has_element?(view, "#market-movers-intro")
  end

  test "switches to local sealed search and restores singles", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(element(view, "#mode-sealed"))

    assert has_element?(view, "#mode-sealed[aria-pressed=true]")
    assert has_element?(view, "#sealed-search-form")
    assert has_element?(view, "#sealed-search-title:not(.sr-only)", "Find a sealed product")
    assert has_element?(view, "#sealed-data-note.search-context", "shown when available")
    assert has_element?(view, "#sealed-search-query[placeholder='Product name, set, or series']")

    assert has_element?(
             view,
             "#sealed-search-query[role=combobox][aria-controls=sealed-search-results]"
           )

    assert has_element?(view, "#sealed-search-results[role=listbox][phx-update=stream]")
    refute has_element?(view, "#card-search-form")

    render_click(element(view, "#mode-singles"))

    assert has_element?(view, "#mode-singles[aria-pressed=true]")
    assert has_element?(view, "#card-search-form")
    assert has_element?(view, "#card-search-results[phx-update=stream]")
    assert has_element?(view, "#card-search-query[type=search]")
    refute has_element?(view, "#card-search-idle")
    refute has_element?(view, "#sealed-search-form")
  end

  test "CSP allows only the TCGdex image host", %{conn: conn} do
    response = get(conn, "/")
    [policy] = get_resp_header(response, "content-security-policy")

    assert Regex.match?(~r/img-src 'self' data: https:\/\/assets\.tcgdex\.net(?:;|$)/, policy)
    refute policy =~ "img-src 'self' data: https://assets.tcgdex.net https://"
  end

  test "searches approved sealed products by canonical name and approved alias", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    product = create_sealed_product("Public Sealed #{suffix}")

    alias_row =
      Core.create_sealed_product_alias!(%{
        sealed_product_id: product.id,
        kind: "name",
        original_value: "Friendly Sealed #{suffix}"
      })

    Core.approve_sealed_product_alias!(alias_row, %{expected_updated_at: alias_row.updated_at},
      authorize?: false
    )

    {:ok, view, _html} = live(conn, ~p"/")
    render_click(element(view, "#mode-sealed"))

    render_hook(view, "search", %{"search" => %{"query" => product.name}})
    assert has_element?(view, "#sealed-option-#{product.id}")

    render_hook(view, "search", %{"search" => %{"query" => "friendly sealed #{suffix}"}})

    assert has_element?(view, "#sealed-option-#{product.id}[role=option][aria-selected=true]")
    assert has_element?(view, "#sealed-search-name-#{product.id}", product.name)
    assert has_element?(view, "#sealed-search-summary", "1 sealed product")
    refute has_element?(view, "#sealed-search-result-#{product.id} img")
  end

  test "sealed selection is bounded to current options", %{conn: conn} do
    product = create_sealed_product("Clickable Sealed #{System.unique_integer([:positive])}")
    {:ok, view, _html} = live(conn, ~p"/")
    render_click(element(view, "#mode-sealed"))
    render_hook(view, "search", %{"search" => %{"query" => "clickable sealed"}})

    render_hook(view, "select_option", %{"slug" => product.slug})
    assert_redirect(view, "/sealed/#{product.slug}")

    {:ok, view, _html} = live(conn, ~p"/")
    render_click(element(view, "#mode-sealed"))
    render_hook(view, "select_option", %{"slug" => "not-a-current-slug"})
    assert has_element?(view, "#sealed-search-form")
  end

  test "sealed search hides drafts and reports short and empty states", %{conn: conn} do
    suffix = System.unique_integer([:positive])

    Core.create_sealed_product_draft!(%{
      slug: "hidden-home-#{suffix}",
      name: "Hidden Home Sealed #{suffix}",
      product_type: "tin"
    })

    {:ok, view, _html} = live(conn, ~p"/")
    render_click(element(view, "#mode-sealed"))

    render_hook(view, "search", %{"search" => %{"query" => "x"}})
    assert has_element?(view, "#sealed-search-short")
    assert has_element?(view, "#sealed-search-summary", "Type at least 2 characters")

    render_hook(view, "search", %{
      "search" => %{"query" => "Hidden Home Sealed #{suffix}"}
    })

    assert has_element?(view, "#sealed-search-empty", "No sealed products found")
    refute has_element?(view, "[id^='sealed-search-result-']")
  end

  test "sealed keyboard navigation wraps and Enter selects the active product", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    query = "Sealed Keyboard #{suffix}"
    first = create_sealed_product("#{query} Alpha")
    second = create_sealed_product("#{query} Bravo")

    {:ok, view, _html} = live(conn, ~p"/")
    render_click(element(view, "#mode-sealed"))
    render_hook(view, "search", %{"search" => %{"query" => query}})

    assert has_element?(view, "#sealed-option-#{first.id}[aria-selected=true]")
    assert has_element?(view, "#sealed-option-#{second.id}[aria-selected=false]")

    render_hook(view, "autocomplete_key", %{"key" => "ArrowDown"})
    assert has_element?(view, "#sealed-option-#{second.id}.active-option[aria-selected=true]")

    render_hook(view, "autocomplete_key", %{"key" => "Enter", "query" => query})
    assert_redirect(view, "/sealed/#{second.slug}")
  end

  test "Enter from a newer input cannot use stale options", %{conn: conn} do
    card = create_same_name_printings("Rapid input") |> elem(1)
    query = "Rapid input"
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "search", %{"search" => %{"query" => query}})
    assert has_element?(view, "#card-option-#{card.id}")

    render_hook(view, "autocomplete_key", %{"key" => "Enter", "query" => "New input"})

    refute has_element?(view, "#card-option-#{card.id}")
    assert has_element?(view, "#card-search-query[aria-expanded=false]")
  end

  test "sealed Escape clears visible options and malformed cross-mode selections are ignored", %{
    conn: conn
  } do
    product = create_sealed_product("Escape Sealed #{System.unique_integer([:positive])}")
    {:ok, view, _html} = live(conn, ~p"/")
    render_click(element(view, "#mode-sealed"))
    render_hook(view, "search", %{"search" => %{"query" => product.name}})

    assert has_element?(view, "#sealed-option-#{product.id}")
    render_hook(view, "autocomplete_key", %{"key" => "Escape"})
    refute has_element?(view, "#sealed-option-#{product.id}")
    assert has_element?(view, "#sealed-search-query[aria-expanded=false]")

    render_hook(view, "select_option", %{"tcgdex-id" => "cross-mode-tamper"})
    render_hook(view, "select_option", %{"slug" => "not-a-current-slug"})
    render_hook(view, "search", %{})
    render_hook(view, "switch_mode", %{"mode" => "unsupported"})
    assert has_element?(view, "#sealed-search-form")
  end

  test "sealed search error component gives a deterministic recovery state" do
    html =
      render_component(&HomeLive.sealed_search_state/1,
        status: :error,
        count: 0,
        query: "charizard",
        fallback_count: 0
      )

    document = LazyHTML.from_fragment(html)

    assert document
           |> LazyHTML.filter("#sealed-search-error.state-error")
           |> LazyHTML.to_tree() != []

    assert document
           |> LazyHTML.filter("#sealed-search-summary")
           |> LazyHTML.text() =~ "Search unavailable for charizard"
  end

  test "requires two effective characters", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "search", %{"search" => %{"query" => "é"}})

    assert has_element?(view, "#card-search-short")
    assert has_element?(view, "#card-search-summary", "Type at least 2 characters")
    refute has_element?(view, ".evidence-slip")
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
      TcgCheap.TestSupport.import_card_printing(%{
        tcgdex_id: "card-#{suffix}-a",
        name: name,
        set_name: set.name,
        collector_number: "01",
        card_set_id: set.id,
        rarity: "Common",
        standard_legal: true
      })

    {:ok, second} =
      TcgCheap.TestSupport.import_card_printing(%{
        tcgdex_id: "card-#{suffix}-b",
        name: name,
        set_name: set.name,
        collector_number: "02",
        card_set_id: set.id,
        expanded_legal: true
      })

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "search", %{"search" => %{"query" => name}})

    assert has_element?(view, "#card-search-result-#{first.id}")
    assert has_element?(view, "#card-search-result-#{second.id}")
    assert has_element?(view, "#card-search-result-#{first.id} .evidence-identity")
    assert has_element?(view, "#card-search-summary", "2 cards for #{String.downcase(name)}")

    assert has_element?(
             view,
             "#card-search-result-#{first.id} .evidence-set",
             "Archive Set #{suffix} · #01"
           )

    assert has_element?(
             view,
             "#card-search-result-#{second.id} .evidence-set",
             "Archive Set #{suffix} · #02"
           )

    assert has_element?(view, "#card-rarity-#{first.id}", "Common")
    refute has_element?(view, "#card-standard-#{first.id}")
    refute has_element?(view, "#card-expanded-#{second.id}")
    assert has_element?(view, "#card-estimate-#{first.id}", "Price unavailable")
    refute has_element?(view, "#card-freshness-#{first.id}")

    assert has_element?(
             view,
             "#card-option-#{first.id}[aria-labelledby='card-search-name-#{first.id} card-search-set-#{first.id} card-rarity-#{first.id} card-estimate-#{first.id}']"
           )

    refute has_element?(view, "#tcgdex-#{first.id}")
    refute has_element?(view, "#trade")

    assert has_element?(
             view,
             "#card-select-action-#{first.id}.detail-action"
           )

    assert has_element?(view, "#card-select-action-#{first.id}", "View price")
    refute has_element?(view, "#card-select-action-#{first.id} a")
    refute has_element?(view, "#card-select-action-#{first.id} button")

    assert has_element?(
             view,
             "#card-option-#{first.id}[phx-click=select_option][phx-value-tcgdex-id='#{first.tcgdex_id}'][tabindex='-1']"
           )

    refute has_element?(view, "#card-image-link-#{first.id}")

    assert has_element?(
             view,
             "#card-search-result-#{first.id}[aria-labelledby='card-search-name-#{first.id} card-search-set-#{first.id}']"
           )

    assert has_element?(view, "#card-search-set-#{first.id}", "Archive Set #{suffix} · #01")
  end

  test "renders local active-policy estimates with 24-hour freshness", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    search_term = "valuation-bench-#{suffix}"
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, set} =
      Core.import_card_set(%{
        tcgdex_id: Ecto.UUID.generate(),
        name: "Valuation Set #{suffix}"
      })

    {:ok, fresh} =
      TcgCheap.TestSupport.import_card_printing(%{
        tcgdex_id: Ecto.UUID.generate(),
        name: "Fresh #{search_term}",
        set_name: set.name,
        collector_number: "01",
        card_set_id: set.id,
        mapping_status: "matched",
        cardmarket_product_id: System.unique_integer([:positive])
      })

    {:ok, stale} =
      TcgCheap.TestSupport.import_card_printing(%{
        tcgdex_id: Ecto.UUID.generate(),
        name: "Stale #{search_term}",
        set_name: set.name,
        collector_number: "02",
        card_set_id: set.id,
        mapping_status: "matched",
        cardmarket_product_id: System.unique_integer([:positive])
      })

    valuation_attrs = fn card, value, fetched_at ->
      %{
        card_printing_id: card.id,
        value_eur: Decimal.new(value),
        currency: "EUR",
        policy_version: "tcgdex_cardmarket_v1",
        source: "tcgdex",
        source_metric: "cardmarket_average_sell_price",
        fetched_at: fetched_at,
        cardmarket_product_id: card.cardmarket_product_id
      }
    end

    Core.record_single_valuation!(valuation_attrs.(fresh, "12.30", now))
    Core.record_single_valuation!(valuation_attrs.(stale, "8.40", DateTime.add(now, -8, :day)))

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "search", %{"search" => %{"query" => search_term}})

    assert has_element?(view, "#card-estimate-#{fresh.id}", "€12.30")
    assert has_element?(view, "#card-freshness-#{fresh.id}", "Updated today")
    assert has_element?(view, "#card-estimate-#{stale.id}", "€8.40")
    assert has_element?(view, "#card-freshness-#{stale.id}", "May be outdated")

    assert has_element?(
             view,
             "#card-option-#{fresh.id}[aria-labelledby='card-search-name-#{fresh.id} card-search-set-#{fresh.id} card-estimate-#{fresh.id} card-freshness-#{fresh.id}']"
           )

    assert has_element?(
             view,
             "#card-option-#{stale.id}[aria-labelledby='card-search-name-#{stale.id} card-search-set-#{stale.id} card-estimate-#{stale.id} card-freshness-#{stale.id}']"
           )

    assert has_element?(
             view,
             ".estimate-note",
             "Estimate only · Condition and shipping may vary."
           )

    assert has_element?(view, "#price-details")
    assert has_element?(view, "#price-details", "at least two dates")
    refute has_element?(view, "#market-movers-intro")
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
      TcgCheap.TestSupport.import_card_printing(%{
        tcgdex_id: "image-card-#{suffix}",
        name: name,
        set_name: set.name,
        collector_number: "01",
        card_set_id: set.id,
        image_url: "https://assets.tcgdex.net/en/swsh/swshp/1"
      })

    {:ok, missing} =
      TcgCheap.TestSupport.import_card_printing(%{
        tcgdex_id: "missing-image-card-#{suffix}",
        name: name,
        set_name: set.name,
        collector_number: "02",
        card_set_id: set.id
      })

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "search", %{"search" => %{"query" => name}})

    assert has_element?(
             view,
             "#card-search-image-#{imported.id}[src='https://assets.tcgdex.net/en/swsh/swshp/1/low.webp'][width='245'][height='337'][loading='lazy'][decoding='async'][referrerpolicy='no-referrer']"
           )

    assert has_element?(
             view,
             "#card-search-image-missing-#{missing.id}[aria-label='No image is available for this card.']"
           )
  end

  test "uses singular card summary and clears previous results", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    name = "Solo Archive Card #{suffix}"

    {:ok, _set} =
      Core.import_card_set(%{tcgdex_id: "solo-set-#{suffix}", name: "Solo Set #{suffix}"})

    {:ok, _printing} =
      TcgCheap.TestSupport.import_card_printing(%{
        tcgdex_id: "solo-card-#{suffix}",
        name: name,
        set_name: "Solo Set #{suffix}",
        collector_number: "001"
      })

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "search", %{"search" => %{"query" => name}})
    assert has_element?(view, "#card-search-summary", "1 card for #{String.downcase(name)}")
    assert has_element?(view, ".evidence-slip")

    padded_query = String.duplicate(" ", 101) <> name
    render_hook(view, "search", %{"search" => %{"query" => padded_query}})
    assert has_element?(view, "#card-search-summary", "1 card for #{String.downcase(name)}")
    refute has_element?(view, "#card-search-invalid")
    refute has_element?(view, "#card-search-error")

    render_hook(view, "search", %{"search" => %{"query" => ""}})
    refute has_element?(view, "#card-search-idle")
    refute has_element?(view, ".evidence-slip")
  end

  test "rejects a normalized query over 100 characters", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    query = String.duplicate("é", 101)

    render_hook(view, "search", %{"search" => %{"query" => query}})

    assert has_element?(view, "#card-search-invalid")
    assert has_element?(view, "#card-search-summary", "Search too long")
    refute has_element?(view, ".evidence-slip")
  end

  test "shows recovery for a local no-match", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    query = "nothing-#{System.unique_integer()}"
    render_hook(view, "search", %{"search" => %{"query" => query}})

    assert has_element?(view, "#card-search-empty")
    assert has_element?(view, "#card-search-summary", "No cards found for #{query}")
  end

  test "same-count completed searches have distinct query summaries", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    first_query = "missing-alpha-#{System.unique_integer([:positive])}"
    second_query = "missing-beta-#{System.unique_integer([:positive])}"

    render_hook(view, "search", %{"search" => %{"query" => first_query}})
    assert has_element?(view, "#card-search-summary", "No cards found for #{first_query}")

    render_hook(view, "search", %{"search" => %{"query" => second_query}})
    assert has_element?(view, "#card-search-summary", "No cards found for #{second_query}")
  end

  test "navigates autocomplete options with keyboard and wraps", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    name = "Keyboard Archive #{suffix}"

    {:ok, set} =
      Core.import_card_set(%{tcgdex_id: Ecto.UUID.generate(), name: "Keyboard Set #{suffix}"})

    {:ok, first} =
      TcgCheap.TestSupport.import_card_printing(%{
        tcgdex_id: "keyboard-#{suffix}-a",
        name: name,
        set_name: set.name,
        collector_number: "01",
        card_set_id: set.id
      })

    {:ok, second} =
      TcgCheap.TestSupport.import_card_printing(%{
        tcgdex_id: "keyboard-#{suffix}-b",
        name: name,
        set_name: set.name,
        collector_number: "02",
        card_set_id: set.id
      })

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "search", %{"search" => %{"query" => name}})
    {initial, next} = selected_order(view, first, second)

    assert has_element?(view, "#card-search-results[role=listbox]")
    assert has_element?(view, "#card-option-#{initial.id}[role=option][aria-selected=true]")
    assert has_element?(view, "#card-option-#{next.id}[role=option][aria-selected=false]")
    assert has_element?(view, "#card-search-query[aria-expanded=true]")

    render_hook(view, "autocomplete_key", %{"key" => "ArrowDown"})
    assert has_element?(view, "#card-option-#{next.id}.active-option[aria-selected=true]")
    assert has_element?(view, "#card-option-#{initial.id}[aria-selected=false]")
    refute has_element?(view, "#card-option-#{initial.id}.active-option")
    assert_one_selected(view)

    assert has_element?(
             view,
             "#card-search-query[aria-activedescendant='card-option-#{next.id}']"
           )

    render_hook(view, "autocomplete_key", %{"key" => "ArrowDown"})
    assert has_element?(view, "#card-option-#{initial.id}.active-option[aria-selected=true]")
    assert has_element?(view, "#card-option-#{next.id}[aria-selected=false]")
    refute has_element?(view, "#card-option-#{next.id}.active-option")
    assert_one_selected(view)

    assert has_element?(
             view,
             "#card-search-query[aria-activedescendant='card-option-#{initial.id}']"
           )

    render_hook(view, "autocomplete_key", %{"key" => "ArrowUp"})
    assert has_element?(view, "#card-option-#{next.id}.active-option[aria-selected=true]")
    assert has_element?(view, "#card-option-#{initial.id}[aria-selected=false]")
    refute has_element?(view, "#card-option-#{initial.id}.active-option")
    assert_one_selected(view)

    render_hook(view, "autocomplete_key", %{"key" => "Escape"})
    refute has_element?(view, "#card-option-#{first.id}")
    refute has_element?(view, "#card-option-#{second.id}")
    assert has_element?(view, "#card-search-query[aria-expanded=false]")
  end

  test "Enter selects the initially active exact autocomplete printing", %{conn: conn} do
    {name, first, second} = create_same_name_printings("Enter first")
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "search", %{"search" => %{"query" => name}})
    {initial, _next} = selected_order(view, first, second)
    render_hook(view, "autocomplete_key", %{"key" => "Enter", "query" => name})

    assert_redirect(view, "/cards/#{initial.tcgdex_id}")
  end

  test "Enter selects the active autocomplete printing", %{conn: conn} do
    {name, first, second} = create_same_name_printings("Enter active")
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "search", %{"search" => %{"query" => name}})
    {_initial, next} = selected_order(view, first, second)

    render_hook(view, "autocomplete_key", %{"key" => "ArrowDown"})
    assert has_element?(view, "#card-option-#{next.id}[aria-selected=true]")

    render_hook(view, "autocomplete_key", %{"key" => "Enter", "query" => name})

    assert_redirect(view, "/cards/#{next.tcgdex_id}")
  end

  test "clicking an option selects the exact current printing and rejects tampering", %{
    conn: conn
  } do
    {name, first, _second} = create_same_name_printings("Click option")
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "search", %{"search" => %{"query" => name}})
    render_click(element(view, "#card-option-#{first.id}"))
    assert_redirect(view, "/cards/#{first.tcgdex_id}")

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "search", %{"search" => %{"query" => name}})
    render_hook(view, "select_option", %{"tcgdex-id" => "not-a-current-card"})
    assert has_element?(view, "#card-option-#{first.id}")
  end

  test "renders singles market movers with evidence and direct routes", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    {first, _first_start, _first_current} = create_discovery_card("first-#{suffix}", "10", "20")

    {_second, _second_start, _second_current} =
      create_discovery_card("second-#{suffix}", "20", "10")

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#market-movers")
    assert has_element?(view, "#market-movers-title", "Price movement")
    assert has_element?(view, "#market-singles-risers-list[phx-update=stream]")
    assert has_element?(view, "#market-singles-fallers-list[phx-update=stream]")

    assert has_element?(
             view,
             "#market-single-riser-#{first.id}[href='/cards/#{first.tcgdex_id}']"
           )

    assert has_element?(view, "#market-single-riser-#{first.id}", "+100.00%")
    assert has_element?(view, "#market-single-riser-#{first.id} .fluent-icon")
    refute has_element?(view, "#market-single-riser-#{first.id} .mover-price-range")
    refute has_element?(view, "#market-single-riser-#{first.id} .mover-date-range")
    refute has_element?(view, "#market-single-riser-#{first.id} .mover-freshness")
    refute has_element?(view, "#market-single-riser-#{first.id}", "€10.00 → €20.00")

    refute has_element?(view, "#market-single-riser-#{first.id}", "View price")
    assert has_element?(view, "#market-singles-recent-title", "Recently tracked")
  end

  test "renders one-observation recently tracked singles without inventing direction", %{
    conn: conn
  } do
    suffix = System.unique_integer([:positive])
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    card =
      TcgCheap.TestSupport.import_card_printing!(%{
        tcgdex_id: "idle-card-#{suffix}",
        name: "Idle Card #{suffix}",
        set_name: "Idle Set #{suffix}",
        collector_number: "151",
        last_synced_at: now,
        mapping_status: "matched",
        cardmarket_product_id: suffix
      })

    Core.record_single_valuation!(%{
      card_printing_id: card.id,
      value_eur: Decimal.new("12.30"),
      policy_version: "tcgdex_cardmarket_v1",
      source: "tcgdex_cardmarket",
      source_metric: "avg7",
      fetched_at: now,
      cardmarket_product_id: suffix
    })

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#market-singles-recent")

    refute has_element?(view, "#market-singles-recent-direction-note")

    assert has_element?(view, "#idle-recent-card-#{card.id}[href='/cards/#{card.tcgdex_id}']")
    assert has_element?(view, "#idle-recent-card-#{card.id}", "Idle Card #{suffix}")
    assert has_element?(view, "#idle-recent-card-#{card.id}", "Idle Set #{suffix} · #151")
    assert has_element?(view, "#idle-recent-card-#{card.id}", "€12.30")
    refute has_element?(view, "#idle-recent-card-#{card.id}", "Updated today")
    refute has_element?(view, "#idle-recent-card-#{card.id} .recent-value .fluent-icon")
    refute has_element?(view, "#idle-recent-card-#{card.id}", "View price")
    refute has_element?(view, "#idle-recent-card-#{card.id}", "%")
  end

  test "renders recently approved sealed products after switching mode", %{conn: conn} do
    product = create_sealed_product("Idle sealed #{System.unique_integer([:positive])}")
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(element(view, "#mode-sealed"))

    assert has_element?(view, "#market-sealed-recent")
    assert has_element?(view, "#market-singles-recent[hidden]")
    assert has_element?(view, "#market-sealed-recent:not([hidden])")

    refute has_element?(view, "#market-sealed-recent-direction-note")

    assert has_element?(view, "#market-movers-title", "Price movement")

    assert has_element?(
             view,
             "#market-sealed-recent[aria-labelledby='market-sealed-recent-title']"
           )

    assert has_element?(view, "#market-sealed-recent-title", "Recent releases")
    assert has_element?(view, "#idle-recent-sealed-#{product.id}[href='/sealed/#{product.slug}']")
    assert has_element?(view, "#idle-recent-sealed-#{product.id}", product.name)
    refute has_element?(view, "#idle-recent-sealed-#{product.id}", "View offers")
  end

  test "caps idle recently tracked singles at six rows", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    cards =
      for index <- 1..7 do
        card =
          TcgCheap.TestSupport.import_card_printing!(%{
            tcgdex_id: "idle-cap-#{suffix}-#{index}",
            name: "Idle Cap Card #{suffix} #{index}",
            set_name: "Idle Cap Set #{suffix}",
            collector_number: Integer.to_string(index),
            last_synced_at: DateTime.add(now, -index, :day),
            mapping_status: "matched",
            cardmarket_product_id: System.unique_integer([:positive])
          })

        Core.record_single_valuation!(%{
          card_printing_id: card.id,
          value_eur: Decimal.new("#{index}.00"),
          policy_version: "tcgdex_cardmarket_v1",
          source: "tcgdex_cardmarket",
          source_metric: "avg7",
          fetched_at: DateTime.add(now, -index, :day),
          cardmarket_product_id: card.cardmarket_product_id
        })

        card
      end

    {:ok, view, _html} = live(conn, ~p"/")
    assert Enum.count(cards, &has_element?(view, "#idle-recent-card-#{&1.id}")) == 6
    oldest = List.last(cards)
    refute has_element?(view, "#idle-recent-card-#{oldest.id}")
  end

  test "keeps an honest nonblank state when no recent local data exists", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#market-singles-recent")
    assert has_element?(view, "#market-movers-title", "Price movement")
    assert has_element?(view, "#market-singles-recent-title", "Recently tracked")
    assert has_element?(view, "#market-singles-recent-empty", "Search by name")
    refute has_element?(view, "#market-singles-risers")
    refute has_element?(view, "#market-singles-fallers")

    refute has_element?(view, "#market-singles-recent-direction-note")
  end

  test "switches to compact sealed market mover hooks", %{conn: conn} do
    suffix = System.unique_integer([:positive])

    {riser, _riser_start, _riser_current} =
      create_sealed_mover("Sealed Riser #{suffix}", ["100.00", "120.00", "150.00"])

    {faller, _faller_start, _faller_current} =
      create_sealed_mover("Sealed Faller #{suffix}", ["200.00", "180.00", "100.00"])

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#market-singles-panel:not([hidden])")
    assert has_element?(view, "#market-sealed-panel[hidden]")

    render_click(element(view, "#mode-sealed"))

    assert has_element?(view, "#market-singles-panel[hidden]")
    assert has_element?(view, "#market-sealed-panel:not([hidden])")
    assert has_element?(view, "#market-sealed-riser-#{riser.id}[href='/sealed/#{riser.slug}']")
    assert has_element?(view, "#market-sealed-faller-#{faller.id}[href='/sealed/#{faller.slug}']")
    assert has_element?(view, "#market-sealed-riser-#{riser.id}", "+50.00%")
    assert has_element?(view, "#market-sealed-faller-#{faller.id}", "-50.00%")
    refute has_element?(view, "#market-sealed-riser-#{riser.id} .mover-price-range")
    refute has_element?(view, "#market-sealed-riser-#{riser.id} .mover-date-range")
    refute has_element?(view, "#market-sealed-riser-#{riser.id} .mover-freshness")
    refute has_element?(view, "#market-sealed-riser-#{riser.id}", "100.00 PLN → 150.00 PLN")
    refute has_element?(view, "#market-sealed-riser-#{riser.id}", "Checked today")
    refute has_element?(view, "#market-sealed-riser-#{riser.id}", "View offers")
    assert has_element?(view, "#market-sealed-recent-title", "Recent releases")
  end

  test "keeps discovery streams mounted while hidden during search", %{conn: conn} do
    {product, _start_date, _current_date} =
      create_sealed_mover("Stream discovery #{System.unique_integer([:positive])}", [
        "100",
        "110",
        "120"
      ])

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#market-sealed-risers-list[phx-update=stream]")
    assert has_element?(view, "#market-sealed-riser-#{product.id}")
    render_hook(view, "search", %{"search" => %{"query" => "missing discovery"}})
    assert has_element?(view, "#market-movers[hidden]")
    assert has_element?(view, "#market-sealed-riser-#{product.id}")

    render_hook(view, "autocomplete_key", %{"key" => "Escape"})
    assert has_element?(view, "#market-movers:not([hidden])")
    assert has_element?(view, "#market-sealed-riser-#{product.id}")
  end

  test "offers sealed products when singles have no match", %{conn: conn} do
    product = create_sealed_product("Fallback sealed #{System.unique_integer([:positive])}")
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "search", %{"search" => %{"query" => "Fallback sealed"}})
    assert has_element?(view, "#sealed-fallback-list a[href='/sealed/#{product.slug}']")
    assert has_element?(view, "#card-search-summary", "1 sealed product suggestion")
    render_click(element(view, "#switch-to-sealed-from-fallback"))
    assert has_element?(view, "#mode-sealed[aria-pressed=true]")
    assert has_element?(view, "#sealed-search-query[value='fallback sealed']")
    assert has_element?(view, "#sealed-option-#{product.id}")
    refute has_element?(view, "#card-search-results a")
    refute has_element?(view, "#card-search-results #sealed-fallback-list")
  end

  test "offers singles when sealed products have no match", %{conn: conn} do
    suffix = System.unique_integer([:positive])

    {card, _start_date, _current_date} =
      create_discovery_card("fallback-card-#{suffix}", "10", "11")

    {:ok, view, _html} = live(conn, ~p"/")
    render_click(element(view, "#mode-sealed"))

    render_hook(view, "search", %{"search" => %{"query" => "Discovery fallback card #{suffix}"}})
    assert has_element?(view, "#card-fallback-list a[href='/cards/#{card.tcgdex_id}']")
    assert has_element?(view, "#sealed-search-summary", "1 single-card suggestion")
    render_click(element(view, "#switch-to-singles-from-fallback"))
    assert has_element?(view, "#mode-singles[aria-pressed=true]")
    assert has_element?(view, "#card-search-query[value='discovery fallback card #{suffix}']")
    assert has_element?(view, "#card-option-#{card.id}")
    render_hook(view, "switch_mode_with_query", %{"mode" => "tampered"})
    assert has_element?(view, "#mode-singles[aria-pressed=true]")
    refute has_element?(view, "#sealed-search-results #card-fallback-list")
  end

  test "does not show cross-category fallback when primary results exist", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    {card, _start_date, _current_date} = create_discovery_card("primary-#{suffix}", "10", "11")
    product = create_sealed_product("Primary sealed #{suffix}")
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "search", %{"search" => %{"query" => "Discovery primary #{suffix}"}})
    refute has_element?(view, "#sealed-fallback")
    assert has_element?(view, "#card-option-#{card.id}")

    render_click(element(view, "#mode-sealed"))
    render_hook(view, "search", %{"search" => %{"query" => product.name}})
    refute has_element?(view, "#card-fallback")
    assert has_element?(view, "#sealed-option-#{product.id}")
  end

  test "clears fallback on short input, idle input, and mode changes", %{conn: conn} do
    _product = create_sealed_product("Clear fallback #{System.unique_integer([:positive])}")
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "search", %{"search" => %{"query" => "Clear fallback"}})
    assert has_element?(view, "#sealed-fallback")
    render_hook(view, "search", %{"search" => %{"query" => "x"}})
    refute has_element?(view, "#sealed-fallback")
    render_hook(view, "search", %{"search" => %{"query" => "Clear fallback"}})
    assert has_element?(view, "#sealed-fallback")
    render_hook(view, "search", %{"search" => %{"query" => ""}})
    refute has_element?(view, "#sealed-fallback")
    render_hook(view, "search", %{"search" => %{"query" => "Clear fallback"}})
    assert has_element?(view, "#sealed-fallback")
    render_click(element(view, "#mode-sealed"))
    refute has_element?(view, "#sealed-fallback")
  end

  defp assert_one_selected(view) do
    document = LazyHTML.from_fragment(render(view))
    selected = LazyHTML.query(document, "#card-search-results [aria-selected=true]")
    assert length(LazyHTML.to_tree(selected)) == 1
  end

  defp selected_order(view, first, second) do
    if has_element?(view, "#card-option-#{first.id}[aria-selected=true]") do
      {first, second}
    else
      assert has_element?(view, "#card-option-#{second.id}[aria-selected=true]")
      {second, first}
    end
  end

  defp create_same_name_printings(label) do
    suffix = Ecto.UUID.generate()
    name = "#{label} #{suffix}"

    {:ok, set} =
      Core.import_card_set(%{tcgdex_id: Ecto.UUID.generate(), name: "Set #{suffix}"})

    {:ok, first} =
      TcgCheap.TestSupport.import_card_printing(%{
        tcgdex_id: "enter-#{suffix}-a",
        name: name,
        set_name: set.name,
        collector_number: "01",
        card_set_id: set.id
      })

    {:ok, second} =
      TcgCheap.TestSupport.import_card_printing(%{
        tcgdex_id: "enter-#{suffix}-b",
        name: name,
        set_name: set.name,
        collector_number: "02",
        card_set_id: set.id
      })

    {name, first, second}
  end

  defp create_sealed_product(name) do
    draft =
      Core.create_sealed_product_draft!(%{
        slug: "home-#{System.unique_integer([:positive])}",
        name: name,
        product_type: "booster_box",
        officially_distributed: true,
        release_date: Date.utc_today()
      })

    Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
      authorize?: false
    )
  end

  defp create_discovery_card(label, start_value, current_value) do
    card =
      TcgCheap.TestSupport.import_card_printing!(%{
        tcgdex_id: "home-discovery-#{label}-#{Ecto.UUID.generate()}",
        name: "Discovery #{String.replace(label, "-", " ")}",
        set_name: "Discovery Set",
        collector_number: "001",
        mapping_status: "matched",
        cardmarket_product_id: System.unique_integer([:positive])
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    for {days_ago, value} <- [{8, start_value}, {0, current_value}] do
      Core.record_single_valuation!(%{
        card_printing_id: card.id,
        value_eur: Decimal.new(value),
        policy_version: "tcgdex_cardmarket_v1",
        source: "tcgdex_cardmarket",
        source_metric: "avg7",
        fetched_at: DateTime.add(now, -days_ago * 86_400, :second),
        cardmarket_product_id: card.cardmarket_product_id
      })
    end

    {card, Date.add(DateTime.to_date(now), -8), DateTime.to_date(now)}
  end

  defp create_sealed_mover(name, values) do
    product = create_sealed_product(name)
    today = Date.utc_today()

    for {days_ago, value} <- Enum.zip([14, 7, 0], values) do
      date = Date.add(today, -days_ago)

      calculated_at =
        if days_ago == 0,
          do: DateTime.utc_now() |> DateTime.truncate(:microsecond),
          else: DateTime.new!(date, ~T[12:00:00], "Etc/UTC")

      Core.record_sealed_daily_aggregate!(%{
        sealed_product_id: product.id,
        aggregate_date: date,
        calculation_version: "sealed_market_daily_v1",
        currency: "PLN",
        status: "ready",
        benchmark_pln: Decimal.new(value),
        typical_low_pln: Decimal.new(value),
        typical_high_pln: Decimal.new(value),
        fresh_regular_retailer_count: 5,
        fresh_lgs_count: 1,
        recent_sold_out_0_14_day_count: 0,
        sold_out_15_30_day_count: 0,
        stale_or_future_current_offer_count: 0,
        unique_source_retailer_count: 6,
        latest_nonfuture_checked_at: calculated_at,
        calculated_at: calculated_at,
        source_mapping_confident: true
      })
    end

    {product, Date.add(today, -14), today}
  end
end
