defmodule TcgCheap.Catalogue.SyncTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.Catalogue.{Importer, Sync}
  alias TcgCheap.{Core, Operations, Repo}

  defmodule Provider do
    def fetch_set(id, opts) do
      case Keyword.get(opts, :sets, %{}) do
        %{^id => {:error, reason}} -> {:error, reason}
        %{^id => set} -> {:ok, set}
        _ -> {:error, :missing_set}
      end
    end

    def list_sets(opts) do
      case Keyword.get(opts, :list_result, :sets) do
        :sets -> {:ok, Keyword.get(opts, :set_briefs, [])}
        result -> result
      end
    end

    def fetch_card(id, opts) do
      case Keyword.get(opts, :cards, %{}) do
        %{^id => card} -> {:ok, card}
        _ -> {:error, :missing_card}
      end
    end
  end

  defmodule CallbackProvider do
    def list_sets(opts), do: callback(Keyword.fetch!(opts, :list_result))

    def fetch_set(id, opts) do
      opts
      |> Keyword.fetch!(:sets)
      |> Map.fetch!(id)
      |> callback()
    end

    defp callback({:ok, value}), do: {:ok, value}
    defp callback({:error, reason}), do: {:error, reason}
    defp callback({:return, value}), do: value
    defp callback({:raise, message}), do: raise(message)
    defp callback({:throw, reason}), do: throw(reason)
    defp callback({:exit, reason}), do: exit(reason)
    defp callback(value), do: {:ok, value}
  end

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    Repo.delete_all("card_printings")
    Repo.delete_all("card_sets")
    Repo.delete_all("import_issues")
    :ok
  end

  defp id(label), do: "sync-#{label}-#{System.unique_integer([:positive])}"

  defp clock(counter, value),
    do: fn ->
      :counters.add(counter, 1, 1)
      value
    end

  defp set(id, cards, name \\ "Sync Set") do
    %{
      "id" => id,
      "name" => name,
      "cards" => cards,
      "releaseDate" => "2026-01-02",
      "logo" => "https://assets.example/logo",
      "symbol" => "https://assets.example/symbol",
      "cardCount" => %{"official" => length(cards), "total" => length(cards)},
      "legal" => %{"standard" => true, "expanded" => false}
    }
  end

  defp card(id, local_id, name \\ "Brief Card") do
    %{"id" => id, "name" => name, "localId" => local_id, "image" => "https://assets.example/card"}
  end

  defp opts(sets, clock), do: [provider: Provider, provider_options: [sets: sets], clock: clock]

  test "syncs complete set briefs atomically and never fetches card details" do
    set_id = id("set")
    card_id = id("card")
    counter = :counters.new(1, [:atomics])
    set = set(set_id, [card(card_id, 7)])

    assert {:ok, result} =
             Sync.sync_set(
               " " <> set_id <> " ",
               opts(%{set_id => set}, clock(counter, ~U[2026-01-01 00:00:00Z]))
             )

    assert result == %{set_id: set_id, cards_seen: 1, cards_seeded: 1, cards_preserved: 0}
    assert :counters.get(counter, 1) == 1
    assert {:ok, stored_set} = Core.get_card_set_by_tcgdex_id(set_id)
    assert stored_set.name == "Sync Set"
    assert stored_set.logo_url == "https://assets.example/logo.webp"
    assert {:ok, stored_card} = Core.get_card_printing_by_tcgdex_id(card_id)
    assert stored_card.collector_number == "7"
    assert stored_card.image_url == "https://assets.example/card/high.webp"
    assert stored_card.mapping_status == "pending"
  end

  test "validates every card before writing the set" do
    set_id = id("malformed")

    cards = [
      card(id("good"), "1"),
      %{"id" => id("bad"), "name" => "Bad", "localId" => "2", "image" => 12}
    ]

    assert {:error, {:malformed_response, {:card, :invalid_image}}} =
             Sync.sync_set(
               set_id,
               opts(%{set_id => set(set_id, cards)}, fn -> ~U[2026-01-01 00:00:00Z] end)
             )

    assert {:error, _} = Core.get_card_set_by_tcgdex_id(set_id)

    assert Repo.aggregate(
             from(c in "card_printings", where: c.tcgdex_id == ^hd(tl(cards))["id"]),
             :count,
             :id
           ) == 0

    duplicate_id = id("duplicate")
    duplicate_set_id = id("duplicate-set")
    duplicate_cards = [card(duplicate_id, "1"), card(duplicate_id, "2")]

    assert {:error, {:malformed_response, {:duplicate_card_id, ^duplicate_id}}} =
             Sync.sync_set(
               duplicate_set_id,
               opts(%{duplicate_set_id => set(duplicate_set_id, duplicate_cards)}, fn ->
                 ~U[2026-01-01 00:00:00Z]
               end)
             )

    assert {:error, _} = Core.get_card_set_by_tcgdex_id(duplicate_set_id)
  end

  test "excludes TCG Pocket sets without invoking the clock or writing" do
    set_id = id("A1")
    counter = :counters.new(1, [:atomics])

    pocket =
      set(set_id, [card(id("pocket-card"), "1")])
      |> Map.put("serie", %{"id" => "tcgp", "name" => "Pokémon TCG Pocket"})

    assert {:ok, %{status: :excluded, set_id: ^set_id}} =
             Sync.sync_set(
               set_id,
               opts(%{set_id => pocket}, clock(counter, ~U[2026-01-01 00:00:00Z]))
             )

    assert :counters.get(counter, 1) == 0
    assert {:error, _} = Core.get_card_set_by_tcgdex_id(set_id)

    briefs = [%{"id" => set_id, "name" => "A1"}]

    assert {:ok, report} =
             Sync.sync_all_sets(
               provider: Provider,
               provider_options: [sets: %{set_id => pocket}, set_briefs: briefs],
               clock: fn -> raise "must not run" end
             )

    assert report.excluded_sets == 1
    assert report.synced_sets == 0
    assert report.failed_sets == 0
    assert report.exclusions == [%{set_id: set_id, reason: :tcg_pocket}]
    assert {:ok, []} = Operations.list_admin_import_issues(authorize?: false)
  end

  test "does not classify a mismatched Pocket payload as excluded" do
    requested_id = id("pocket-request")

    payload =
      set(id("different-pocket"), [], "Pocket Set")
      |> Map.put("serie", %{"id" => "tcgp", "name" => "Pokémon TCG Pocket"})

    assert {:error, {:malformed_response, {:set_id_mismatch, ^requested_id, _}}} =
             Sync.sync_set(
               requested_id,
               opts(%{requested_id => payload}, fn -> raise "must not run" end)
             )

    assert {:error, _} = Core.get_card_set_by_tcgdex_id(requested_id)
  end

  test "rejects missing, truncated, and invalid detailed card totals before writes" do
    set_id = id("count")

    cases = [
      Map.delete(set(set_id, []), "cardCount"),
      Map.put(set(set_id, [card(id("partial"), "1")]), "cardCount", %{"total" => 2}),
      Map.put(set(set_id, []), "cardCount", %{"total" => -1})
    ]

    for candidate <- cases do
      assert {:error, {:malformed_response, {:set, _}}} =
               Sync.sync_set(
                 set_id,
                 opts(%{set_id => candidate}, fn -> ~U[2026-01-01 00:00:00Z] end)
               )

      assert {:error, _} = Core.get_card_set_by_tcgdex_id(set_id)
    end

    empty_id = id("empty")

    assert {:ok, result} =
             Sync.sync_set(
               empty_id,
               opts(%{empty_id => set(empty_id, [])}, fn -> ~U[2026-01-01 00:00:00Z] end)
             )

    assert result.cards_seen == 0
  end

  test "reruns preserve IDs and refresh pending briefs" do
    set_id = id("rerun")
    card_id = id("card")
    first = set(set_id, [card(card_id, "1", "Old")])
    second = set(set_id, [card(card_id, 2, "New")])
    clock = fn -> ~U[2026-01-01 00:00:00Z] end

    assert {:ok, first_result} = Sync.sync_set(set_id, opts(%{set_id => first}, clock))
    assert first_result.cards_seeded == 1 and first_result.cards_preserved == 0
    assert {:ok, old_card} = Core.get_card_printing_by_tcgdex_id(card_id)
    assert {:ok, second_result} = Sync.sync_set(set_id, opts(%{set_id => second}, clock))
    assert second_result.cards_seeded == 1 and second_result.cards_preserved == 0
    assert {:ok, new_card} = Core.get_card_printing_by_tcgdex_id(card_id)
    assert new_card.id == old_card.id
    assert new_card.name == "New"
    assert new_card.collector_number == "2"

    assert Repo.aggregate(
             from(c in "card_printings", where: c.tcgdex_id == ^card_id),
             :count,
             :id
           ) == 1
  end

  test "preserves authoritative matched, unmatched, and review cards" do
    set_id = id("authoritative")
    cards = Enum.map(["matched", "unmatched", "review"], &card(id(&1), "1", "brief"))
    full_set = Core.import_card_set!(%{tcgdex_id: set_id, name: "Set"})

    Enum.zip(cards, [
      %{
        mapping_status: "matched",
        cardmarket_product_id: 123,
        source_payload: %{"full" => true},
        source_updated_at: ~U[2026-01-01 00:00:00Z]
      },
      %{
        mapping_status: "unmatched",
        source_payload: %{"full" => true},
        source_updated_at: ~U[2026-01-01 00:00:00Z]
      },
      %{
        mapping_status: "review",
        mapping_review_reason: "manual",
        source_payload: %{"full" => true},
        source_updated_at: ~U[2026-01-01 00:00:00Z]
      }
    ])
    |> Enum.each(fn {card, extra} ->
      Core.import_card_printing!(
        Map.merge(
          %{
            tcgdex_id: card["id"],
            name: "Full",
            set_name: "Set",
            collector_number: "9",
            card_set_id: full_set.id
          },
          extra
        )
      )
    end)

    assert {:ok, result} =
             Sync.sync_set(
               set_id,
               opts(%{set_id => set(set_id, cards)}, fn -> ~U[2026-01-02 00:00:00Z] end)
             )

    assert result.cards_preserved == 3
    assert result.cards_seeded == 0

    for card <- cards do
      query =
        TcgCheap.Catalogue.CardPrinting
        |> Ash.Query.select([:tcgdex_id, :name, :source_payload])

      assert {:ok, stored} = Core.get_card_printing_by_tcgdex_id(card["id"], query: query)
      assert stored.name == "Full"
      assert stored.source_payload == %{"full" => true}
    end
  end

  test "refreshes and links an existing pending minimal row" do
    set_id = id("minimal-set")
    card_id = id("minimal-card")
    card_set = Core.import_card_set!(%{tcgdex_id: set_id, name: "Set"})

    minimal =
      Core.create_card_printing!(%{
        tcgdex_id: card_id,
        name: "Minimal",
        set_name: "Set",
        collector_number: "0"
      })

    assert minimal.card_set_id == nil

    assert {:ok, _} =
             Sync.sync_set(
               set_id,
               opts(%{set_id => set(set_id, [card(card_id, "1", "Refreshed")])}, fn ->
                 ~U[2026-01-01 00:00:00Z]
               end)
             )

    assert {:ok, refreshed} = Core.get_card_printing_by_tcgdex_id(card_id)
    assert refreshed.id == minimal.id
    assert refreshed.card_set_id == card_set.id
    assert refreshed.name == "Refreshed"
  end

  test "nil brief images preserve pending images while nonnil images refresh" do
    set_id = id("image-set")
    card_id = id("image-card")
    first = set(set_id, [card(card_id, "1")])
    second = set(set_id, [Map.put(card(card_id, "1"), "image", nil)])
    third = set(set_id, [Map.put(card(card_id, "1"), "image", "https://assets.example/new.png")])

    assert {:ok, _} =
             Sync.sync_set(set_id, opts(%{set_id => first}, fn -> ~U[2026-01-01 00:00:00Z] end))

    assert {:ok, _} =
             Sync.sync_set(set_id, opts(%{set_id => second}, fn -> ~U[2026-01-02 00:00:00Z] end))

    assert {:ok, retained} = Core.get_card_printing_by_tcgdex_id(card_id)
    assert retained.image_url == "https://assets.example/card/high.webp"

    assert {:ok, _} =
             Sync.sync_set(set_id, opts(%{set_id => third}, fn -> ~U[2026-01-03 00:00:00Z] end))

    assert {:ok, refreshed} = Core.get_card_printing_by_tcgdex_id(card_id)
    assert refreshed.image_url == "https://assets.example/new.png"
  end

  test "brief upsert condition protects a full import after a brief" do
    set_id = id("race-set")
    card_id = id("race-card")
    card_set = Core.import_card_set!(%{tcgdex_id: set_id, name: "Set"})

    brief = %{
      tcgdex_id: card_id,
      name: "Brief",
      set_name: "Set",
      collector_number: "1",
      card_set_id: card_set.id
    }

    assert {:ok, _} = Core.seed_card_printing_brief(brief)

    full =
      Map.merge(brief, %{
        name: "Full",
        source_payload: %{"source" => "full"},
        source_updated_at: ~U[2026-01-01 00:00:00Z],
        mapping_status: "matched",
        cardmarket_product_id: 999
      })

    imported = Core.import_card_printing!(full)
    assert imported.name == "Full"
    assert {:ok, skipped} = Core.seed_card_printing_brief(Map.put(brief, :name, "Late Brief"))
    assert Ash.Resource.get_metadata(skipped, :upsert_skipped) == true
    assert skipped.name == "Full"
  end

  test "concurrent brief and full import leave the enriched state authoritative" do
    set_id = id("race-concurrent-set")
    card_id = id("race-concurrent-card")
    synced_at = ~U[2026-05-01 00:00:00Z]
    payload_set = set(set_id, [card(card_id, "1")])

    payload_card = %{
      "id" => card_id,
      "name" => "Enriched",
      "localId" => "1",
      "set" => %{"id" => set_id},
      "updated" => "2026-05-01T00:00:00Z",
      "pricing" => %{"cardmarket" => %{"idProduct" => 777}}
    }

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from(c in "card_printings", where: c.tcgdex_id == ^card_id))
        Repo.delete_all(from(s in "card_sets", where: s.tcgdex_id == ^set_id))
      end)
    end)

    parent = self()

    tasks =
      [
        {:brief,
         fn ->
           Sync.sync_set(
             set_id,
             opts(%{set_id => payload_set}, fn -> synced_at end)
           )
         end},
        {:full,
         fn ->
           Importer.import_fetched_card(payload_card, payload_set, card_id,
             expected_set_id: set_id,
             synced_at: synced_at
           )
         end}
      ]
      |> Enum.map(fn {kind, fun} ->
        Task.async(fn ->
          send(parent, {:ready, self(), kind})

          receive do
            :go -> Sandbox.unboxed_run(Repo, fun)
          end
        end)
      end)

    assert_receive {:ready, first, _}, 5_000
    assert_receive {:ready, second, _}, 5_000
    send(first, :go)
    send(second, :go)
    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.all?(results, &match?({:ok, _}, &1))

    Sandbox.unboxed_run(Repo, fn ->
      assert {:ok, stored} = Core.get_card_printing_by_tcgdex_id(card_id)
      assert stored.name == "Enriched"
      assert stored.mapping_status == "matched"
      assert stored.cardmarket_product_id == 777
    end)
  end

  test "cross-set brief conflicts roll back the whole current set transaction" do
    current_set_id = id("current")
    foreign_set_id = id("foreign")
    first_id = id("first")
    conflict_id = id("conflict")
    foreign_set = Core.import_card_set!(%{tcgdex_id: foreign_set_id, name: "Foreign"})

    foreign =
      Core.import_card_printing!(%{
        tcgdex_id: conflict_id,
        name: "Foreign Card",
        set_name: "Foreign",
        collector_number: "9",
        card_set_id: foreign_set.id
      })

    current = set(current_set_id, [card(first_id, "1"), card(conflict_id, "2")])

    assert {:error, {:card_set_conflict, %{tcgdex_id: ^conflict_id}}} =
             Sync.sync_set(
               current_set_id,
               opts(%{current_set_id => current}, fn -> ~U[2026-01-01 00:00:00Z] end)
             )

    assert {:error, _} = Core.get_card_set_by_tcgdex_id(current_set_id)
    assert {:error, _} = Core.get_card_printing_by_tcgdex_id(first_id)
    assert {:ok, retained} = Core.get_card_printing_by_tcgdex_id(conflict_id)
    assert retained.id == foreign.id
    assert retained.card_set_id == foreign_set.id
    assert retained.name == "Foreign Card"
  end

  test "sync_all returns numeric aggregate counts and continues after failures" do
    first = id("first")
    broken = id("broken")
    third = id("third")

    sets = %{
      first => set(first, [card(id("one"), "1")]),
      third => set(third, [card(id("three"), "3")]),
      broken => {:error, :offline}
    }

    briefs = [
      %{"id" => first, "name" => "First"},
      %{"id" => broken, "name" => "Broken"},
      %{"id" => third, "name" => "Third"}
    ]

    assert {:ok, report} =
             Sync.sync_all_sets(
               provider: Provider,
               provider_options: [sets: sets, set_briefs: briefs],
               clock: fn -> ~U[2026-01-01 00:00:00Z] end
             )

    assert report.discovered_sets == 3
    assert report.synced_sets == 2
    assert report.failed_sets == 1
    assert report.cards_seen == 2
    assert report.cards_seeded == 2
    assert [%{set_id: ^broken, stage: :sync, reason: :offline}] = report.failures

    assert {:ok, [issue]} = Operations.list_admin_import_issues(authorize?: false)
    assert issue.operation == "card_catalogue_sync"
    assert issue.stage == "set_fetch"
    assert issue.target_type == "set"
    assert issue.target_key == broken
    assert issue.issue_kind == "failed"
    assert issue.issue_code == "unknown"
  end

  test "records bounded catalogue and malformed-set diagnostics without raw reasons" do
    secret = "https://provider.test/sets?token=do-not-retain"

    assert {:error, {:transport_error, ^secret}} =
             Sync.sync_all_sets(
               provider: Provider,
               provider_options: [list_result: {:error, {:transport_error, secret}}]
             )

    set_id = id("diagnostic-malformed")
    malformed = set(set_id, []) |> Map.delete("cardCount")

    assert {:error, {:malformed_response, {:set, :invalid_card_count_total}}} =
             Sync.sync_set(
               set_id,
               opts(%{set_id => malformed}, fn -> raise "business clock must not run" end)
             )

    assert {:ok, issues} = Operations.list_admin_import_issues(authorize?: false)

    assert Enum.map(issues, &{&1.stage, &1.issue_kind, &1.issue_code}) |> Enum.sort() ==
             [
               {"catalogue_fetch", "failed", "transport"},
               {"set_validation", "malformed", "malformed_response"}
             ]

    refute inspect(issues) =~ secret
  end

  test "normalizes malformed and failed list callbacks without retaining details" do
    callbacks = [
      {:return, :unexpected},
      {:raise, "raise-secret"},
      {:throw, "throw-secret"},
      {:exit, "exit-secret"}
    ]

    for callback <- callbacks do
      assert {:error, {:provider_callback_error, :list_sets, _}} =
               Sync.sync_all_sets(
                 provider: CallbackProvider,
                 provider_options: [list_result: callback]
               )
    end

    assert {:ok, [issue]} = Operations.list_admin_import_issues(authorize?: false)
    assert issue.stage == "catalogue_fetch"
    assert issue.issue_kind == "failed"
    assert issue.issue_code == "provider_response"
    refute inspect(issue) =~ "secret"
  end

  test "isolates a failed set callback and continues the catalogue" do
    first = id("callback-first")
    broken = id("callback-broken")
    third = id("callback-third")

    assert {:ok, report} =
             Sync.sync_all_sets(
               provider: CallbackProvider,
               provider_options: [
                 list_result:
                   {:ok,
                    [
                      %{"id" => first, "name" => "First"},
                      %{"id" => broken, "name" => "Broken"},
                      %{"id" => third, "name" => "Third"}
                    ]},
                 sets: %{
                   first => set(first, []),
                   broken => {:throw, "set-secret"},
                   third => set(third, [])
                 }
               ],
               clock: fn -> ~U[2026-01-01 00:00:00Z] end
             )

    assert report.synced_sets == 2
    assert report.failed_sets == 1

    assert [%{set_id: ^broken, stage: :sync, reason: {:provider_callback_error, :fetch_set, _}}] =
             report.failures

    assert {:ok, [issue]} = Operations.list_admin_import_issues(authorize?: false)
    assert issue.target_key == broken
    assert issue.stage == "set_fetch"
    assert issue.issue_code == "provider_response"
    refute inspect(issue) =~ "set-secret"
  end

  test "malformed list and invalid options do not write or raise" do
    assert {:error, :invalid_options} = Sync.sync_set(id("x"), "bad")
    assert {:error, :invalid_options} = Sync.sync_all_sets("bad")
    assert {:error, :invalid_options} = Sync.sync_all_sets(provider: Provider, provider: Provider)

    assert {:error, :invalid_provider_options} =
             Sync.sync_all_sets(provider: Provider, provider_options: "bad")

    assert {:error, :invalid_clock} = Sync.sync_all_sets(provider: Provider, clock: :not_a_clock)

    clock_set_id = id("clock")
    clock_set = set(clock_set_id, [])

    assert {:ok, clock_report} =
             Sync.sync_all_sets(
               provider: Provider,
               provider_options: [
                 sets: %{clock_set_id => clock_set},
                 set_briefs: [%{"id" => clock_set_id, "name" => "Clock"}]
               ],
               clock: fn -> raise "bad clock" end
             )

    assert clock_report.failed_sets == 1
    assert hd(clock_report.failures).reason == :invalid_clock

    assert {:error, :invalid_provider} = Sync.sync_all_sets(provider: __MODULE__)

    assert {:error, {:malformed_response, _}} =
             Sync.sync_all_sets(
               provider: Provider,
               provider_options: [list_result: {:ok, [%{"id" => "bad id", "name" => "Bad"}]}]
             )

    untouched_id = id("list-failure")

    assert {:error, :offline} =
             Sync.sync_all_sets(
               provider: Provider,
               provider_options: [list_result: {:error, :offline}]
             )

    assert {:error, _} = Core.get_card_set_by_tcgdex_id(untouched_id)
    assert {:error, _} = Core.get_card_printing_by_tcgdex_id(untouched_id)
  end
end
