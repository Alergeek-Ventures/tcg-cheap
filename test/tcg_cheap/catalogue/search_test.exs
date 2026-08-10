defmodule TcgCheap.Catalogue.SearchTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Core

  defp unique_token(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp printing(token, overrides) do
    TcgCheap.TestSupport.import_card_printing!(
      Map.merge(
        %{
          tcgdex_id: unique_token("id-#{token}"),
          name: "Card #{token}",
          set_name: "Set #{token}",
          collector_number: "1-#{token}",
          standard_legal: false,
          mapping_status: "pending"
        },
        Map.new(overrides)
      )
    )
  end

  test "normalizes case, outer whitespace, and internal whitespace" do
    token = unique_token("normalization")
    card = printing(token, name: "Café #{token}", set_name: "Set #{token}")

    assert [result] = Core.search_card_printings!("  cAfÉ   #{token}  ")
    assert result.id == card.id
  end

  test "NFKC and Unicode whitespace normalization match persisted text and queries" do
    token = unique_token("unicode")
    full_width = printing(token, name: "Ｆｏｏ #{token}")
    decomposed = printing(token, name: "e\u0301 #{token}")
    nbsp = printing(token, name: "A\u00a0\u00a0B #{token}")
    dotted_i = printing(token, name: "İa #{token}")
    greek_sigma = printing(token, name: "ΣΟΣ #{token}")

    assert hd(Core.search_card_printings!("foo #{token}")).id == full_width.id
    assert hd(Core.search_card_printings!("é #{token}")).id == decomposed.id
    assert hd(Core.search_card_printings!("a b #{token}")).id == nbsp.id
    assert hd(Core.search_card_printings!("i\u0307a #{token}")).id == dotted_i.id
    assert hd(Core.search_card_printings!("σος #{token}")).id == greek_sigma.id

    persisted =
      Repo.all(
        from card in "card_printings",
          where:
            card.tcgdex_id in ^[
              full_width.tcgdex_id,
              decomposed.tcgdex_id,
              nbsp.tcgdex_id,
              dotted_i.tcgdex_id,
              greek_sigma.tcgdex_id
            ],
          select: card.search_name
      )

    assert MapSet.new([
             "foo #{token}",
             "é #{token}",
             "a b #{token}",
             "i\u0307a #{token}",
             "σος #{token}"
           ]) ==
             MapSet.new(persisted)
  end

  test "exact card name outranks a card-name prefix" do
    token = unique_token("name-rank")
    exact = printing(token, name: "Exact #{token}")
    printing(token, name: "Exact #{token} Extended")

    assert [first | _] = Core.search_card_printings!("exact #{token}")
    assert first.id == exact.id
  end

  test "exact TCGdex ID, collector number, and set name each rank first" do
    token = unique_token("exact-rank")
    by_id = printing(token, tcgdex_id: "target-id-#{token}")
    by_collector = printing(token, collector_number: "target-collector-#{token}")
    by_set = printing(token, set_name: "Target Set #{token}")

    assert hd(Core.search_card_printings!(by_id.tcgdex_id)).id == by_id.id
    assert hd(Core.search_card_printings!(by_collector.collector_number)).id == by_collector.id
    assert hd(Core.search_card_printings!(by_set.set_name)).id == by_set.id
  end

  test "typos use local trigram matching" do
    token = unique_token("typo")
    card = printing(token, name: "Charizard #{token}")

    assert card.id in Enum.map(Core.search_card_printings!("charizrd #{token}"), & &1.id)
  end

  test "same-name printings remain separate and use stable tie-break ordering" do
    token = unique_token("collision")
    stable_suffix = unique_token("id")

    first =
      printing(token,
        name: "Foo",
        set_name: "Same",
        collector_number: "1",
        tcgdex_id: "x-b-#{stable_suffix}"
      )

    second =
      printing(token,
        name: "Foo",
        set_name: "Same",
        collector_number: "1",
        tcgdex_id: "x-c-#{stable_suffix}"
      )

    third =
      printing(token,
        name: "Foo",
        set_name: "Same",
        collector_number: "1",
        tcgdex_id: "x-a-#{stable_suffix}"
      )

    results = Core.search_card_printings!("foo")
    ids = Enum.map(results, & &1.id)

    assert Enum.sort([first.id, second.id, third.id]) -- ids == []
    collision_results = Enum.filter(results, &(&1.id in [first.id, second.id, third.id]))

    assert Enum.map(collision_results, & &1.tcgdex_id) == [
             "x-a-#{stable_suffix}",
             "x-b-#{stable_suffix}",
             "x-c-#{stable_suffix}"
           ]
  end

  test "cross-field exact and prefix ranking follows the documented matrix" do
    query = unique_token("matrix")
    neutral = fn suffix -> "neutral-#{suffix}-#{unique_token("field")}" end

    exact_id =
      printing(query,
        tcgdex_id: query,
        name: neutral.(:id),
        set_name: neutral.(:id_set),
        collector_number: neutral.(:id_collector)
      )

    exact_name =
      printing(query,
        name: query,
        set_name: neutral.(:name_set),
        collector_number: neutral.(:name_collector)
      )

    exact_collector =
      printing(query,
        collector_number: query,
        name: neutral.(:collector_name),
        set_name: neutral.(:collector_set)
      )

    exact_set =
      printing(query,
        set_name: query,
        name: neutral.(:set_name),
        collector_number: neutral.(:set_collector)
      )

    name_prefix =
      printing(query,
        name: "#{query}-name-prefix",
        set_name: neutral.(:name_prefix_set),
        collector_number: neutral.(:name_prefix_collector)
      )

    collector_prefix =
      printing(query,
        collector_number: "#{query}-collector-prefix",
        name: neutral.(:collector_prefix_name),
        set_name: neutral.(:collector_prefix_set)
      )

    set_prefix =
      printing(query,
        set_name: "#{query}-set-prefix",
        name: neutral.(:set_prefix_name),
        collector_number: neutral.(:set_prefix_collector)
      )

    id_prefix =
      printing(query,
        tcgdex_id: "#{query}-id-prefix",
        name: neutral.(:id_prefix_name),
        set_name: neutral.(:id_prefix_set),
        collector_number: neutral.(:id_prefix_collector)
      )

    expected = [
      exact_id,
      exact_name,
      exact_collector,
      exact_set,
      name_prefix,
      collector_prefix,
      set_prefix,
      id_prefix
    ]

    assert Enum.take(Core.search_card_printings!(query), 8) |> Enum.map(& &1.id) ==
             Enum.map(expected, & &1.id)
  end

  test "standard legality only breaks otherwise equivalent relevance" do
    token = unique_token("legality")

    old =
      printing(token,
        tcgdex_id: "legality-printing-#{token}-a",
        name: "Legal #{token}",
        set_name: "Legal Set #{token}",
        collector_number: "1",
        standard_legal: false
      )

    current =
      printing(token,
        tcgdex_id: "legality-printing-#{token}-b",
        name: "Legal #{token}",
        set_name: "Legal Set #{token}",
        collector_number: "1",
        standard_legal: true
      )

    assert [first, second] = Core.search_card_printings!("legal #{token}")
    assert first.id == current.id
    assert second.id == old.id
  end

  test "all mapping statuses remain searchable" do
    token = unique_token("mapping")
    pending = printing(token, name: "Pending #{token}", mapping_status: "pending")
    unmatched = printing(token, name: "Unmatched #{token}", mapping_status: "unmatched")

    review =
      printing(token,
        name: "Review #{token}",
        mapping_status: "review",
        mapping_review_reason: "manual"
      )

    matched =
      printing(token,
        name: "Matched #{token}",
        mapping_status: "matched",
        cardmarket_product_id: 123
      )

    ids = Enum.map(Core.search_card_printings!(token), & &1.id)
    assert Enum.all?([pending, unmatched, review, matched], &(&1.id in ids))
  end

  test "default limit is 10 and custom limits are applied" do
    token = unique_token("limit")
    for index <- 1..12, do: printing(token, name: "Limit #{token} #{index}")

    assert length(Core.search_card_printings!(token)) == 10
    assert length(Core.search_card_printings!(token, 3)) == 3
  end

  test "rejects invalid limits and normalized query lengths" do
    assert {:error, _} = Core.search_card_printings(" ")
    assert {:error, _} = Core.search_card_printings("a")
    assert {:error, _} = Core.search_card_printings("a   ")
    assert {:error, _} = Core.search_card_printings(String.duplicate("x", 101))
    assert {:error, _} = Core.search_card_printings("valid", 0)
    assert {:error, _} = Core.search_card_printings("valid", 21)
  end

  test "LIKE wildcards and backslashes are literal input" do
    token = unique_token("wildcards")

    percent =
      printing(token, name: "literal-%x", set_name: "neutral", collector_number: "neutral-p")

    percent_distractor =
      printing(token, name: "far-away-Yx", set_name: "neutral", collector_number: "neutral-pd")

    underscore =
      printing(token, name: "literal-_u", set_name: "neutral", collector_number: "neutral-u")

    underscore_distractor =
      printing(token, name: "far-away-Yu", set_name: "neutral", collector_number: "neutral-ud")

    slash =
      printing(token, name: "literal-\\s", set_name: "neutral", collector_number: "neutral-s")

    slash_distractor =
      printing(token, name: "far-away-s", set_name: "neutral", collector_number: "neutral-sd")

    assert [result] = Core.search_card_printings!("%x")
    assert result.id == percent.id
    refute percent_distractor.id in Enum.map(Core.search_card_printings!("%x"), & &1.id)
    assert [result] = Core.search_card_printings!("_u")
    assert result.id == underscore.id
    refute underscore_distractor.id in Enum.map(Core.search_card_printings!("_u"), & &1.id)
    assert [result] = Core.search_card_printings!("\\s")
    assert result.id == slash.id
    refute slash_distractor.id in Enum.map(Core.search_card_printings!("\\s"), & &1.id)
  end

  test "search is local-only and preloads card_set" do
    token = unique_token("local")
    set = Core.import_card_set!(%{tcgdex_id: unique_token("set"), name: "Local Set #{token}"})
    card = printing(token, name: "Local #{token}", set_name: set.name, card_set_id: set.id)

    assert [result] = Core.search_card_printings!("local #{token}")
    assert result.id == card.id
    assert result.card_set.id == set.id
  end

  test "search preloads the active Cardmarket valuation and leaves missing valuations nil" do
    token = unique_token("valuation")

    valued =
      printing(token,
        name: "Valued #{token}",
        mapping_status: "matched",
        cardmarket_product_id: System.unique_integer([:positive])
      )

    missing = printing(token, name: "Unvalued #{token}")

    valuation =
      Core.record_single_valuation!(%{
        card_printing_id: valued.id,
        value_eur: Decimal.new("12.34"),
        currency: "EUR",
        policy_version: "tcgdex_cardmarket_v1",
        source: "tcgdex",
        source_metric: "cardmarket_average_sell_price",
        fetched_at: DateTime.utc_now(),
        cardmarket_product_id: valued.cardmarket_product_id
      })

    results = Core.search_card_printings!(token)
    valued_result = Enum.find(results, &(&1.id == valued.id))
    missing_result = Enum.find(results, &(&1.id == missing.id))

    assert valued_result
    assert valued_result.tcgdex_cardmarket_v1_current_valuation.id == valuation.id
    assert valued_result.tcgdex_cardmarket_v1_current_valuation.value_eur == Decimal.new("12.34")
    assert missing_result
    assert missing_result.tcgdex_cardmarket_v1_current_valuation == nil
  end

  test "search does not preload a current valuation from another Cardmarket product" do
    token = unique_token("stale-valuation")

    card =
      printing(token,
        name: "Stale #{token}",
        mapping_status: "matched",
        cardmarket_product_id: 101
      )

    Core.record_single_valuation!(%{
      card_printing_id: card.id,
      value_eur: Decimal.new("9.99"),
      currency: "EUR",
      policy_version: "tcgdex_cardmarket_v1",
      source: "tcgdex",
      source_metric: "cardmarket_average_sell_price",
      fetched_at: DateTime.utc_now(),
      cardmarket_product_id: card.cardmarket_product_id
    })

    Repo.query!(
      "UPDATE single_valuation_snapshots SET cardmarket_product_id = $1 WHERE card_printing_id = $2",
      [202, Ecto.UUID.dump!(card.id)]
    )

    assert [result] = Core.search_card_printings!("stale #{token}")
    assert result.tcgdex_cardmarket_v1_current_valuation == nil
  end

  test "persisted search text is normalized and refreshed by both upsert actions" do
    token = unique_token("persisted")
    tcgdex_id = unique_token("persisted-id")

    TcgCheap.TestSupport.import_card_printing!(%{
      tcgdex_id: tcgdex_id,
      name: "  Initial   Name  ",
      set_name: "Initial Set",
      collector_number: "A_1"
    })

    TcgCheap.TestSupport.import_card_printing!(%{
      tcgdex_id: tcgdex_id,
      name: "Updated #{token}",
      set_name: "Updated Set #{token}",
      collector_number: "B_2"
    })

    assert [updated] = Core.search_card_printings!("updated #{token}")
    assert updated.tcgdex_id == tcgdex_id

    Core.seed_card_printing_brief!(%{
      tcgdex_id: tcgdex_id,
      name: "Brief #{token}",
      set_name: "Brief Set #{token}",
      collector_number: "C_3",
      card_set_id: nil
    })

    assert [brief] = Core.search_card_printings!("brief #{token}")
    assert brief.tcgdex_id == tcgdex_id

    assert {"brief #{token}", "brief set #{token}", "c_3", tcgdex_id} ==
             Repo.one(
               from card in "card_printings",
                 where: card.tcgdex_id == ^tcgdex_id,
                 select:
                   {card.search_name, card.search_set_name, card.search_collector_number,
                    card.search_tcgdex_id}
             )
  end
end
