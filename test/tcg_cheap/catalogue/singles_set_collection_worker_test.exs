defmodule TcgCheap.Catalogue.SinglesSetCollectionWorkerProvider do
  def list_sets(_opts), do: {:ok, []}

  def fetch_set(id, opts) do
    :ok = Keyword.fetch!(opts, :request_admitter).()
    fetch_set_from_agent(id, Keyword.fetch!(opts, :agent))
  end

  defp fetch_set_from_agent(id, agent) do
    case Agent.get(agent, fn state -> state.sets[id] end) do
      {:error, _} = error -> error
      set -> {:ok, set}
    end
  end

  def fetch_card(id, opts) do
    with :ok <- Keyword.fetch!(opts, :request_admitter).() do
      Agent.get_and_update(Keyword.fetch!(opts, :agent), fn state ->
        result = Map.get(state.cards, id, {:error, :not_found})

        {if(is_map(result), do: {:ok, result}, else: result),
         %{state | fetched: state.fetched ++ [id]}}
      end)
    end
  end
end

defmodule TcgCheap.Catalogue.SinglesSetCollectionWorkerAdmission do
  def admit(_key),
    do:
      Agent.get_and_update(Application.fetch_env!(:tcg_cheap, :singles_set_admissions), fn [h | t] ->
        {h, t}
      end)
end

defmodule TcgCheap.Catalogue.SinglesSetCollectionWorkerTest do
  use TcgCheap.DataCase, async: false
  import Oban.Testing
  alias TcgCheap.Catalogue.SinglesSetCollectionWorker

  setup do
    {:ok, provider} = Agent.start_link(fn -> %{sets: %{}, cards: %{}, fetched: []} end)
    {:ok, admissions} = Agent.start_link(fn -> List.duplicate({:ok, %{}}, 10) end)

    previous =
      for key <- [
            :catalogue_sync,
            :singles_collection,
            :acquisition_budget,
            :acquisition_budget_admitter,
            :singles_set_admissions
          ],
          into: %{},
          do: {key, Application.get_env(:tcg_cheap, key)}

    configure(provider, admissions, 20)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:tcg_cheap, key)
        {key, value} -> Application.put_env(:tcg_cheap, key, value)
      end)
    end)

    %{provider: provider, admissions: admissions}
  end

  test "me05 imports both cards, applies pitch scope, and enqueues only matched valuation", %{
    provider: provider,
    admissions: admissions
  } do
    ids = card_ids(2)

    put_fixture(provider, "me05", ids, [
      card(ids |> hd(), "matched", 123),
      card(Enum.at(ids, 1), "unmatched", nil)
    ])

    assert :ok = SinglesSetCollectionWorker.perform(job("me05", 0))
    assert Agent.get(provider, & &1.fetched) == ids
    cards = Enum.map(ids, &TcgCheap.Core.get_card_printing_by_tcgdex_id!/1)
    assert Enum.all?(cards, &(&1.collection_scopes == ["pitch_black_full"]))

    assert Enum.map(
             all_enqueued(repo: TcgCheap.Repo, worker: TcgCheap.Pricing.Singles.ValuationWorker),
             & &1.args["tcgdex_id"]
           ) == [hd(ids)]

    # One catalogue request for the set and one for each card; valuation
    # enqueueing is trusted background work and does not consume this budget.
    assert length(Agent.get(admissions, & &1)) == 7
  end

  test "persists usable embedded pricing without enqueueing valuation", %{provider: provider} do
    id = hd(card_ids(1))
    scoped_at = ~U[2026-08-19 12:00:00Z]

    priced =
      card(id, "matched", 123)
      |> Map.put("updated", "2026-08-18T10:00:00Z")
      |> Map.put("pricing", %{
        "cardmarket" => %{
          "unit" => "EUR",
          "idProduct" => 123,
          "updated" => "2026-08-18T10:00:00Z",
          "avg7" => 1.235,
          "avg30" => 9.99
        }
      })

    put_fixture(provider, "me05", [id], [priced])
    assert :ok = SinglesSetCollectionWorker.perform_on(job("me05", 0), scoped_at)

    card = TcgCheap.Core.get_card_printing_by_tcgdex_id!(id)

    assert {:ok, [snapshot]} =
             TcgCheap.Core.list_current_single_valuations(card.id, authorize?: false)

    assert Decimal.equal?(snapshot.value_eur, Decimal.new("1.24"))
    assert snapshot.source_metric == "avg7"
    assert snapshot.policy_version == "tcgdex_cardmarket_v1"
    assert snapshot.source == "tcgdex_cardmarket"
    assert snapshot.currency == "EUR"
    assert snapshot.cardmarket_product_id == 123
    assert DateTime.compare(snapshot.fetched_at, scoped_at) == :eq
    assert DateTime.compare(snapshot.provider_updated_at, ~U[2026-08-18 10:00:00Z]) == :eq
    refute_enqueued(repo: TcgCheap.Repo, worker: TcgCheap.Pricing.Singles.ValuationWorker)
  end

  test "rolling window selects exact IR/SIR rarities and expires two years later", %{
    provider: provider
  } do
    ids = card_ids(4)
    set_id = "sv-base-priority-#{System.unique_integer([:positive])}"

    cards = [
      card(Enum.at(ids, 0), "Illustration Rare", 1),
      card(Enum.at(ids, 1), "Special Illustration Rare", 2),
      card(Enum.at(ids, 2), "Rare", 3),
      card(Enum.at(ids, 3), "Illustration Rare", 4)
    ]

    put_fixture(provider, set_id, ids, cards, "2024-08-19")

    assert :ok =
             SinglesSetCollectionWorker.perform_on(
               job(set_id, 0),
               ~U[2026-08-19 12:00:00Z]
             )

    assert TcgCheap.Core.get_card_printing_by_tcgdex_id!(Enum.at(ids, 0)).collection_scopes == [
             "rolling_ir_sir"
           ]

    assert TcgCheap.Core.get_card_printing_by_tcgdex_id!(Enum.at(ids, 1)).collection_scopes == [
             "rolling_ir_sir"
           ]

    assert {:error, _} = TcgCheap.Core.get_card_printing_by_tcgdex_id(Enum.at(ids, 2))

    assert TcgCheap.Core.get_card_printing_by_tcgdex_id!(Enum.at(ids, 3)).collection_scopes == [
             "rolling_ir_sir"
           ]

    assert TcgCheap.Core.get_card_printing_by_tcgdex_id!(Enum.at(ids, 0)).collection_expires_on ==
             ~D[2026-08-19]
  end

  test "outside the rolling window does not fetch cards", %{provider: provider} do
    id = "sv-base-#{System.unique_integer([:positive])}"

    put_fixture(
      provider,
      "sv-base-#{System.unique_integer([:positive])}",
      [id],
      [card(id, "Illustration Rare", 1)],
      "2024-08-18"
    )

    set_id = hd(Map.keys(Agent.get(provider, & &1.sets)))
    assert :ok = SinglesSetCollectionWorker.perform(job(set_id, 0))
    assert Agent.get(provider, & &1.fetched) == []
  end

  test "current set with a release date before the as_of date is collected", %{provider: provider} do
    id = hd(card_ids(1))
    set_id = "sv-current-#{System.unique_integer([:positive])}"
    put_fixture(provider, set_id, [id], [card(id, "Illustration Rare", 1)], "2026-07-17")

    job = Map.update!(job(set_id, 0), :args, &Map.put(&1, "as_of", "2026-09-01"))

    assert :ok = SinglesSetCollectionWorker.perform(job)
    assert Agent.get(provider, & &1.fetched) == [id]
  end

  test "set released after as_of is rejected before fetching or persisting cards", %{
    provider: provider
  } do
    id = hd(card_ids(1))
    set_id = "sv-future-#{System.unique_integer([:positive])}"
    put_fixture(provider, set_id, [id], [card(id, "Illustration Rare", 1)], "2026-10-02")

    job = Map.update!(job(set_id, 0), :args, &Map.put(&1, "as_of", "2026-09-01"))

    assert {:cancel, :provider_response} = SinglesSetCollectionWorker.perform(job)
    assert Agent.get(provider, & &1.fetched) == []
    assert {:error, _} = TcgCheap.Core.get_card_printing_by_tcgdex_id(id)
  end

  test "old set is safely skipped rather than treated as a provider failure", %{
    provider: provider
  } do
    id = hd(card_ids(1))
    set_id = "sv-old-#{System.unique_integer([:positive])}"
    put_fixture(provider, set_id, [id], [card(id, "Illustration Rare", 1)], "2023-03-31")

    job = Map.update!(job(set_id, 0), :args, &Map.put(&1, "as_of", "2026-09-01"))

    assert :ok = SinglesSetCollectionWorker.perform(job)
    assert Agent.get(provider, & &1.fetched) == []
  end

  test "delayed rolling execution skips an expired boundary card", %{provider: provider} do
    id = hd(card_ids(1))
    set_id = "sv-delayed-#{System.unique_integer([:positive])}"
    put_fixture(provider, set_id, [id], [card(id, "Illustration Rare", 1)], "2024-08-19")

    assert :ok =
             SinglesSetCollectionWorker.perform_on(
               job(set_id, 0),
               ~U[2026-08-20 12:00:00Z]
             )

    assert Agent.get(provider, & &1.fetched) == []
    assert {:error, _} = TcgCheap.Core.get_card_printing_by_tcgdex_id(id)
  end

  test "chunk continuation and rerun are idempotent", %{provider: provider} do
    Application.put_env(:tcg_cheap, :singles_collection,
      pitch_black_set_id: "me05",
      paper_series_ids: ["sv", "me"],
      rolling_rarities: ["illustration rare", "special illustration rare"],
      chunk_size: 1
    )

    ids = card_ids(2)
    set_id = "me05"
    put_fixture(provider, set_id, ids, Enum.map(ids, &card(&1, "matched", 321)))
    assert :ok = SinglesSetCollectionWorker.perform(job(set_id, 0))

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: SinglesSetCollectionWorker,
      args: %{"policy_version" => 2, "set_id" => set_id, "offset" => 1, "as_of" => "2026-08-19"},
      priority: 0
    )

    assert :ok = SinglesSetCollectionWorker.perform(job(set_id, 1))
    assert :ok = SinglesSetCollectionWorker.perform(job(set_id, 0))
    assert length(Ash.read!(TcgCheap.Catalogue.CardPrinting, authorize?: false)) == 2
  end

  test "rolling continuation is enqueued at priority 1", %{provider: provider} do
    Application.put_env(:tcg_cheap, :singles_collection,
      pitch_black_set_id: "me05",
      paper_series_ids: ["sv", "me"],
      rolling_rarities: ["illustration rare", "special illustration rare"],
      chunk_size: 1
    )

    ids = card_ids(2)
    set_id = "sv-priority-#{System.unique_integer([:positive])}"

    put_fixture(
      provider,
      set_id,
      ids,
      Enum.map(ids, &card(&1, "Illustration Rare", 321)),
      "2026-08-19"
    )

    assert :ok = SinglesSetCollectionWorker.perform(job(set_id, 0))

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: SinglesSetCollectionWorker,
      args: %{
        "policy_version" => 2,
        "set_id" => set_id,
        "offset" => 1,
        "as_of" => "2026-08-19"
      },
      priority: 1
    )
  end

  test "rolling refresh on a curated card retains finite max expiry", %{provider: provider} do
    id = hd(card_ids(1))

    existing =
      TcgCheap.TestSupport.import_card_printing!(
        %{tcgdex_id: id, name: "Card", set_name: "Set", collector_number: "1"},
        scoped?: false,
        card_set?: false
      )

    TcgCheap.TestSupport.set_collection_scope!(
      existing,
      %{
        collection_scopes: ["curated_playable"],
        collection_scope_source: "system",
        collection_scoped_at: ~U[2025-01-01 00:00:00Z],
        collection_expires_on: ~D[2026-11-17]
      },
      authorize?: false
    )

    set_id = "sv-refresh-#{System.unique_integer([:positive])}"
    put_fixture(provider, set_id, [id], [card(id, "Illustration Rare", 123)], "2025-08-19")
    assert :ok = SinglesSetCollectionWorker.perform(job(set_id, 0))
    updated = TcgCheap.Core.get_card_printing_by_tcgdex_id!(id)
    assert updated.collection_scopes == ["curated_playable", "rolling_ir_sir"]
    assert updated.collection_expires_on == ~D[2027-08-19]
  end

  test "recent Pocket set is rejected before fetching or persisting cards", %{provider: provider} do
    id = hd(card_ids(1))

    Agent.update(provider, fn state ->
      %{
        state
        | sets: %{"sv01" => set("sv01", [%{"id" => id}], "2026-08-01", "tcgp")},
          cards: %{id => card(id, "Illustration Rare", 1)}
      }
    end)

    assert {:cancel, :provider_response} = SinglesSetCollectionWorker.perform(job("sv01", 0))
    assert Agent.get(provider, & &1.fetched) == []
    assert {:error, _} = TcgCheap.Core.get_card_printing_by_tcgdex_id(id)
  end

  test "legacy child payload is superseded without provider or budget calls", %{
    provider: provider
  } do
    legacy = job("me05", 0) |> Map.update!(:args, &Map.delete(&1, "policy_version"))

    assert {:cancel, :superseded_policy} = SinglesSetCollectionWorker.perform(legacy)
    assert Agent.get(provider, & &1.fetched) == []

    assert Agent.get(Application.fetch_env!(:tcg_cheap, :singles_set_admissions), & &1) ==
             List.duplicate({:ok, %{}}, 10)
  end

  test "unsupported and extra child payloads are malformed" do
    unsupported = job("me05", 0) |> Map.update!(:args, &Map.put(&1, "policy_version", 3))
    extra = job("me05", 0) |> Map.update!(:args, &Map.put(&1, "extra", true))

    assert {:cancel, :malformed_job_args} = SinglesSetCollectionWorker.perform(unsupported)
    assert {:cancel, :malformed_job_args} = SinglesSetCollectionWorker.perform(extra)
  end

  test "available legacy me05 child does not conflict with a versioned child" do
    {:ok, legacy} =
      SinglesSetCollectionWorker.new(%{
        "set_id" => "me05",
        "offset" => 0,
        "as_of" => "2026-08-19"
      })
      |> Oban.insert()

    assert {:ok, versioned} =
             SinglesSetCollectionWorker.new(%{
               "policy_version" => 2,
               "set_id" => "me05",
               "offset" => 0,
               "as_of" => "2026-08-19"
             })
             |> Oban.insert()

    assert versioned.id != legacy.id
    assert TcgCheap.Repo.get!(Oban.Job, legacy.id).state == "available"
  end

  test "duplicate and malformed briefs cancel before card fetch", %{provider: provider} do
    id = "sv-base-#{System.unique_integer([:positive])}"
    set_id = "me05"

    Agent.update(provider, fn s ->
      %{s | sets: %{set_id => set(set_id, [%{"id" => id}, %{"id" => id}])}}
    end)

    assert {:cancel, :provider_response} = SinglesSetCollectionWorker.perform(job(set_id, 0))
    assert Agent.get(provider, & &1.fetched) == []
  end

  test "incomplete selected set response is retryable as provider response", %{provider: provider} do
    id = hd(card_ids(1))
    put_fixture(provider, "me05", [id], [card(id, "matched", 123)])

    Agent.update(provider, fn state ->
      update_in(state, [:sets, "me05", "cardCount", "total"], &(&1 + 1))
    end)

    assert {:error, :provider_response} = SinglesSetCollectionWorker.perform(job("me05", 0))
  end

  test "timeout is retryable and budget rejection is retryable", %{
    provider: provider,
    admissions: admissions
  } do
    id = "sv#{System.unique_integer([:positive])}"
    set_id = "me05"
    put_fixture(provider, set_id, [id], [{:error, {:timeout, :request}}])
    assert {:error, :provider_timeout} = SinglesSetCollectionWorker.perform(job(set_id, 0))
    Agent.update(admissions, fn _ -> [{:error, :hourly_limit_reached}] end)

    assert {:snooze, seconds} =
             SinglesSetCollectionWorker.perform(job(set_id, 0))

    assert seconds > 0
    run = latest_run("tcgdex_catalogue")
    assert run.status == "retryable_failure"
    assert run.failure_category == "budget"
    assert run.request_count == 0
  end

  test "legacy source and timestamp are retained", %{provider: provider} do
    id = "me05-#{System.unique_integer([:positive])}"
    old = ~U[2025-01-01 00:00:00Z]

    existing =
      TcgCheap.TestSupport.import_card_printing!(
        %{tcgdex_id: id, name: "Old", set_name: "Old", collector_number: "1"},
        expires_on: nil,
        card_set?: false
      )

    TcgCheap.TestSupport.set_collection_scope!(
      existing,
      %{
        collection_scopes: ["legacy_local"],
        collection_scope_source: "legacy",
        collection_scoped_at: old,
        collection_expires_on: nil
      },
      authorize?: false
    )

    put_fixture(provider, "me05", [id], [card(id, "matched", 3)])
    assert :ok = SinglesSetCollectionWorker.perform(job("me05", 0))
    updated = TcgCheap.Core.get_card_printing_by_tcgdex_id!(id)
    assert updated.collection_scope_source == "legacy"
    assert DateTime.compare(updated.collection_scoped_at, old) == :eq
    assert "pitch_black_full" in updated.collection_scopes
  end

  defp configure(provider, admissions, chunk),
    do:
      (
        Application.put_env(:tcg_cheap, :catalogue_sync,
          provider: TcgCheap.Catalogue.SinglesSetCollectionWorkerProvider,
          provider_options: [agent: provider],
          batch_size: 20,
          batch_delay_seconds: 900,
          budget_backoff_seconds: 3600
        )

        Application.put_env(:tcg_cheap, :singles_collection,
          pitch_black_set_id: "me05",
          paper_series_ids: ["sv", "me"],
          rolling_rarities: ["illustration rare", "special illustration rare"],
          chunk_size: chunk
        )

        Application.put_env(:tcg_cheap, :acquisition_budget, budget_config())

        Application.put_env(
          :tcg_cheap,
          :acquisition_budget_admitter,
          TcgCheap.Catalogue.SinglesSetCollectionWorkerAdmission
        )

        Application.put_env(:tcg_cheap, :singles_set_admissions, admissions)
      )

  defp put_fixture(agent, set_id, ids, cards, release_date \\ "2026-01-01"),
    do:
      Agent.update(agent, fn s ->
        %{
          s
          | sets: %{set_id => set(set_id, Enum.map(ids, &%{"id" => &1}), release_date)},
            cards: Map.new(Enum.zip(ids, Enum.map(cards, &with_set(&1, set_id)))),
            fetched: []
        }
      end)

  defp set(id, cards, release \\ "2026-01-01", serie_id \\ nil),
    do: %{
      "id" => id,
      "name" => "Set",
      "serie" => %{"id" => serie_id || if(String.starts_with?(id, "me"), do: "me", else: "sv")},
      "releaseDate" => release,
      "cards" => cards,
      "cardCount" => %{"official" => length(cards), "total" => length(cards)}
    }

  defp card(id, rarity, product),
    do: %{
      "id" => id,
      "name" => "Card",
      "localId" => "1",
      "set" => %{"id" => "me05"},
      "rarity" => rarity,
      "pricing" => %{"cardmarket" => %{"idProduct" => product}}
    }

  defp with_set({:error, _} = error, _set_id), do: error
  defp with_set(card, set_id), do: Map.put(card, "set", %{"id" => set_id})

  defp card_ids(n),
    do: Enum.map(1..n, fn _ -> "sv-base-#{System.unique_integer([:positive])}" end)

  defp job(set_id, offset),
    do: %Oban.Job{
      args: %{
        "policy_version" => 2,
        "set_id" => set_id,
        "offset" => offset,
        "as_of" => "2026-08-19"
      },
      attempt: 1,
      max_attempts: 5,
      worker: Atom.to_string(SinglesSetCollectionWorker),
      queue: "catalogue_sync"
    }

  defp budget_config,
    do: [
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1000,
      global_monthly_spend_limit: "50.00",
      providers: [
        [
          provider_key: "tcgdex_catalogue",
          display_name: "TCGdex",
          estimated_cost_per_request: "0.00",
          hourly_request_limit: 100,
          daily_request_limit: 1000,
          monthly_request_limit: 20_000,
          monthly_spend_limit: "0.00"
        ],
        [
          provider_key: "tcgdex_cardmarket",
          display_name: "Cardmarket",
          estimated_cost_per_request: "0.00",
          hourly_request_limit: 100,
          daily_request_limit: 1000,
          monthly_request_limit: 20_000,
          monthly_spend_limit: "0.00"
        ]
      ]
    ]

  defp latest_run(provider_key),
    do:
      TcgCheap.Operations.list_recent_acquisition_runs!([provider_key], 1, authorize?: false)
      |> hd()
end
