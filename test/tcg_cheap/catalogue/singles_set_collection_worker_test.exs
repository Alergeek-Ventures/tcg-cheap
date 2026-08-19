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

  test "rolling window selects exact IR/SIR rarities and expires two years later", %{
    provider: provider
  } do
    ids = card_ids(4)
    set_id = "sv-base-#{System.unique_integer([:positive])}"

    cards = [
      card(Enum.at(ids, 0), "Illustration Rare", 1),
      card(Enum.at(ids, 1), "Special Illustration Rare", 2),
      card(Enum.at(ids, 2), "Rare", 3),
      card(Enum.at(ids, 3), "Illustration Rare", 4)
    ]

    put_fixture(provider, set_id, ids, cards, "2024-08-19")
    assert :ok = SinglesSetCollectionWorker.perform(job(set_id, 0))

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

  test "chunk continuation and rerun are idempotent", %{provider: provider} do
    Application.put_env(:tcg_cheap, :singles_collection,
      pitch_black_set_id: "me05",
      rolling_rarities: ["illustration rare", "special illustration rare"],
      chunk_size: 1
    )

    ids = card_ids(2)
    put_fixture(provider, "me05", ids, Enum.map(ids, &card(&1, "matched", 321)))
    assert :ok = SinglesSetCollectionWorker.perform(job("me05", 0))

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: SinglesSetCollectionWorker,
      args: %{"set_id" => "me05", "offset" => 1, "as_of" => "2026-08-19"}
    )

    assert :ok = SinglesSetCollectionWorker.perform(job("me05", 1))
    assert :ok = SinglesSetCollectionWorker.perform(job("me05", 0))
    assert length(Ash.read!(TcgCheap.Catalogue.CardPrinting, authorize?: false)) == 2
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

    assert {:error, :acquisition_budget_rejected} =
             SinglesSetCollectionWorker.perform(job(set_id, 0))
  end

  test "legacy source and timestamp are retained", %{provider: provider} do
    id = "me05-#{System.unique_integer([:positive])}"
    old = ~U[2025-01-01 00:00:00Z]

    existing =
      TcgCheap.TestSupport.import_card_printing!(
        %{tcgdex_id: id, name: "Old", set_name: "Old", collector_number: "1"},
        expires_on: nil
      )

    TcgCheap.Core.set_card_printing_collection_scope!(
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

  defp set(id, cards, release \\ "2026-01-01"),
    do: %{
      "id" => id,
      "name" => "Set",
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
      args: %{"set_id" => set_id, "offset" => offset, "as_of" => "2026-08-19"},
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
end
