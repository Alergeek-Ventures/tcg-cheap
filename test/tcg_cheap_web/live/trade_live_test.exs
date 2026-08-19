defmodule TcgCheapWeb.TradeLiveTest do
  import Bitwise
  import Oban.Testing
  import Phoenix.LiveViewTest
  use TcgCheapWeb.ConnCase, async: false

  alias TcgCheap.Core
  alias TcgCheap.Pricing.ExchangeRate
  alias TcgCheap.Pricing.ExchangeRateWorker
  alias TcgCheap.Pricing.Singles.{ValuationAcquisition, ValuationWorker}
  alias TcgCheap.Trades.Composition
  alias TcgCheapWeb.PublicAcquisitionLimiter

  @policy "tcgdex_cardmarket_v1"

  setup %{conn: conn} do
    address = unique_ip()

    conn =
      conn
      |> Map.put(:remote_ip, address)
      |> put_private(:live_view_connect_info, %{peer_data: %{address: address}})

    {:ok, conn: conn}
  end

  test "empty trade has stable structure, accessible search, and empty ledgers", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/trade")

    assert has_element?(view, "#trade-main")
    assert has_element?(view, "#trade-title", "Build a trade")
    assert has_element?(view, "#trade-search-form")
    assert has_element?(view, "#trade-search-form .search-field-wrap #trade-search-query")
    assert has_element?(view, "#trade-search-query[role=combobox][aria-expanded=false]")
    assert has_element?(view, "#trade-search-results[phx-update=stream]")
    assert has_element?(view, "#trade-left-side")
    assert has_element?(view, "#trade-right-side")
    assert has_element?(view, "#trade-announcements[aria-live=polite]")
    refute has_element?(view, "#trade-left-total")
    refute has_element?(view, "#trade-right-total")
    refute has_element?(view, "#trade-comparison")
    refute has_element?(view, "#trade-rate-evidence")
    refute has_element?(view, "#trade-share")
    refute has_element?(view, "#trade-share-status")
    assert has_element?(view, ".trade-empty", "Add cards to this side.")
  end

  test "a populated side reveals comparison, rate evidence, and share controls", %{conn: conn} do
    card = card("revealed-controls", "Revealed Controls", 1)

    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1")

    assert has_element?(view, "#trade-row-left-#{card.tcgdex_id}")
    assert has_element?(view, "#trade-left-total")
    refute has_element?(view, "#trade-right-total")
    assert has_element?(view, "#trade-comparison")
    assert has_element?(view, "#trade-rate-evidence")
    assert has_element?(view, "#trade-share[phx-hook=TradeShare]")
    assert has_element?(view, "#trade-share-status[role=status][aria-live=polite]")
  end

  test "accepts a URL-encoded punctuation pick", %{conn: conn} do
    set = Core.import_card_set!(%{tcgdex_id: "exu", name: "Destined Rivals"})

    card =
      TcgCheap.TestSupport.import_card_printing!(%{
        tcgdex_id: "exu-%3F",
        name: "Question",
        set_name: set.name,
        collector_number: "2",
        card_set_id: set.id,
        mapping_status: "matched",
        cardmarket_product_id: 999_001
      })

    {:ok, view, _html} = live(conn, "/trade?pick=exu-%253F")

    assert has_element?(view, "#trade-selected-name", card.name)
    refute has_element?(view, "#trade-url-warning", "malformed")
  end

  test "trade share feedback accepts only copied and failed statuses", %{conn: conn} do
    card = card("share-path", "Share Path", 1)
    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1&pick=#{card.tcgdex_id}")
    path = Composition.to_path(%Composition{left: [{card.tcgdex_id, 1}], right: []})

    assert has_element?(view, "#trade-share[data-trade-path='#{path}']")
    refute has_element?(view, "#trade-share[data-trade-path*='pick']")

    render_hook(view, "trade_share_result", %{"status" => "copied", "path" => path})
    assert has_element?(view, "#trade-share-status", "Link copied.")

    render_hook(view, "trade_share_result", %{"status" => "failed", "path" => path})
    assert has_element?(view, "#trade-share-status", "Copy failed.")

    render_hook(view, "trade_share_result", %{"status" => "unexpected", "path" => path})
    assert has_element?(view, "#trade-share-status", "Copy failed.")

    render_hook(view, "trade_share_result", %{"status" => "copied", "path" => "/trade"})
    assert has_element?(view, "#trade-share-status", "Copy failed.")
  end

  test "restores valued rows with decimal totals and exact difference", %{conn: conn} do
    first = card("valued-a", "Trade Card A", 1)
    second = card("valued-b", "Trade Card B", 2)
    snapshot(first, "1.25")
    snapshot(second, "2.50")

    {:ok, view, _html} =
      live(conn, "/trade?left=#{first.tcgdex_id}:2&right=#{second.tcgdex_id}:1")

    assert has_element?(view, "#trade-row-left-#{first.tcgdex_id}")
    assert has_element?(view, "#trade-row-left-#{first.tcgdex_id} .card-image-missing")
    assert has_element?(view, "#trade-left-total", "€2.50")
    assert has_element?(view, "#trade-right-total", "€2.50")
    assert has_element?(view, "#trade-comparison", "Equal")
    assert has_element?(view, "#trade-comparison", "difference €0.00")
    assert has_element?(view, "#trade-row-left-#{first.tcgdex_id}", "€1.25")
  end

  test "complete totals and difference expose exact Decimal PLN evidence", %{conn: conn} do
    first = card("rate-complete-a", "Rate Complete A", 1)
    second = card("rate-complete-b", "Rate Complete B", 2)
    snapshot(first, "2.00")
    snapshot(second, "1.00")
    exchange_rate("4.3000")

    {:ok, view, _html} =
      live(conn, "/trade?left=#{first.tcgdex_id}:1&right=#{second.tcgdex_id}:1")

    assert has_element?(view, "#trade-left-total-eur", "€2.00")
    assert has_element?(view, "#trade-left-total-pln", "PLN 8.60")
    assert has_element?(view, "#trade-right-total-pln", "PLN 4.30")
    assert has_element?(view, "#trade-comparison-eur", "difference €1.00")
    assert has_element?(view, "#trade-comparison-pln", "Difference PLN 4.30")
    assert has_element?(view, "#trade-rate-evidence", "1 EUR = 4.3000 PLN")
    assert has_element?(view, "#trade-rate-evidence", "(today)")
  end

  test "incomplete known subtotal converts while comparison remains incomplete", %{conn: conn} do
    known = card("rate-incomplete", "Rate Incomplete", 1)
    snapshot(known, "2.50")
    exchange_rate("4.3000")
    unknown = "unknown-rate-#{System.unique_integer([:positive])}"

    {:ok, view, _html} = live(conn, "/trade?left=#{known.tcgdex_id}:1,#{unknown}:1")

    assert has_element?(view, "#trade-left-total-eur", "€2.50 + ? (1 unpriced)")
    assert has_element?(view, "#trade-left-total-pln", "PLN 10.75 + ?")
    assert has_element?(view, "#trade-comparison-eur", "Comparison incomplete")
    refute has_element?(view, "#trade-comparison-pln")
  end

  test "no cached rate keeps EUR and reports PLN unavailable", %{conn: conn} do
    card = card("rate-none", "Rate None", 1)
    snapshot(card, "2.50")

    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1")

    assert has_element?(view, "#trade-left-total-eur", "€2.50")
    assert has_element?(view, "#trade-left-total-pln", "PLN unavailable")
    assert has_element?(view, "#trade-rate-evidence", "PLN unavailable")
    assert has_element?(view, "#trade-comparison-eur", "Comparison incomplete")
  end

  test "a peer at the public acquisition limit queues neither rate nor valuation work", %{
    conn: conn
  } do
    card = card("public-limit", "Public Limit", 1)
    fill_public_limit(conn.remote_ip)

    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1")

    assert has_element?(view, "#trade-row-left-#{card.tcgdex_id}", "Price unavailable")
    assert has_element?(view, "#trade-row-left-#{card.tcgdex_id}", "Update failed")
    assert has_element?(view, "#trade-rate-evidence", "Rate update failed")
    refute_enqueued(repo: TcgCheap.Repo, worker: ExchangeRateWorker)

    refute_enqueued(
      repo: TcgCheap.Repo,
      worker: ValuationWorker,
      args: %{"local_card_id" => card.id}
    )
  end

  test "exchange completion updates PLN without remounting and malformed completion is ignored",
       %{
         conn: conn
       } do
    first = card("rate-completion-a", "Rate Completion A", 1)
    second = card("rate-completion-b", "Rate Completion B", 2)
    snapshot(first, "2.00")
    snapshot(second, "1.00")

    {:ok, view, _html} =
      live(conn, "/trade?left=#{first.tcgdex_id}:1&right=#{second.tcgdex_id}:1")

    assert has_element?(view, "#trade-left-total-pln", "PLN unavailable")
    send(view.pid, {:exchange_rate_completed, %{exchange_rate: %{rate: Decimal.new("4.3")}}})
    assert has_element?(view, "#trade-left-total-pln", "PLN unavailable")

    rate = exchange_rate("4.3000")

    Phoenix.PubSub.broadcast(
      TcgCheap.PubSub,
      "exchange_rates",
      {:exchange_rate_completed, %{exchange_rate: rate}}
    )

    assert has_element?(view, "#trade-left-total-pln", "PLN 8.60")
    assert has_element?(view, "#trade-comparison-pln", "Difference PLN 4.30")

    send(view.pid, {:exchange_rate_completed, %{exchange_rate: invalid_rate(:future)}})
    send(view.pid, {:exchange_rate_completed, %{exchange_rate: invalid_rate(:noncanonical)}})
    send(view.pid, {:exchange_rate_completed, %{exchange_rate: invalid_rate(:nan)}})
    send(view.pid, {:exchange_rate_completed, %{exchange_rate: invalid_rate(:infinity)}})
    send(view.pid, {:exchange_rate_completed, %{exchange_rate: invalid_rate(:blank_publication)}})
    send(view.pid, {:exchange_rate_completed, %{exchange_rate: invalid_rate(:future_fetched)}})
    send(view.pid, {:exchange_rate_completed, %{exchange_rate: invalid_rate(:older)}})
    assert has_element?(view, "#trade-left-total-pln", "PLN 8.60")
    assert has_element?(view, "#trade-rate-evidence", "1 EUR = 4.3000 PLN")
  end

  test "rate evidence uses yesterday grammar", %{conn: conn} do
    card = card("rate-yesterday", "Rate Yesterday", 1)
    exchange_rate("4.3000", Date.add(Date.utc_today(), -1))
    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1")

    assert has_element?(
             view,
             "#trade-rate-evidence",
             "1 EUR = 4.3000 PLN · #{Date.to_iso8601(Date.add(Date.utc_today(), -1))} (yesterday)."
           )
  end

  test "rate evidence uses N-days grammar", %{conn: conn} do
    card = card("rate-days-ago", "Rate Days Ago", 1)
    date = Date.add(Date.utc_today(), -2)
    exchange_rate("4.3000", date)
    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1")

    assert has_element?(
             view,
             "#trade-rate-evidence",
             "1 EUR = 4.3000 PLN · #{Date.to_iso8601(date)} (2 days ago)."
           )
  end

  test "exchange acquisition is enqueued at most once across a URL patch", %{conn: conn} do
    card = card("rate-once", "Rate Once", 1)

    exchange_rate(
      "4.3000",
      Date.add(Date.utc_today(), -1),
      DateTime.add(DateTime.utc_now(), -1, :day)
    )

    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1")
    assert length(all_enqueued(repo: TcgCheap.Repo, worker: ExchangeRateWorker)) == 1

    render_click(element(view, "#trade-increment-left-#{card.tcgdex_id}"))
    assert length(all_enqueued(repo: TcgCheap.Repo, worker: ExchangeRateWorker)) == 1
  end

  test "failed refresh retains cached conversion and dated evidence", %{conn: conn} do
    card = card("rate-failed", "Rate Failed", 1)
    snapshot(card, "2.50")

    exchange_rate(
      "4.3000",
      Date.add(Date.utc_today(), -1),
      DateTime.add(DateTime.utc_now(), -1, :day)
    )

    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1")
    send(view.pid, {:exchange_rate_failed, %{reason: :network}})

    assert has_element?(view, "#trade-left-total-pln", "PLN 10.75")
    assert has_element?(view, "#trade-rate-evidence", "1 EUR = 4.3000 PLN")
    assert has_element?(view, "#trade-rate-evidence", "Update failed; cached rate kept.")
  end

  test "unknown and unvalued rows remain honest and incomplete", %{conn: conn} do
    card = card("unvalued", "No Price Card", 1)
    unknown = "unknown-#{System.unique_integer([:positive])}"
    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1,#{unknown}:2")

    assert has_element?(view, "#trade-row-left-#{card.tcgdex_id}", "Fetching estimate…")
    assert has_element?(view, "#trade-row-left-#{unknown}", "Card unavailable")
    assert has_element?(view, "#trade-row-left-#{unknown}", unknown)
    assert has_element?(view, "#trade-left-total", "€0.00 + ? (3 unpriced)")
    assert has_element?(view, "#trade-comparison", "Comparison incomplete")

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: ValuationWorker,
      args: %{"tcgdex_id" => card.tcgdex_id}
    )
  end

  test "malformed, truncated, and invalid picks warn without raw staged values", %{conn: conn} do
    malformed = live!(conn, "/trade?left=bad-token&pick=bad%2Fpick")
    assert has_element?(malformed, "#trade-url-warning", "invalid")
    refute has_element?(malformed, "#trade-staging")

    huge = Enum.map_join(1..51, ",", &"x#{&1}:1")
    truncated = live!(conn, "/trade?left=#{URI.encode_www_form(huge)}")
    assert has_element?(truncated, "#trade-url-warning", "truncated")
  end

  test "stale valuation copy is consistent in rows, search, and staging", %{conn: conn} do
    card = card("stale-copy", "Stale Copy", 1)
    snapshot(card, "4.20", DateTime.add(DateTime.utc_now(), -8, :day))

    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1&pick=#{card.tcgdex_id}")
    assert has_element?(view, "#trade-row-left-#{card.tcgdex_id}", "May be outdated")
    assert has_element?(view, "#trade-selected-freshness", "May be outdated")
    render_hook(view, "search", %{"search" => %{"query" => card.name}})
    assert has_element?(view, "#trade-card-freshness-#{card.id}", "May be outdated")
  end

  test "fresh composition rows show today's update without acquiring", %{conn: conn} do
    card = card("fresh-row", "Fresh Row", 1)
    snapshot(card, "3.40")

    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1")

    assert has_element?(view, "#trade-freshness-left-#{card.tcgdex_id}", "Updated today")
    refute_enqueued(repo: TcgCheap.Repo, worker: ValuationWorker)
  end

  test "stale rows acquire once, show age, and retain their total", %{conn: conn} do
    card = card("stale-row", "Stale Row", 1)
    snapshot(card, "4.20", DateTime.add(DateTime.utc_now(), -8, :day))

    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1")

    assert has_element?(
             view,
             "#trade-freshness-left-#{card.tcgdex_id}",
             "Updated 8 days ago · May be outdated"
           )

    assert has_element?(view, "#trade-row-left-#{card.tcgdex_id}", "Updating…")
    assert has_element?(view, "#trade-left-total", "€4.20")
    assert length(queued_jobs(card)) == 1

    render_click(element(view, "#trade-increment-left-#{card.tcgdex_id}"))
    assert length(queued_jobs(card)) == 1
  end

  test "missing known rows reconcile after completion without remounting", %{conn: conn} do
    card = card("completion-row", "Completion Row", 1)
    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:2")

    assert has_element?(view, "#trade-row-left-#{card.tcgdex_id}", "Fetching estimate…")
    assert has_element?(view, "#trade-left-total", "€0.00 + ? (2 unpriced)")
    assert length(queued_jobs(card)) == 1

    send(view.pid, {:valuation_completed, %{card_printing_id: Ecto.UUID.generate()}})
    render(view)
    assert has_element?(view, "#trade-row-left-#{card.tcgdex_id}", "Fetching estimate…")

    snapshot(card, "2.75")
    send(view.pid, {:valuation_completed, %{card_printing_id: card.id}})
    render(view)
    assert has_element?(view, "#trade-row-left-#{card.tcgdex_id}", "€2.75")
    assert has_element?(view, "#trade-left-total", "€5.50")
  end

  test "mapping changes clear the old total and reacquire the canonical printing", %{conn: conn} do
    card = card("mapping-event", "Mapping Event", 1)
    snapshot(card, "8.10")
    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1")
    assert has_element?(view, "#trade-left-total", "€8.10")

    new_product_id = card.cardmarket_product_id + 1

    TcgCheap.Repo.query!(
      "UPDATE card_printings SET cardmarket_product_id = $2 WHERE id = $1",
      [Ecto.UUID.dump!(card.id), new_product_id]
    )

    TcgCheap.Repo.query!(
      "UPDATE single_valuation_snapshots SET \"current?\" = FALSE WHERE card_printing_id = $1",
      [Ecto.UUID.dump!(card.id)]
    )

    Phoenix.PubSub.broadcast(
      TcgCheap.PubSub,
      ValuationAcquisition.topic(card),
      {:card_mapping_changed, %{card_printing_id: card.id}}
    )

    render(view)
    refute has_element?(view, "#trade-left-total", "€8.10")
    assert has_element?(view, "#trade-row-left-#{card.tcgdex_id}", "Fetching estimate…")
    assert length(queued_jobs(card)) == 1
  end

  test "stale valuation failures retain cached estimates and ignore unrelated cards", %{
    conn: conn
  } do
    card = card("failed-row", "Failed Row", 1)
    snapshot(card, "6.10", DateTime.add(DateTime.utc_now(), -8, :day))
    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1")

    send(view.pid, {:valuation_failed, %{card_printing_id: Ecto.UUID.generate()}})
    render(view)
    refute has_element?(view, "#trade-row-left-#{card.tcgdex_id}", "cached estimate kept")

    send(view.pid, {:valuation_failed, %{card_printing_id: card.id}})
    render(view)

    assert has_element?(
             view,
             "#trade-row-left-#{card.tcgdex_id}",
             "Update failed · Cached estimate kept."
           )

    assert has_element?(view, "#trade-left-total", "€6.10")
  end

  test "arrow navigation reinserts exactly one active result and click stages it", %{conn: conn} do
    _first = card("arrow-first", "Arrow Pair", 1)
    second = card("arrow-second", "Arrow Pair", 2)
    {:ok, view, _html} = live(conn, ~p"/trade")
    render_hook(view, "search", %{"search" => %{"query" => "Arrow Pair"}})
    render_hook(view, "autocomplete_key", %{"key" => "ArrowDown"})
    assert has_element?(view, "#trade-search-results .active-option[aria-selected=true]")
    assert one_active_option?(view)
    render_hook(view, "autocomplete_key", %{"key" => "ArrowUp"})
    assert has_element?(view, "#trade-search-results .active-option[aria-selected=true]")
    assert one_active_option?(view)
    render_click(element(view, "#trade-card-option-#{second.id}"))
    assert has_element?(view, "#trade-staging", second.name)
  end

  test "local search has first active result and keyboard selection stages one card", %{
    conn: conn
  } do
    card = card("searchable", "Searchable Trade", 3)
    {:ok, view, _html} = live(conn, ~p"/trade")

    render_hook(view, "search", %{"search" => %{"query" => "Searchable"}})
    refute_enqueued(repo: TcgCheap.Repo, worker: ValuationWorker)

    assert has_element?(
             view,
             "#trade-card-option-#{card.id}.active-option[aria-selected=true][tabindex='-1']"
           )

    assert has_element?(view, "#trade-card-name-#{card.id}", card.name)
    assert has_element?(view, "#trade-card-set-#{card.id}", "Trade Set")
    assert has_element?(view, "#trade-card-price-#{card.id}", "Price unavailable")
    assert has_element?(view, "#trade-card-option-#{card.id} .card-image-missing")
    assert has_element?(view, "#trade-search-status[aria-live=polite]", "1 cards for searchable")

    assert has_element?(
             view,
             "#trade-search-query[aria-activedescendant='trade-card-option-#{card.id}']"
           )

    render_hook(view, "autocomplete_key", %{"key" => "Enter", "query" => "Searchable"})
    assert has_element?(view, "#trade-staging")
    assert has_element?(view, "#trade-selected-name", card.name)
    refute has_element?(view, ".evidence-slot")
    assert has_element?(view, "#add-to-left")
    assert has_element?(view, "#add-to-right")
  end

  test "trade search cannot stage an unscoped known card", %{conn: conn} do
    card = card("unscoped", "Unscoped Trade", 3, scoped?: false)
    {:ok, view, _html} = live(conn, ~p"/trade")

    render_hook(view, "search", %{"search" => %{"query" => "Unscoped Trade"}})
    refute has_element?(view, "#trade-card-option-#{card.id}")
  end

  test "trade search shows stable recovery states", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/trade")

    render_hook(view, "search", %{"search" => %{"query" => "a"}})
    assert has_element?(view, "#trade-search-short", "Type at least 2 characters.")

    assert has_element?(
             view,
             "#trade-search-status[aria-live=polite]",
             "Type at least 2 characters for a"
           )

    render_hook(view, "search", %{"search" => %{"query" => "no matching card"}})
    assert has_element?(view, "#trade-search-empty", "No cards found.")

    assert has_element?(
             view,
             "#trade-search-status[aria-live=polite]",
             "No cards found for no matching card"
           )

    render_hook(view, "search", %{"search" => %{"query" => String.duplicate("x", 101)}})
    assert has_element?(view, "#trade-search-invalid", "Search is too long.")

    assert has_element?(
             view,
             "#trade-search-status[aria-live=polite]",
             "Search too long for #{String.duplicate("x", 101)}"
           )
  end

  test "search state component renders deterministic error announcement", %{conn: _conn} do
    document =
      render_component(&TcgCheapWeb.TradeLive.search_state/1,
        status: :error,
        count: 0,
        query: "broken search"
      )
      |> LazyHTML.from_fragment()

    error = LazyHTML.query(document, "#trade-search-error.state-error")
    status = LazyHTML.query(document, "#trade-search-status[aria-live=polite]")

    assert LazyHTML.to_tree(error) != []
    assert LazyHTML.to_tree(status) != []
    assert inspect(LazyHTML.to_tree(error)) =~ "Search unavailable. Try again."
    assert inspect(LazyHTML.to_tree(status)) =~ "Search unavailable for broken search"
  end

  test "add, merge, opposite sides, and quantity controls produce canonical URL patches", %{
    conn: conn
  } do
    first = card("mutate-a", "Mutation A", 1)
    second = card("mutate-b", "Mutation B", 2)
    {:ok, view, _html} = live(conn, "/trade?pick=#{first.tcgdex_id}")
    refute_enqueued(repo: TcgCheap.Repo, worker: ValuationWorker)

    render_click(element(view, "#add-to-left"))
    expected_path = "/trade?left=#{first.tcgdex_id}%3A1"
    assert_patch(view, expected_path)
    refute expected_path =~ first.name
    refute expected_path =~ first.id
    refute expected_path =~ "1.25"
    render_click(element(view, "#add-to-left"))
    assert_patch(view, "/trade?left=#{first.tcgdex_id}%3A2")
    render_click(element(view, "#add-to-right"))
    assert_patch(view, "/trade?left=#{first.tcgdex_id}%3A2&right=#{first.tcgdex_id}%3A1")

    render_hook(view, "search", %{"search" => %{"query" => second.name}})
    render_hook(view, "autocomplete_key", %{"key" => "Enter", "query" => second.name})
    assert has_element?(view, "#trade-staging", second.name)
    render_click(element(view, "#add-to-left"))

    assert_patch(
      view,
      "/trade?left=#{first.tcgdex_id}%3A2%2C#{second.tcgdex_id}%3A1&right=#{first.tcgdex_id}%3A1"
    )

    render_click(element(view, "#trade-decrement-left-#{first.tcgdex_id}"))

    assert has_element?(
             view,
             "#trade-increment-left-#{first.tcgdex_id}[aria-label='Add one Mutation A to Left side'] .hero-plus"
           )

    assert has_element?(
             view,
             "#trade-decrement-left-#{first.tcgdex_id}[aria-label='Subtract one Mutation A from Left side'] .hero-minus"
           )

    assert_patch(
      view,
      "/trade?left=#{first.tcgdex_id}%3A1%2C#{second.tcgdex_id}%3A1&right=#{first.tcgdex_id}%3A1"
    )

    render_click(element(view, "#trade-remove-left-#{second.tcgdex_id}"))
    assert_patch(view, "/trade?left=#{first.tcgdex_id}%3A1&right=#{first.tcgdex_id}%3A1")
    render_click(element(view, "#trade-decrement-left-#{first.tcgdex_id}"))
    assert_patch(view, "/trade?right=#{first.tcgdex_id}%3A1")
    assert has_element?(view, "#trade-announcements", "left")
  end

  test "untrusted quantity events and absent IDs cannot inject rows", %{conn: conn} do
    card = card("safe-event", "Safe Event", 1)
    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}:1")

    render_hook(view, "increment", %{"side" => "bogus", "tcgdex-id" => "injected"})
    render_hook(view, "increment", %{"side" => "left", "tcgdex-id" => "injected"})
    render_hook(view, "add_to_side", %{"side" => "left"})
    refute has_element?(view, "#trade-row-left-injected")
    assert has_element?(view, "#trade-left-total", "€0.00 + ? (1 unpriced)")
  end

  test "known row detail link preserves only canonical trade composition", %{conn: conn} do
    card = card("return-link", "Return Link", 1)
    {:ok, view, _html} = live(conn, "/trade?left=#{card.tcgdex_id}%3A1")

    assert has_element?(
             view,
             "#trade-detail-left-#{card.tcgdex_id}[href='/cards/#{card.tcgdex_id}?return_to=%2Ftrade%3Fleft%3D#{card.tcgdex_id}%253A1']"
           )
  end

  test "card detail accepts only local canonical trade returns", %{conn: conn} do
    card = card("return-validation", "Return Validation", 1)
    {:ok, detail, _html} = live(conn, "/cards/#{card.tcgdex_id}")

    assert has_element?(
             detail,
             "#card-detail-add-to-trade.card-detail-add-to-trade[href='/trade?pick=#{card.tcgdex_id}']"
           )

    refute has_element?(detail, "#card-detail-add-to-trade[href*='left']")
    refute has_element?(detail, "#card-detail-add-to-trade[href*='right']")
    {:ok, valid, _html} = live(conn, "/cards/#{card.tcgdex_id}?return_to=%2Ftrade")
    assert has_element?(valid, "#card-detail-back[href='/trade']", "Back to trade")

    {:ok, canonical, _html} =
      live(conn, "/cards/#{card.tcgdex_id}?return_to=%2Ftrade%3Fleft%3Dsafe%253A1")

    assert has_element?(
             canonical,
             "#card-detail-back[href='/trade?left=safe%3A1']",
             "Back to trade"
           )

    for value <- [
          "https%3A%2F%2Fevil.example",
          "%2F%2Fevil.example",
          "%2Fcards%2Felse",
          "%2Ftrade%23fragment",
          "%2Ftrade%3Funknown%3D1",
          "%2Ftrade%3Fleft%3Dbad%252Fvalue"
        ] do
      {:ok, rejected, _html} = live(conn, "/cards/#{card.tcgdex_id}?return_to=#{value}")
      assert has_element?(rejected, "#card-detail-back[href='/']", "Back to search")
    end
  end

  defp live!(conn, path), do: elem(live(conn, path), 1)

  defp one_active_option?(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#trade-search-results [role=option][aria-selected=true]")
    |> LazyHTML.to_tree()
    |> length()
    |> Kernel.==(1)
  end

  defp card(prefix, name, number, fixture_opts \\ []) do
    suffix = System.unique_integer([:positive])
    set = Core.import_card_set!(%{tcgdex_id: "trade-set-#{suffix}", name: "Trade Set"})

    TcgCheap.TestSupport.import_card_printing!(
      %{
        tcgdex_id: "#{prefix}-#{suffix}",
        name: name,
        set_name: set.name,
        collector_number: Integer.to_string(number),
        card_set_id: set.id,
        mapping_status: "matched",
        cardmarket_product_id: suffix
      },
      fixture_opts
    )
  end

  defp snapshot(card, value, fetched_at \\ DateTime.utc_now()) do
    Core.record_single_valuation!(%{
      card_printing_id: card.id,
      value_eur: Decimal.new(value),
      policy_version: @policy,
      source: "test",
      source_metric: "avg7",
      fetched_at: fetched_at,
      cardmarket_product_id: card.cardmarket_product_id
    })
  end

  defp exchange_rate(value, effective_date \\ Date.utc_today(), fetched_at \\ DateTime.utc_now()) do
    Core.record_exchange_rate!(%{
      source: "nbp",
      table: "A",
      base_currency: "EUR",
      quote_currency: "PLN",
      rate: Decimal.new(value),
      effective_date: effective_date,
      publication_number: "trade-test-#{System.unique_integer([:positive])}",
      fetched_at: fetched_at
    })
  end

  defp invalid_rate(:future),
    do: invalid_rate_struct(%{effective_date: Date.add(Date.utc_today(), 1)})

  defp invalid_rate(:noncanonical), do: invalid_rate_struct(%{source: "ecb"})
  defp invalid_rate(:nan), do: invalid_rate_struct(%{rate: Decimal.new("NaN")})
  defp invalid_rate(:infinity), do: invalid_rate_struct(%{rate: Decimal.new("Infinity")})
  defp invalid_rate(:blank_publication), do: invalid_rate_struct(%{publication_number: "  "})

  defp invalid_rate(:future_fetched),
    do: invalid_rate_struct(%{fetched_at: DateTime.add(DateTime.utc_now(), 60, :second)})

  defp invalid_rate(:older),
    do: invalid_rate_struct(%{effective_date: Date.add(Date.utc_today(), -1)})

  defp invalid_rate_struct(overrides) do
    struct(
      %ExchangeRate{
        source: "nbp",
        table: "A",
        base_currency: "EUR",
        quote_currency: "PLN",
        rate: Decimal.new("4.1000"),
        effective_date: Date.utc_today(),
        publication_number: "invalid-test",
        fetched_at: DateTime.utc_now()
      },
      overrides
    )
  end

  defp queued_jobs(card) do
    all_enqueued(
      repo: TcgCheap.Repo,
      worker: ValuationWorker,
      args: %{"local_card_id" => card.id}
    )
  end

  defp unique_ip do
    n = System.unique_integer([:positive])

    {0x2001, 0xDB8, 0, 1, n >>> 48 &&& 0xFFFF, n >>> 32 &&& 0xFFFF, n >>> 16 &&& 0xFFFF,
     n &&& 0xFFFF}
  end

  defp fill_public_limit(address) do
    limit =
      :tcg_cheap
      |> Application.fetch_env!(:public_acquisition_limiter)
      |> Keyword.fetch!(:limit)

    for _attempt <- 1..limit, do: assert(:ok = PublicAcquisitionLimiter.reserve(address))
  end
end
