defmodule TcgCheapWeb.HomeLiveTest do
  import Phoenix.LiveViewTest
  use TcgCheapWeb.ConnCase

  alias TcgCheap.Core

  test "mounts the singles decision surface by default", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#decision-header")
    assert has_element?(view, "#decision-wordmark")
    assert has_element?(view, "#mode-singles[aria-pressed=true]")
    assert has_element?(view, "#mode-sealed[aria-pressed=false]")
    assert has_element?(view, "#card-search-form")
    refute has_element?(view, "#card-search-form[phx-change]")
    assert has_element?(view, "#card-search-query[type=search]")

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
    assert has_element?(view, "#card-search-query[placeholder='Search for a card']")
    refute has_element?(view, "#price-details")
  end

  test "switches to an honest unavailable sealed state and restores singles", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(element(view, "#mode-sealed"))

    assert has_element?(view, "#mode-sealed[aria-pressed=true]")
    assert has_element?(view, "#sealed-unavailable")
    refute has_element?(view, "#card-search-form")
    refute has_element?(view, "#card-search-results")
    refute has_element?(view, ".evidence-slip")

    render_click(element(view, "#mode-singles"))

    assert has_element?(view, "#mode-singles[aria-pressed=true]")
    assert has_element?(view, "#card-search-form")
    assert has_element?(view, "#card-search-results[phx-update=stream]")
    assert has_element?(view, "#card-search-query[type=search]")
    refute has_element?(view, "#card-search-idle")
    refute has_element?(view, "#sealed-unavailable")
  end

  test "CSP allows only the TCGdex image host", %{conn: conn} do
    response = get(conn, "/")
    [policy] = get_resp_header(response, "content-security-policy")

    assert Regex.match?(~r/img-src 'self' data: https:\/\/assets\.tcgdex\.net(?:;|$)/, policy)
    refute policy =~ "img-src 'self' data: https://assets.tcgdex.net https://"
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
    render_hook(view, "search", %{"search" => %{"query" => name}})

    assert has_element?(view, "#card-search-result-#{first.id}")
    assert has_element?(view, "#card-search-result-#{second.id}")
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

  test "renders local active-policy estimates with seven-day freshness", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    search_term = "valuation-bench-#{suffix}"
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, set} =
      Core.import_card_set(%{
        tcgdex_id: Ecto.UUID.generate(),
        name: "Valuation Set #{suffix}"
      })

    {:ok, fresh} =
      Core.import_card_printing(%{
        tcgdex_id: Ecto.UUID.generate(),
        name: "Fresh #{search_term}",
        set_name: set.name,
        collector_number: "01",
        card_set_id: set.id
      })

    {:ok, stale} =
      Core.import_card_printing(%{
        tcgdex_id: Ecto.UUID.generate(),
        name: "Stale #{search_term}",
        set_name: set.name,
        collector_number: "02",
        card_set_id: set.id
      })

    valuation_attrs = fn card, value, fetched_at ->
      %{
        card_printing_id: card.id,
        value_eur: Decimal.new(value),
        currency: "EUR",
        policy_version: "tcgdex_cardmarket_v1",
        source: "tcgdex",
        source_metric: "cardmarket_average_sell_price",
        fetched_at: fetched_at
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

    assert has_element?(view, "#price-details")

    assert has_element?(
             view,
             "#price-methodology",
             "Seller identity and seller/offer count are unavailable"
           )

    assert has_element?(view, "#price-disclaimer")
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
      Core.import_card_printing(%{
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
      Core.import_card_printing(%{
        tcgdex_id: "keyboard-#{suffix}-a",
        name: name,
        set_name: set.name,
        collector_number: "01",
        card_set_id: set.id
      })

    {:ok, second} =
      Core.import_card_printing(%{
        tcgdex_id: "keyboard-#{suffix}-b",
        name: name,
        set_name: set.name,
        collector_number: "02",
        card_set_id: set.id
      })

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "search", %{"search" => %{"query" => name}})

    assert has_element?(view, "#card-search-results[role=listbox]")
    assert has_element?(view, "#card-option-#{first.id}[role=option][aria-selected=true]")
    assert has_element?(view, "#card-option-#{second.id}[role=option][aria-selected=false]")
    assert has_element?(view, "#card-search-query[aria-expanded=true]")

    render_hook(view, "autocomplete_key", %{"key" => "ArrowDown"})
    assert has_element?(view, "#card-option-#{second.id}.active-option[aria-selected=true]")
    assert has_element?(view, "#card-option-#{first.id}[aria-selected=false]")
    refute has_element?(view, "#card-option-#{first.id}.active-option")
    assert_one_selected(view)

    assert has_element?(
             view,
             "#card-search-query[aria-activedescendant='card-option-#{second.id}']"
           )

    render_hook(view, "autocomplete_key", %{"key" => "ArrowDown"})
    assert has_element?(view, "#card-option-#{first.id}.active-option[aria-selected=true]")
    assert has_element?(view, "#card-option-#{second.id}[aria-selected=false]")
    refute has_element?(view, "#card-option-#{second.id}.active-option")
    assert_one_selected(view)

    assert has_element?(
             view,
             "#card-search-query[aria-activedescendant='card-option-#{first.id}']"
           )

    render_hook(view, "autocomplete_key", %{"key" => "ArrowUp"})
    assert has_element?(view, "#card-option-#{second.id}.active-option[aria-selected=true]")
    assert has_element?(view, "#card-option-#{first.id}[aria-selected=false]")
    refute has_element?(view, "#card-option-#{first.id}.active-option")
    assert_one_selected(view)

    render_hook(view, "autocomplete_key", %{"key" => "Escape"})
    refute has_element?(view, "#card-option-#{first.id}")
    refute has_element?(view, "#card-option-#{second.id}")
    assert has_element?(view, "#card-search-query[aria-expanded=false]")
  end

  test "Enter selects the first exact autocomplete printing", %{conn: conn} do
    {name, first, _second} = create_same_name_printings("Enter first")
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "search", %{"search" => %{"query" => name}})
    render_hook(view, "autocomplete_key", %{"key" => "Enter"})

    assert_redirect(view, "/cards/#{first.tcgdex_id}")
  end

  test "Enter selects the active autocomplete printing", %{conn: conn} do
    {name, _first, second} = create_same_name_printings("Enter active")
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "search", %{"search" => %{"query" => name}})
    render_hook(view, "autocomplete_key", %{"key" => "ArrowDown"})
    render_hook(view, "autocomplete_key", %{"key" => "Enter"})

    assert_redirect(view, "/cards/#{second.tcgdex_id}")
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

  defp assert_one_selected(view) do
    document = LazyHTML.from_fragment(render(view))
    selected = LazyHTML.query(document, "#card-search-results [aria-selected=true]")
    assert length(LazyHTML.to_tree(selected)) == 1
  end

  defp create_same_name_printings(label) do
    suffix = System.unique_integer([:positive])
    name = "#{label} #{suffix}"

    {:ok, set} =
      Core.import_card_set(%{tcgdex_id: Ecto.UUID.generate(), name: "Set #{suffix}"})

    {:ok, first} =
      Core.import_card_printing(%{
        tcgdex_id: "enter-#{suffix}-a",
        name: name,
        set_name: set.name,
        collector_number: "01",
        card_set_id: set.id
      })

    {:ok, second} =
      Core.import_card_printing(%{
        tcgdex_id: "enter-#{suffix}-b",
        name: name,
        set_name: set.name,
        collector_number: "02",
        card_set_id: set.id
      })

    {name, first, second}
  end
end
