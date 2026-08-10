defmodule TcgCheap.Catalogue.EnrichmentTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.{Catalogue.Enrichment, Core, Operations, Repo}

  defmodule Provider do
    def fetch_set(id, opts) do
      record(opts, {:set, id})
      Process.sleep(Keyword.get(opts, :set_delay, 0))
      Keyword.fetch!(opts, :sets) |> Map.fetch(id) |> reply()
    end

    def fetch_card(id, opts) do
      record(opts, {:card, id})
      enter(opts)
      Process.sleep(Keyword.get(opts, :delay, 0))
      result = Keyword.fetch!(opts, :cards) |> Map.fetch(id) |> reply()
      leave(opts)
      result
    end

    defp reply({:ok, {:error, reason}}), do: {:error, reason}
    defp reply({:ok, value}), do: {:ok, value}
    defp reply(value), do: {:ok, value}

    defp record(opts, event), do: Agent.update(Keyword.fetch!(opts, :state), &[event | &1])

    defp enter(opts) do
      Agent.get_and_update(Keyword.fetch!(opts, :state), fn events ->
        active = Keyword.get(events, :active, 0) + 1
        max = max(active, Keyword.get(events, :max, 0))
        {active, [active: active, max: max] ++ Keyword.drop(events, [:active, :max])}
      end)
    end

    defp leave(opts),
      do:
        Agent.update(Keyword.fetch!(opts, :state), fn events ->
          [active: max(0, Keyword.get(events, :active, 1) - 1)] ++
            Keyword.drop(events, [:active])
        end)
  end

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    Repo.delete_all("card_printings")
    Repo.delete_all("card_sets")
    Repo.delete_all("import_issues")
    {:ok, state} = Agent.start_link(fn -> [] end)
    %{state: state}
  end

  defp id(label), do: "enrich-#{label}-#{System.unique_integer([:positive])}"

  defp set(id, cards, opts \\ []) do
    %{
      "id" => id,
      "name" => Keyword.get(opts, :name, "Enrichment Set"),
      "cards" => Enum.map(cards, &%{"id" => &1}),
      "cardCount" => %{"total" => length(cards)},
      "serie" => Keyword.get(opts, :serie, %{"id" => "sv"})
    }
  end

  defp card(id, set_id, opts \\ []) do
    %{
      "id" => Keyword.get(opts, :returned_id, id),
      "name" => Keyword.get(opts, :name, "Card"),
      "localId" => Keyword.get(opts, :local_id, "1"),
      "set" => %{"id" => Keyword.get(opts, :returned_set_id, set_id)},
      "pricing" => Keyword.get(opts, :pricing, %{})
    }
    |> Map.merge(Keyword.get(opts, :extra, %{}))
  end

  defp opts(state, set_id, cards, extra \\ []) do
    [
      provider: Provider,
      provider_options: [
        state: state,
        sets: %{
          set_id =>
            Keyword.get(extra, :set, set(set_id, Keyword.get(extra, :brief_ids, Map.keys(cards))))
        },
        cards: cards,
        delay: Keyword.get(extra, :delay, 0),
        set_delay: Keyword.get(extra, :set_delay, 0)
      ],
      clock: Keyword.get(extra, :clock, fn -> ~U[2026-01-01 00:00:00Z] end)
    ] ++ Keyword.take(extra, [:max_concurrency, :fetch_timeout])
  end

  defp events(state), do: Agent.get(state, & &1)

  test "fetches one set and one detail per card and reports mapping outcomes", %{state: state} do
    set_id = id("set")
    ids = Enum.map(~w(matched unmatched review), &id/1)

    cards = %{
      Enum.at(ids, 0) =>
        card(Enum.at(ids, 0), set_id, pricing: %{"cardmarket" => %{"idProduct" => 10}}),
      Enum.at(ids, 1) => card(Enum.at(ids, 1), set_id),
      Enum.at(ids, 2) =>
        card(Enum.at(ids, 2), set_id,
          extra: %{"variants_detailed" => [%{"subtype" => "shadowless"}]}
        )
    }

    assert {:ok, report} =
             Enrichment.enrich_set(set_id, opts(state, set_id, cards, brief_ids: ids))

    assert report.cards_seen == 3
    assert report.cards_enriched == 3
    assert report.cards_failed == 0
    assert report.cards_preserved == 0
    assert Enum.count(events(state), &match?({:set, ^set_id}, &1)) == 1
    assert Enum.count(events(state), &match?({:card, _}, &1)) == 3
    assert {:ok, matched} = Core.get_card_printing_by_tcgdex_id(Enum.at(ids, 0))
    assert matched.mapping_status == "matched"
    assert {:ok, unmatched} = Core.get_card_printing_by_tcgdex_id(Enum.at(ids, 1))
    assert unmatched.mapping_status == "unmatched"
    assert {:ok, review} = Core.get_card_printing_by_tcgdex_id(Enum.at(ids, 2))
    assert review.mapping_status == "review"
    assert {:ok, issues} = Operations.list_admin_import_issues(authorize?: false)

    assert Enum.sort(Enum.map(issues, &{&1.target_key, &1.issue_kind, &1.issue_code})) ==
             Enum.sort([
               {Enum.at(ids, 1), "unmatched", "provider_response"},
               {Enum.at(ids, 2), "ambiguous", "provider_response"}
             ])
  end

  test "rejects malformed, truncated, and duplicate card lists before detail calls or writes", %{
    state: state
  } do
    for mutation <- [:missing, :truncated, :duplicate] do
      set_id = id(to_string(mutation))
      cards = [id("one"), id("two")]
      payload = set(set_id, cards)

      payload =
        case mutation do
          :missing -> Map.delete(payload, "cardCount")
          :truncated -> Map.put(payload, "cardCount", %{"total" => 3})
          :duplicate -> Map.put(payload, "cards", [%{"id" => hd(cards)}, %{"id" => hd(cards)}])
        end

      assert {:error, {:malformed_response, _}} =
               Enrichment.enrich_set(set_id, opts(state, set_id, %{}, set: payload))

      refute Enum.any?(events(state), &match?({:card, _}, &1))
      assert Repo.aggregate(from(c in "card_printings"), :count, :id) == 0
    end
  end

  test "excludes Pocket before card fetch, clock, or writes", %{state: state} do
    set_id = id("pocket")
    payload = set(set_id, [id("card")], serie: %{"id" => "tcgp"})
    clock = fn -> flunk("clock must not be called") end

    assert {:ok, %{status: :excluded, reason: :tcg_pocket, cards_preserved: 0}} =
             Enrichment.enrich_set(set_id, opts(state, set_id, %{}, set: payload, clock: clock))

    refute Enum.any?(events(state), &match?({:card, _}, &1))
    assert Repo.aggregate(from(s in "card_sets"), :count, :id) == 0
  end

  test "isolates fetch and import failures in original card order", %{state: state} do
    set_id = id("failures")
    ids = Enum.map(1..4, &id("card-#{&1}"))

    cards = %{
      Enum.at(ids, 0) => card(Enum.at(ids, 0), set_id),
      Enum.at(ids, 1) => {:error, :offline},
      Enum.at(ids, 2) => card(Enum.at(ids, 2), set_id, returned_id: id("wrong")),
      Enum.at(ids, 3) => card(Enum.at(ids, 3), set_id)
    }

    assert {:ok, report} =
             Enrichment.enrich_set(set_id, opts(state, set_id, cards, brief_ids: ids))

    assert report.cards_enriched == 2
    assert report.cards_preserved == 0
    assert Enum.map(report.failures, & &1.card_id) == [Enum.at(ids, 1), Enum.at(ids, 2)]
    assert Enum.at(report.failures, 0).stage == :fetch
    assert Enum.at(report.failures, 1).stage == :import
    assert {:ok, _} = Core.get_card_printing_by_tcgdex_id(Enum.at(ids, 3))

    assert {:ok, issues} = Operations.list_admin_import_issues(authorize?: false)

    assert Enum.sort(Enum.map(issues, &{&1.target_key, &1.stage, &1.issue_code})) ==
             Enum.sort([
               {Enum.at(ids, 1), "card_fetch", "unknown"},
               {Enum.at(ids, 0), "card_import", "provider_response"},
               {Enum.at(ids, 2), "card_import", "malformed_response"},
               {Enum.at(ids, 3), "card_import", "provider_response"}
             ])
  end

  test "rejects returned set mismatch as an isolated import failure", %{state: state} do
    set_id = id("set-mismatch")
    card_id = id("card")
    cards = %{card_id => card(card_id, set_id, returned_set_id: id("wrong-set"))}
    assert {:ok, report} = Enrichment.enrich_set(set_id, opts(state, set_id, cards))
    assert [%{card_id: ^card_id, stage: :import}] = report.failures
    assert {:error, _} = Core.get_card_printing_by_tcgdex_id(card_id)
  end

  test "calls clock once and shares normalized timestamp", %{state: state} do
    set_id = id("clock")
    ids = [id("one"), id("two")]
    counter = :counters.new(1, [:atomics])

    clock = fn ->
      :counters.add(counter, 1, 1)
      ~U[2026-01-01 01:02:03.123456789Z]
    end

    cards = Map.new(ids, &{&1, card(&1, set_id)})

    assert {:ok, %{cards_enriched: 2}} =
             Enrichment.enrich_set(set_id, opts(state, set_id, cards, clock: clock))

    assert :counters.get(counter, 1) == 1
    assert {:ok, first} = Core.get_card_printing_by_tcgdex_id(hd(ids))
    assert {:ok, second} = Core.get_card_printing_by_tcgdex_id(List.last(ids))
    assert first.last_synced_at == second.last_synced_at
    assert first.last_synced_at == ~U[2026-01-01 01:02:03.123456Z]
  end

  test "invalid clock writes nothing", %{state: state} do
    set_id = id("bad-clock")
    card_id = id("card")
    cards = %{card_id => card(card_id, set_id)}

    for clock <- [fn -> :bad end, fn -> raise "boom" end] do
      assert {:error, :invalid_clock} =
               Enrichment.enrich_set(set_id, opts(state, set_id, cards, clock: clock))

      assert Repo.aggregate(from(s in "card_sets"), :count, :id) == 0
    end

    assert {:ok, [issue]} = Operations.list_admin_import_issues(authorize?: false)
    assert issue.stage == "set_import"
    assert issue.issue_code == "local_input"
  end

  test "bounds detail fetch concurrency", %{state: state} do
    set_id = id("bounded")
    ids = Enum.map(1..8, &id("card-#{&1}"))
    cards = Map.new(ids, &{&1, card(&1, set_id)})

    assert {:ok, report} =
             Enrichment.enrich_set(
               set_id,
               opts(state, set_id, cards, delay: 10, max_concurrency: 2)
             )

    assert report.cards_enriched == 8
    assert Keyword.get(events(state), :max, 0) == 2
  end

  test "rerun is idempotent and stale detailed payload does not overwrite newer data", %{
    state: state
  } do
    set_id = id("stale")
    card_id = id("card")
    newer = card(card_id, set_id, name: "New", extra: %{"updated" => "2026-02-01T00:00:00Z"})
    older = card(card_id, set_id, name: "Old", extra: %{"updated" => "2026-01-01T00:00:00Z"})
    Agent.update(state, fn _ -> [] end)
    assert {:ok, _} = Enrichment.enrich_set(set_id, opts(state, set_id, %{card_id => newer}))
    assert {:ok, first} = Core.get_card_printing_by_tcgdex_id(card_id)

    assert {:ok, second_report} =
             Enrichment.enrich_set(set_id, opts(state, set_id, %{card_id => older}))

    assert {:ok, second} = Core.get_card_printing_by_tcgdex_id(card_id)
    assert second.id == first.id
    assert second.name == "New"
    assert second_report.cards_enriched == 0
    assert second_report.cards_preserved == 1
    assert Repo.aggregate(from(c in "card_printings"), :count, :id) == 1
  end

  test "reports stale-preserved cards separately", %{state: state} do
    set_id = id("preserved")
    card_id = id("card")
    newer = card(card_id, set_id, name: "New", extra: %{"updated" => "2026-02-01T00:00:00Z"})
    older = card(card_id, set_id, name: "Old", extra: %{"updated" => "2026-01-01T00:00:00Z"})
    assert {:ok, first} = Enrichment.enrich_set(set_id, opts(state, set_id, %{card_id => newer}))
    assert first.cards_enriched == 1 and first.cards_preserved == 0
    assert {:ok, second} = Enrichment.enrich_set(set_id, opts(state, set_id, %{card_id => older}))
    assert second.cards_enriched == 0 and second.cards_preserved == 1 and second.cards_failed == 0
  end

  test "times out a hanging set provider call", %{state: state} do
    set_id = id("set-timeout")

    assert {:error, {:provider_timeout, :fetch_set}} =
             Enrichment.enrich_set(
               set_id,
               opts(state, set_id, %{}, set_delay: 50, fetch_timeout: 1)
             )
  end

  test "normalizes malformed provider callbacks and caps set fan-out", %{state: state} do
    set_id = id("too-many")
    ids = Enum.map(1..1_001, &id("card-#{&1}"))
    oversized = set(set_id, ids)

    assert {:error, {:malformed_response, {:set, :too_many_cards}}} =
             Enrichment.enrich_set(set_id, opts(state, set_id, %{}, set: oversized))

    refute Enum.any?(events(state), &match?({:card, _}, &1))

    bad_state = Agent.start_link(fn -> [] end) |> elem(1)

    assert {:error, {:provider_callback_error, :fetch_set, {:unexpected_return, :bad}}} =
             Enrichment.enrich_set(set_id,
               provider: __MODULE__.MalformedSetProvider,
               provider_options: [state: bad_state]
             )

    assert {:ok, issues} = Operations.list_admin_import_issues(authorize?: false)

    assert Enum.any?(
             issues,
             &(&1.stage == "set_fetch" and &1.issue_code == "provider_response")
           )
  end

  test "reports malformed card callback as a fetch failure", _context do
    set_id = id("bad-card-callback")
    card_id = id("card")

    assert {:ok, report} =
             Enrichment.enrich_set(set_id,
               provider: __MODULE__.MalformedCardProvider,
               provider_options: [set: set(set_id, [card_id])],
               clock: fn -> ~U[2026-01-01 00:00:00Z] end
             )

    assert [
             %{
               card_id: ^card_id,
               stage: :fetch,
               reason: {:provider_callback_error, :fetch_card, _}
             }
           ] = report.failures
  end

  test "rejects whitespace-mutated set identity before card fan-out", %{state: state} do
    set_id = id("exact-set")
    card_id = id("card")
    mutated_id = " " <> set_id
    payload = set(set_id, [card_id]) |> Map.put("id", mutated_id)

    assert {:error, {:malformed_response, {:set_id_mismatch, ^set_id, ^mutated_id}}} =
             Enrichment.enrich_set(
               set_id,
               opts(state, set_id, %{card_id => card(card_id, set_id)}, set: payload)
             )

    refute Enum.any?(events(state), &match?({:card, _}, &1))
  end

  defmodule MalformedSetProvider do
    def fetch_set(_, _), do: :bad
    def fetch_card(_, _), do: {:ok, %{}}
  end

  defmodule MalformedCardProvider do
    def fetch_set(_, opts), do: {:ok, opts[:set]}
    def fetch_card(_, _), do: :not_a_callback_result
  end

  defmodule CallbackCardProvider do
    def fetch_set(_, opts), do: {:ok, opts[:set]}

    def fetch_card("timeout", opts) do
      Process.sleep(Keyword.get(opts, :delay, 1_000))
      {:ok, %{}}
    end

    def fetch_card("raise", _), do: raise("detail boom")
    def fetch_card("throw", _), do: throw(:detail_throw)
    def fetch_card("exit", _), do: exit(:detail_exit)
    def fetch_card(id, opts), do: {:ok, Keyword.fetch!(opts, :cards) |> Map.fetch!(id)}
  end

  test "times out and isolates raised, thrown, and exited detail callbacks in order", %{
    state: state
  } do
    set_id = id("detail-failures")
    ids = ["timeout", "raise", "throw", "exit", id("healthy")]
    healthy = List.last(ids)
    payload = set(set_id, ids)
    cards = %{healthy => card(healthy, set_id)}

    assert {:ok, report} =
             Enrichment.enrich_set(set_id,
               provider: __MODULE__.CallbackCardProvider,
               provider_options: [state: state, set: payload, cards: cards, delay: 1_000],
               fetch_timeout: 500,
               max_concurrency: 1,
               clock: fn -> ~U[2026-01-01 00:00:00Z] end
             )

    assert report.cards_enriched == 1
    assert Enum.map(report.failures, & &1.card_id) == Enum.take(ids, 4)
    assert Enum.all?(report.failures, &(&1.stage == :fetch))
    assert {:ok, _} = Core.get_card_printing_by_tcgdex_id(healthy)

    assert {:ok, issues} = Operations.list_admin_import_issues(authorize?: false)
    fetch_issues = Enum.filter(issues, &(&1.stage == "card_fetch"))
    assert length(fetch_issues) == 4
    assert Enum.count(fetch_issues, &(&1.issue_code == "provider_response")) == 3
  end

  test "rejects invalid options, providers, provider options, and bounds", %{state: state} do
    set_id = id("options")
    cards = %{}
    base = opts(state, set_id, cards)

    assert {:error, :invalid_options} =
             Enrichment.enrich_set(set_id, Keyword.put(base, :unknown, true))

    assert {:error, :invalid_options} =
             Enrichment.enrich_set(set_id, base ++ [provider: Provider])

    assert {:error, :invalid_provider_options} =
             Enrichment.enrich_set(set_id, Keyword.put(base, :provider_options, [:bad]))

    assert {:error, :invalid_provider_options} =
             Enrichment.enrich_set(
               set_id,
               Keyword.put(base, :provider_options, state: state, state: state)
             )

    assert {:error, :invalid_provider} =
             Enrichment.enrich_set(set_id, Keyword.put(base, :provider, __MODULE__))

    assert {:error, :invalid_max_concurrency} =
             Enrichment.enrich_set(set_id, Keyword.put(base, :max_concurrency, 17))

    assert {:error, :invalid_fetch_timeout} =
             Enrichment.enrich_set(set_id, Keyword.put(base, :fetch_timeout, 120_001))
  end
end
