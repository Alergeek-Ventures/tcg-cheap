defmodule TcgCheapWeb.CardDetailLiveTest do
  import Oban.Testing
  import Phoenix.LiveViewTest
  use TcgCheapWeb.ConnCase, async: false

  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.{ValuationAcquisition, ValuationWorker}

  @policy "tcgdex_cardmarket_v1"

  test "an unknown exact printing is honest and offers a way back", %{conn: conn} do
    id = "missing-#{System.unique_integer([:positive])}"
    {:ok, view, _html} = live(conn, ~p"/cards/#{id}")

    assert has_element?(view, "#card-detail-not-found")
    assert has_element?(view, "#card-detail-not-found-back[href='/']")
    assert has_element?(view, "#card-detail-not-found", "No provider was contacted.")
  end

  test "a missing valuation renders the full local-card detail and queues acquisition", %{
    conn: conn
  } do
    card = create_card("missing")

    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(view, "#card-detail-identity")
    assert has_element?(view, "#card-detail-title", card.name)
    assert has_element?(view, "#card-detail-metadata", card.tcgdex_id)
    assert has_element?(view, "#card-image-rights-note")

    assert has_element?(
             view,
             "#card-detail-disclaimer",
             "not affiliated with Pokémon or Cardmarket"
           )

    assert has_element?(view, ".methodology", "tcgdex_cardmarket_v1")
    assert has_element?(view, "#valuation-value", "?")
    assert has_element?(view, "#valuation-unpriced")
    assert has_element?(view, "#valuation-fetching")
    assert has_element?(view, "#valuation-history-empty")
    assert has_element?(view, "#valuation-history-collecting")

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

  test "a fresh cached valuation shows provenance and does not queue refresh", %{conn: conn} do
    card = create_card("fresh")
    fetched_at = DateTime.utc_now() |> DateTime.truncate(:second)
    record_snapshot(card, Decimal.new("12.345"), fetched_at)

    {:ok, view, _html} = live(conn, ~p"/cards/#{card.tcgdex_id}")

    assert has_element?(view, "#valuation-value", "12.35")
    assert has_element?(view, "#valuation-fresh")
    assert has_element?(view, "#valuation-provenance", "tcgdex_cardmarket")
    assert has_element?(view, "#valuation-provenance", "avg7")
    assert has_element?(view, "#valuation-provenance", @policy)
    assert has_element?(view, "#valuation-provenance", "UTC")

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

    assert [_ledger] =
             document |> LazyHTML.query("#valuation-history-ledger") |> LazyHTML.to_tree()

    refute_enqueued(
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
    assert has_element?(view, "#valuation-stale")
    assert has_element?(view, "#valuation-fetching")

    assert [job] =
             all_enqueued(
               repo: TcgCheap.Repo,
               worker: ValuationWorker,
               args: %{"local_card_id" => card.id}
             )

    assert job.args["tcgdex_id"] == card.tcgdex_id
  end

  test "a valuation completion updates value, freshness, history and ledger", %{conn: conn} do
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
    assert has_element?(view, "#valuation-history-chart")
    assert has_element?(view, "#valuation-history-ledger")
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
    day_a = Date.to_iso8601(DateTime.to_date(DateTime.add(now, -2, :day)))
    day_b = Date.to_iso8601(DateTime.to_date(now))

    assert has_element?(view, "#valuation-history-chart")
    assert has_element?(view, "#valuation-history-ledger")
    assert has_element?(view, "#valuation-history-day-#{day_a}")
    assert has_element?(view, "#valuation-history-day-#{day_b}")
    assert has_element?(view, "#valuation-history-segment-0")
    assert has_element?(view, "#valuation-history-segment-1")
    refute has_element?(view, "#valuation-history-segment-2")
  end

  defp create_card(label) do
    suffix = System.unique_integer([:positive])

    Core.create_card_printing!(%{
      tcgdex_id: "detail-#{label}-#{suffix}",
      name: "Detail Card #{label} #{suffix}",
      set_name: "Detail Set #{suffix}",
      collector_number: "#{suffix}"
    })
  end

  defp record_snapshot(card, value, fetched_at) do
    Core.record_single_valuation!(%{
      card_printing_id: card.id,
      value_eur: value,
      policy_version: @policy,
      source: "tcgdex_cardmarket",
      source_metric: "avg7",
      fetched_at: fetched_at
    })
  end
end
