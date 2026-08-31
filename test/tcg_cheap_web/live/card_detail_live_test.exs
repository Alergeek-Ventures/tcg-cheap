defmodule TcgCheapWeb.CardDetailLiveTest do
  import Bitwise
  import Oban.Testing
  import Phoenix.LiveViewTest
  use TcgCheapWeb.ConnCase, async: false

  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.{ValuationAcquisition, ValuationWorker}
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

  test "an unknown exact printing is honest and offers a way back", %{conn: conn} do
    id = "missing-#{System.unique_integer([:positive])}"
    {:ok, view, _html} = live(conn, ~p"/cards/#{id}")

    assert has_element?(view, "#card-detail-not-found")
    assert has_element?(view, "#card-detail-not-found-back[href='/']", "Back to search")
    assert has_element?(view, "#card-detail-not-found", "Try another search.")
    refute has_element?(view, "#card-detail-not-found", "provider")
  end

  test "a known but unscoped printing is publicly not found", %{conn: conn} do
    card = create_card("unscoped", scoped?: false)
    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(view, "#card-detail-not-found")
    refute has_element?(view, "#card-detail-identity")
  end

  test "a missing valuation renders the full local-card detail and queues acquisition", %{
    conn: conn
  } do
    card = create_card("missing")

    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(view, "#card-detail-identity")
    assert has_element?(view, "#card-detail-title", card.name)
    assert has_element?(view, "#valuation-title", "Current estimate")
    assert has_element?(view, "#history-title", "Price history")
    assert has_element?(view, "#valuation-history-window", "Last 30 days")
    assert has_element?(view, "#archive-wordmark", "TCG CHEAP")
    assert has_element?(view, "#archive-wordmark .fluent-icon")
    refute has_element?(view, "#archive-header", "Card details")
    refute has_element?(view, "#card-detail-metadata", "TCGDEX ID")
    refute has_element?(view, "#card-detail-metadata", card.tcgdex_id)
    assert has_element?(view, "#card-detail-image-missing")
    refute has_element?(view, "#card-detail-image")
    assert has_element?(view, "#card-detail-metadata-title", "Printing")
    assert has_element?(view, "#legal-format-standard.legal-format-unknown")
    assert has_element?(view, "#legal-format-expanded.legal-format-unknown")
    assert has_element?(view, "#legal-format-glc.legal-format-not-legal")
    assert has_element?(view, "#legal-format-standard-trigger[aria-label='Standard']")

    assert has_element?(
             view,
             "#legal-format-standard-trigger[aria-describedby='legal-format-standard-copy']"
           )

    assert has_element?(
             view,
             "#legal-format-standard-copy",
             "Standard legality unavailable."
           )

    assert has_element?(view, "#card-detail-price-note span", "Estimate only")
    assert has_element?(view, "#card-detail-price-note small", "Condition and shipping may vary.")

    assert has_element?(
             view,
             "#card-detail-image-missing[aria-label='No image is available for this card printing.']"
           )

    refute has_element?(view, "#valuation-details")
    refute has_element?(view, "#valuation-provenance")
    refute has_element?(view, "Cardmarket")
    refute has_element?(view, "TCGdex")
    refute has_element?(view, "not affiliated")
    assert has_element?(view, "#valuation-value", "?")
    assert has_element?(view, "#valuation-unpriced")
    assert has_element?(view, "#valuation-fetching")
    assert has_element?(view, "#valuation-history-empty", "No price history yet.")
    refute has_element?(view, "#valuation-history-collecting")

    refute has_element?(
             view,
             "#valuation-history-empty",
             "No successful observations in the last 30 days."
           )

    refute has_element?(view, "#valuation-history-collecting", "History is still being collected")

    assert has_element?(
             view,
             "#valuation-live-region[role=status][aria-live=polite][aria-atomic=true]"
           )

    assert [job] =
             all_enqueued(
               repo: TcgCheap.Repo,
               worker: ValuationWorker,
               args: %{"local_card_id" => card.id}
             )

    assert job.args["tcgdex_id"] == card.tcgdex_id
  end

  test "a valid TCGdex image renders the high WebP detail image", %{conn: conn} do
    card = create_card("image", image_url: "https://assets.tcgdex.net/en/swsh/swshp/1")

    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(
             view,
             "#card-detail-image[src='https://assets.tcgdex.net/en/swsh/swshp/1/high.webp'][width='600'][height='825'][loading='eager'][fetchpriority='high'][decoding='async'][referrerpolicy='no-referrer']"
           )

    assert has_element?(
             view,
             "#card-detail-image[alt='#{card.name}, #{card.set_name}, collector number #{card.collector_number}']"
           )

    refute has_element?(view, "#card-image-source-note")
    refute has_element?(view, "#card-detail-image-missing")
  end

  test "an invalid TCGdex image keeps the honest fallback", %{conn: conn} do
    card = create_card("invalid-image", image_url: "https://example.com/card.jpg")

    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(view, "#card-detail-image-missing")
    refute has_element?(view, "img")
  end

  test "a fresh cached valuation shows a concise calculation tooltip", %{
    conn: conn
  } do
    card = create_card("fresh")
    fetched_at = DateTime.utc_now() |> DateTime.truncate(:second)
    record_snapshot(card, Decimal.new("12.345"), fetched_at)

    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(view, "#valuation-value", "12.35")
    assert has_element?(view, "#valuation-fresh", "Updated today")
    refute has_element?(view, "#valuation-title", "EUR / 7-DAY FRESHNESS")

    assert has_element?(view, "#card-detail-price-note span", "Estimate only")
    assert has_element?(view, "#card-detail-price-note small", "Condition and shipping may vary.")

    assert has_element?(
             view,
             "#valuation-price-row[phx-key=escape][phx-window-keydown]"
           )

    assert has_element?(view, "#valuation-info-trigger[phx-blur][phx-click-away]")

    assert has_element?(
             view,
             "#valuation-info[phx-hook][data-tooltip-target='valuation-price-row']"
           )

    assert has_element?(view, "#valuation-info-copy", "Cardmarket via TCGdex")
    assert has_element?(view, "#valuation-info-copy", "applied consistently to every card")
    refute has_element?(view, "#valuation-info-copy", "7-day average")
    refute has_element?(view, "#valuation-info-copy", @policy)
    refute has_element?(view, "#valuation-basis")
    refute has_element?(view, "#valuation-provenance")
    refute has_element?(view, "#archive-header", "PRINTING ARCHIVE")

    refute_enqueued(
      repo: TcgCheap.Repo,
      worker: ValuationWorker,
      args: %{"local_card_id" => card.id}
    )
  end

  test "a fresh cached valuation is present in the disconnected response", %{conn: conn} do
    card = create_card("disconnected")
    fetched_at = DateTime.utc_now() |> DateTime.truncate(:second)
    record_snapshot(card, Decimal.new("12.345"), fetched_at)

    html = conn |> get(~p"/cards/#{card.tcgdex_id}") |> html_response(200)
    document = LazyHTML.from_fragment(html)

    assert [_valuation] = document |> LazyHTML.query("#valuation-value") |> LazyHTML.to_tree()

    assert [] == document |> LazyHTML.query("#valuation-history-chart") |> LazyHTML.to_tree()
    assert [] == document |> LazyHTML.query("#valuation-history-title") |> LazyHTML.to_tree()

    assert [] ==
             document |> LazyHTML.query("#valuation-history-description") |> LazyHTML.to_tree()

    assert [] ==
             document |> LazyHTML.query("#valuation-history-explanation") |> LazyHTML.to_tree()

    assert inspect(document |> LazyHTML.query("#valuation-history-summary") |> LazyHTML.to_tree()) =~
             "Last update"

    refute inspect(document |> LazyHTML.query("#valuation-history-summary") |> LazyHTML.to_tree()) =~
             "First observed"

    refute inspect(document |> LazyHTML.query("#valuation-history-summary") |> LazyHTML.to_tree()) =~
             "Observations"

    assert inspect(
             document
             |> LazyHTML.query("#valuation-history-summary time")
             |> LazyHTML.to_tree()
           ) =~
             Date.to_iso8601(DateTime.to_date(fetched_at))

    assert [] ==
             document |> LazyHTML.query("#valuation-history-observations") |> LazyHTML.to_tree()

    assert [] == document |> LazyHTML.query("#valuation-history-ledger") |> LazyHTML.to_tree()

    refute_enqueued(
      repo: TcgCheap.Repo,
      worker: ValuationWorker,
      args: %{"local_card_id" => card.id}
    )
  end

  test "printing details have distinct labels and honest legal format icons", %{conn: conn} do
    card =
      create_card("metadata",
        rarity: "Rare",
        category: "Pokemon",
        illustrator: "Archive Artist",
        regulation_mark: "G",
        standard_legal: true,
        expanded_legal: true
      )

    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(view, "#card-detail-metadata-title", "Printing")
    assert has_element?(view, "#card-detail-metadata .card-detail-metadata-item dt", "Rarity")
    assert has_element?(view, "#card-detail-metadata .card-detail-metadata-item dd", "Rare")

    assert has_element?(view, "#legal-format-standard-trigger")
    assert has_element?(view, "#legal-format-expanded-trigger")
    assert has_element?(view, "#legal-format-glc-trigger")
    assert has_element?(view, "#legal-format-standard.legal-format-legal")
    assert has_element?(view, "#legal-format-expanded.legal-format-legal")
    assert has_element?(view, "#legal-format-glc.legal-format-legal")

    assert has_element?(
             view,
             "#legal-format-standard-copy",
             "Legal for Standard."
           )

    assert has_element?(
             view,
             "#legal-format-glc-copy",
             "Legal for Gym Leader Challenge."
           )

    assert has_element?(
             view,
             "#legal-format-standard-trigger[aria-describedby='legal-format-standard-copy']"
           )

    assert has_element?(view, "#legal-formats[phx-key=escape][phx-window-keydown]")

    assert has_element?(
             view,
             "#legal-format-standard[phx-hook][data-tooltip-target='legal-format-standard']"
           )

    refute has_element?(view, "#card-detail-metadata .archive-chip")
    refute has_element?(view, "#card-detail-metadata", "Standard · Expanded")

    refute has_element?(view, "#card-detail-metadata", "TCGDEX ID")
    refute has_element?(view, "#card-detail-metadata", card.tcgdex_id)
  end

  test "legal format icons distinguish false and unavailable data", %{conn: conn} do
    card = create_card("legality-honesty", standard_legal: false, expanded_legal: nil)

    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(view, "#legal-formats")
    assert has_element?(view, "#legal-format-standard.legal-format-not-legal")
    assert has_element?(view, "#legal-format-expanded.legal-format-unknown")
    assert has_element?(view, "#legal-format-glc.legal-format-not-legal")

    assert has_element?(
             view,
             "#legal-format-standard-copy",
             "Not eligible for Standard."
           )

    assert has_element?(
             view,
             "#legal-format-expanded-copy",
             "Expanded legality unavailable."
           )

    assert has_element?(view, "#legal-format-standard-trigger[phx-blur][phx-click-away]")

    assert has_element?(
             view,
             "#legal-format-expanded-trigger[aria-describedby='legal-format-expanded-copy']"
           )

    assert has_element?(
             view,
             "#legal-format-glc-copy",
             "Not eligible for Gym Leader Challenge."
           )
  end

  test "GLC marks an ordinary Pokémon legal", %{conn: conn} do
    card = create_card("glc-legal", category: "Pokemon", name: "Pikachu")
    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(view, "#legal-format-glc.legal-format-legal")
    assert has_element?(view, "#legal-format-glc-copy", "Legal for Gym Leader Challenge.")
  end

  test "GLC marks rule-box and banned printings not eligible", %{conn: conn} do
    rule_box = create_card("glc-rule-box", category: "Pokemon", name: "Pikachu V")
    banned = create_card("glc-banned", category: "Trainer", tcgdex_id: "xy4-99")

    {:ok, rule_view, _html} = live(conn, ~p"/cards/#{rule_box.tcgdex_id}")
    {:ok, banned_view, _html} = live(conn, ~p"/cards/#{banned.tcgdex_id}")

    assert has_element?(rule_view, "#legal-format-glc.legal-format-not-legal")
    assert has_element?(banned_view, "#legal-format-glc.legal-format-not-legal")

    assert has_element?(
             banned_view,
             "#legal-format-glc-copy",
             "Not eligible for Gym Leader Challenge."
           )
  end

  test "unknown Standard and Expanded legality use concise unavailable copy", %{conn: conn} do
    card =
      create_card("glc-unknown", category: "Trainer", standard_legal: nil, expanded_legal: nil)

    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(view, "#legal-format-standard-copy", "Standard legality unavailable.")
    assert has_element?(view, "#legal-format-expanded-copy", "Expanded legality unavailable.")
  end

  test "a valuation from a different cardmarket mapping is hidden from current and history", %{
    conn: conn
  } do
    card = create_card("mapping-mismatch")
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    old_product_id = card.cardmarket_product_id

    record_snapshot(card, Decimal.new("12.34"), DateTime.add(now, -2, :day), old_product_id)
    record_snapshot(card, Decimal.new("23.45"), now, old_product_id)

    TcgCheap.Repo.query!(
      "UPDATE card_printings SET cardmarket_product_id = $2 WHERE id = $1",
      [Ecto.UUID.dump!(card.id), old_product_id + 1]
    )

    TcgCheap.Repo.query!(
      """
      UPDATE single_valuation_snapshots
      SET "current?" = TRUE
      WHERE id = (
        SELECT id FROM single_valuation_snapshots
        WHERE card_printing_id = $1
        ORDER BY fetched_at DESC
        LIMIT 1
      )
      """,
      [Ecto.UUID.dump!(card.id)]
    )

    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(view, "#valuation-value", "?")
    assert has_element?(view, "#valuation-unpriced")
    assert has_element?(view, "#valuation-history-empty")
  end

  test "a mounted card clears the old valuation epoch when its mapping changes", %{conn: conn} do
    card = create_card("mapping-event")
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    old_product_id = card.cardmarket_product_id

    record_snapshot(card, Decimal.new("12.34"), DateTime.add(now, -2, :day))
    record_snapshot(card, Decimal.new("23.45"), now)
    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")
    assert has_element?(view, "#valuation-value", "23.45")

    TcgCheap.Repo.query!(
      "UPDATE card_printings SET cardmarket_product_id = $2 WHERE id = $1",
      [Ecto.UUID.dump!(card.id), old_product_id + 1]
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
    assert has_element?(view, "#valuation-value", "?")
    assert has_element?(view, "#valuation-history-empty")
  end

  test "an unresolved card requests acquisition after a later matched mapping", %{conn: conn} do
    card = create_card("mapping-later", mapping_status: "unmatched", cardmarket_product_id: nil)
    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")
    assert has_element?(view, "#valuation-unpriced")

    TcgCheap.Repo.query!(
      "UPDATE card_printings SET mapping_status = 'matched', cardmarket_product_id = $2 WHERE id = $1",
      [
        Ecto.UUID.dump!(card.id),
        card.id |> String.slice(0, 8) |> :erlang.phash2(10_000) |> max(1)
      ]
    )

    Phoenix.PubSub.broadcast(
      TcgCheap.PubSub,
      ValuationAcquisition.topic(card),
      {:card_mapping_changed, %{card_printing_id: card.id}}
    )

    render(view)
    assert has_element?(view, "#valuation-fetching")

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: ValuationWorker,
      args: %{"local_card_id" => card.id}
    )
  end

  test "a stale cached valuation remains visible while refresh is queued", %{conn: conn} do
    card = create_card("stale")
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    record_snapshot(card, Decimal.new("17.20"), DateTime.add(now, -8, :day))

    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(view, "#valuation-value", "17.20")
    assert has_element?(view, "#valuation-stale", "May be outdated")
    assert has_element?(view, "#valuation-stale", "Updated 8 days ago · May be outdated")
    assert has_element?(view, "#valuation-fetching")

    assert [job] =
             all_enqueued(
               repo: TcgCheap.Repo,
               worker: ValuationWorker,
               args: %{"local_card_id" => card.id}
             )

    assert job.args["tcgdex_id"] == card.tcgdex_id
  end

  test "a peer at the public acquisition limit keeps local fallback and queues no refresh", %{
    conn: conn
  } do
    card = create_card("public-limit")
    fill_public_limit(conn.remote_ip)

    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(view, "#valuation-value", "?")
    assert has_element?(view, "#valuation-unpriced")
    assert has_element?(view, "#valuation-refresh-failed")
    refute has_element?(view, "#valuation-fetching")

    refute_enqueued(
      repo: TcgCheap.Repo,
      worker: ValuationWorker,
      args: %{"local_card_id" => card.id}
    )
  end

  test "a valuation completion updates value, freshness and history chart", %{conn: conn} do
    card = create_card("completion")
    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    snapshot =
      record_snapshot(
        card,
        Decimal.new("23.40"),
        DateTime.utc_now() |> DateTime.truncate(:second)
      )

    assert :ok =
             Phoenix.PubSub.broadcast(
               TcgCheap.PubSub,
               ValuationAcquisition.topic(card),
               {:valuation_completed, %{card_printing_id: card.id, snapshot: snapshot}}
             )

    render(view)
    assert has_element?(view, "#valuation-value", "23.40")
    assert has_element?(view, "#valuation-fresh")
    assert has_element?(view, "#valuation-history-collecting", "Not enough price history yet.")
    assert has_element?(view, "#valuation-history-summary", "Last update")
    refute has_element?(view, "#valuation-history-observations")
    refute has_element?(view, "#valuation-history-ledger")
    refute has_element?(view, "#valuation-history-chart")
    refute has_element?(view, "#valuation-history-title")
    refute has_element?(view, "#valuation-history-description")
    refute has_element?(view, "#valuation-history-details")
    refute has_element?(view, "#valuation-fetching")
  end

  test "a terminal refresh failure retains a stale cached value without fetching", %{conn: conn} do
    card = create_card("failure")
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    record_snapshot(card, Decimal.new("31.10"), DateTime.add(now, -8, :day))
    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert :ok =
             Phoenix.PubSub.broadcast(
               TcgCheap.PubSub,
               ValuationAcquisition.topic(card),
               {:valuation_failed, %{card_printing_id: card.id, reason: :provider_not_found}}
             )

    render(view)
    assert has_element?(view, "#valuation-value", "31.10")
    assert has_element?(view, "#valuation-stale")
    assert has_element?(view, "#valuation-refresh-failed")
    refute has_element?(view, "#valuation-fetching")
  end

  test "daily history leaves a chart gap for an absent UTC calendar day", %{conn: conn} do
    card = create_card("gap")
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    record_snapshot(card, Decimal.new("40.00"), DateTime.add(now, -2, :day))
    record_snapshot(card, Decimal.new("42.00"), now)

    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")
    assert has_element?(view, "#valuation-history-chart")
    assert has_element?(view, "#valuation-history-chart-wrap .history-chart-plot")
    assert has_element?(view, "#valuation-history-chart-wrap[phx-key=escape][phx-window-keydown]")

    assert has_element?(
             view,
             "#valuation-history-point-#{Date.to_iso8601(DateTime.to_date(now))}"
           )

    assert has_element?(
             view,
             "#valuation-history-point-#{Date.to_iso8601(DateTime.to_date(now))}[type='button'][phx-blur][phx-click-away][phx-hook][data-tooltip-target]"
           )

    assert has_element?(
             view,
             "#valuation-history-point-#{Date.to_iso8601(DateTime.to_date(now))}",
             "€42.00"
           )

    assert has_element?(view, "#valuation-history-chart-wrap", "Max €42.00")
    assert has_element?(view, "#valuation-history-chart-wrap", "Min €40.00")
    window_start = now |> DateTime.to_date() |> Date.add(-29)

    assert has_element?(
             view,
             "#valuation-history-chart-wrap time[datetime='#{Date.to_iso8601(window_start)}']",
             Calendar.strftime(window_start, "%b %-d")
           )

    assert has_element?(
             view,
             "#valuation-history-chart-wrap time[datetime='#{Date.to_iso8601(DateTime.to_date(now))}']",
             Calendar.strftime(DateTime.to_date(now), "%b %-d")
           )

    assert has_element?(view, "#valuation-history-description")
    assert has_element?(view, "#valuation-history-summary dt", "Last update")
    refute has_element?(view, "#valuation-history-summary dt", "First observed")
    refute has_element?(view, "#valuation-history-summary dt", "Observations")
    refute has_element?(view, "#valuation-history-explanation")
    refute has_element?(view, "#valuation-history-observations")

    assert has_element?(
             view,
             "#valuation-history-summary time[datetime='#{Date.to_iso8601(DateTime.to_date(now))}']"
           )

    refute has_element?(view, "#valuation-history-details")
    assert has_element?(view, "#valuation-history-segment-0")
    assert has_element?(view, "#valuation-history-segment-1")
    refute has_element?(view, "#valuation-history-segment-2")
  end

  defp create_card(label, overrides \\ []) do
    suffix = System.unique_integer([:positive])
    fixture_opts = Keyword.take(overrides, [:scoped?, :expires_on])
    attribute_overrides = Keyword.drop(overrides, [:scoped?, :expires_on])

    attrs = %{
      tcgdex_id: "detail-#{label}-#{suffix}",
      name: "Detail Card #{label} #{suffix}",
      set_name: "Detail Set #{suffix}",
      collector_number: "#{suffix}",
      mapping_status: "matched",
      cardmarket_product_id: suffix
    }

    TcgCheap.TestSupport.import_card_printing!(
      Map.merge(attrs, Map.new(attribute_overrides)),
      fixture_opts
    )
  end

  defp record_snapshot(card, value, fetched_at, product_id \\ nil) do
    Core.record_single_valuation!(%{
      card_printing_id: card.id,
      value_eur: value,
      policy_version: @policy,
      source: "tcgdex_cardmarket",
      source_metric: "avg7",
      fetched_at: fetched_at,
      cardmarket_product_id: product_id || card.cardmarket_product_id
    })
  end

  defp unique_ip do
    n = System.unique_integer([:positive])

    {0x2001, 0xDB8, 0, 0, n >>> 48 &&& 0xFFFF, n >>> 32 &&& 0xFFFF, n >>> 16 &&& 0xFFFF,
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
