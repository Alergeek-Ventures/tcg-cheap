defmodule TcgCheap.Pricing.HomepageDiscoveryTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Core

  @as_of ~U[2026-08-10 12:00:00.000000Z]

  test "price changes require qualified current evidence and have stable signed ordering" do
    up = card("up")
    down = card("down")
    one_point = card("one-point")
    short = card("short")
    small = card("small")
    future = card("future")
    other_policy = card("other-policy")
    not_current = card("not-current")

    snapshots(up, [{8, "10"}, {0, "20"}])
    snapshots(down, [{8, "20"}, {0, "10"}])
    snapshots(one_point, [{0, "20"}])
    snapshots(short, [{0, "10"}, {0, "20"}])
    snapshots(small, [{8, "10"}, {0, "10.40"}])
    snapshots(future, [{8, "10"}, {-1, "20"}])
    snapshots(other_policy, [{8, "10"}, {0, "20"}], "other")
    snapshots(not_current, [{8, "10"}, {0, "20"}])

    Repo.query!(
      "UPDATE single_valuation_snapshots SET \"current?\" = FALSE WHERE card_printing_id = $1",
      [
        Ecto.UUID.dump!(not_current.id)
      ]
    )

    assert {:ok, [first, second, third]} = Core.list_homepage_price_changes(@as_of, 4)

    assert Enum.map([first, second, third], & &1.tcgdex_id) == [
             up.tcgdex_id,
             down.tcgdex_id,
             small.tcgdex_id
           ]

    assert first.card_printing_id == up.id
    assert Decimal.equal?(first.change_percent, Decimal.new("100.00"))
    assert Decimal.equal?(second.change_percent, Decimal.new("-50.00"))
    assert Decimal.equal?(third.change_percent, Decimal.new("4.00"))
    assert first.start_date == Date.add(DateTime.to_date(@as_of), -8)
    assert first.current_date == DateTime.to_date(@as_of)
    assert first.current_fetched_at == @as_of

    assert {:ok, [only]} = Core.list_homepage_price_changes(@as_of, 1)
    assert only.tcgdex_id == up.tcgdex_id
  end

  test "price changes use UTC daily closes and the inclusive 30-date window" do
    card = card("utc-boundary")
    as_of_date = DateTime.to_date(@as_of)

    snapshot(card, "5", DateTime.new!(Date.add(as_of_date, -30), ~T[23:59:00], "Etc/UTC"))
    snapshot(card, "10", DateTime.new!(Date.add(as_of_date, -29), ~T[01:00:00], "Etc/UTC"))
    snapshot(card, "12", DateTime.new!(Date.add(as_of_date, -29), ~T[23:00:00], "Etc/UTC"))
    snapshot(card, "18", @as_of)

    assert {:ok, [change]} = Core.list_homepage_price_changes(@as_of, 4)
    assert change.start_date == Date.add(as_of_date, -29)
    assert change.current_date == as_of_date
    assert change.current_fetched_at == @as_of
    assert Decimal.equal?(change.start_value_eur, Decimal.new("12"))
    assert Decimal.equal?(change.current_value_eur, Decimal.new("18"))
    assert Decimal.equal?(change.change_percent, Decimal.new("50.00"))
  end

  test "a ten item result balances risers and fallers without weakening evidence" do
    risers = Enum.map(1..6, &card("riser-#{&1}"))
    fallers = Enum.map(1..6, &card("faller-#{&1}"))

    Enum.each(risers, &snapshots(&1, [{8, "10"}, {0, "20"}]))
    Enum.each(fallers, &snapshots(&1, [{8, "20"}, {0, "10"}]))
    weak = card("weak-ten")
    short = card("short-ten")
    snapshots(weak, [{8, "10"}, {0, "10.40"}])
    snapshots(short, [{6, "10"}, {0, "20"}])

    old = card("old-epoch-ten")
    snapshots(old, [{8, "10"}, {0, "20"}], "old-policy")

    assert {:ok, changes} = Core.list_homepage_price_changes(@as_of, 10)
    assert length(changes) == 10
    assert Enum.count(changes, &(Decimal.compare(&1.change_percent, Decimal.new(0)) == :gt)) == 5
    assert Enum.count(changes, &(Decimal.compare(&1.change_percent, Decimal.new(0)) == :lt)) == 5
    refute Enum.any?(changes, &(&1.card_printing_id in [weak.id, short.id]))
    refute Enum.any?(changes, &(&1.card_printing_id == old.id))
  end

  test "price changes exclude snapshots from an old cardmarket mapping" do
    card = card("old-mapping")
    old_product_id = card.cardmarket_product_id

    snapshots(card, [{8, "10"}, {0, "20"}], "tcgdex_cardmarket_v1", old_product_id)

    Repo.query!(
      "UPDATE card_printings SET cardmarket_product_id = $2 WHERE id = $1",
      [Ecto.UUID.dump!(card.id), old_product_id + 1]
    )

    assert {:ok, []} = Core.list_homepage_price_changes(@as_of, 4)
  end

  test "price changes exclude unscoped and expired cards" do
    active = card("scoped-active")
    unscoped = card("scoped-unscoped", scoped?: false)
    expired = card("scoped-expired", expires_on: Date.add(Date.utc_today(), -1))

    Enum.each([active, unscoped, expired], &snapshots(&1, [{8, "10"}, {0, "20"}]))

    assert {:ok, [change]} = Core.list_homepage_price_changes(@as_of, 10)
    assert change.card_printing_id == active.id
  end

  test "recent releases are public, released, and bounded" do
    since = ~D[2026-07-01]
    older = released_product("older", ~D[2026-08-01])
    newest = released_product("newest", ~D[2026-08-10])
    middle = released_product("middle", ~D[2026-08-05])
    discontinued = released_product("discontinued", ~D[2026-08-04])
    _fifth = released_product("fifth", ~D[2026-08-02])

    _released_draft =
      Core.create_sealed_product_draft!(product_attrs("released-draft", ~D[2026-08-09]))

    _future = Core.create_sealed_product_draft!(product_attrs("future", ~D[2026-08-11]))
    _outside_window = released_product("outside-window", ~D[2026-06-30])
    archived = released_product("archived", ~D[2026-08-03])

    Core.archive_sealed_product!(archived, %{expected_updated_at: archived.updated_at},
      authorize?: false
    )

    assert {:ok, products} = Core.list_recent_public_sealed_products(since, ~D[2026-08-10])

    assert Enum.map(products, & &1.name) == [
             newest.name,
             middle.name,
             discontinued.name,
             "fifth",
             older.name
           ]

    assert Enum.all?(products, &(&1.publication_status == "approved"))
    assert {:ok, bounded} = Core.list_recent_public_sealed_products(since, ~D[2026-08-10])
    assert length(bounded) == 5
  end

  defp card(label, fixture_opts \\ []) do
    TcgCheap.TestSupport.import_card_printing!(
      %{
        tcgdex_id: "homepage-#{label}-#{System.unique_integer([:positive])}",
        name: "Homepage #{label}",
        set_name: "Homepage Set",
        collector_number: "#{System.unique_integer([:positive])}",
        mapping_status: "matched",
        cardmarket_product_id: System.unique_integer([:positive])
      },
      fixture_opts
    )
  end

  defp snapshots(card, points, policy \\ "tcgdex_cardmarket_v1", product_id \\ nil) do
    Enum.each(points, fn {days_ago, value} ->
      snapshot(
        card,
        value,
        DateTime.add(@as_of, -days_ago * 86_400, :second),
        if(policy == "other", do: "other-policy", else: policy),
        product_id || card.cardmarket_product_id
      )
    end)
  end

  defp snapshot(card, value, fetched_at, policy \\ "tcgdex_cardmarket_v1", product_id \\ nil) do
    Core.record_single_valuation!(%{
      card_printing_id: card.id,
      value_eur: Decimal.new(value),
      policy_version: policy,
      source: "tcgdex_cardmarket",
      source_metric: "avg7",
      fetched_at: fetched_at,
      cardmarket_product_id: product_id || card.cardmarket_product_id
    })
  end

  defp product_attrs(slug, date),
    do: %{
      slug: "homepage-#{slug}-#{System.unique_integer([:positive])}",
      name: slug,
      product_type: "tin",
      officially_distributed: true,
      release_date: date
    }

  defp released_product(slug, date) do
    draft = Core.create_sealed_product_draft!(product_attrs(slug, date))

    Core.approve_sealed_product!(draft, %{expected_updated_at: draft.updated_at},
      authorize?: false
    )
  end
end
