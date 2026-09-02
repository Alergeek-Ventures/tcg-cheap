defmodule TcgCheap.Catalogue.CuratedPlayableCollectionProvider do
  def list_sets(_opts), do: {:ok, []}

  def fetch_card(id, opts) do
    with :ok <- Keyword.fetch!(opts, :request_admitter).() do
      agent = Keyword.fetch!(opts, :agent)
      result = Agent.get(agent, &Map.fetch!(&1.cards, id))

      case result do
        :raise -> raise("fixture boom")
        :throw -> throw(:fixture_throw)
        :exit -> exit(:fixture_exit)
        _ -> :ok
      end

      Agent.update(agent, &%{&1 | card_calls: &1.card_calls + 1})
      result
    end
  end

  def fetch_set(id, opts) do
    with :ok <- Keyword.fetch!(opts, :request_admitter).() do
      Agent.get_and_update(Keyword.fetch!(opts, :agent), fn state ->
        result = Map.fetch!(state.sets, id)
        response = normalize_set_result(result)
        {response, %{state | set_calls: state.set_calls + 1}}
      end)
    end
  end

  defp normalize_set_result({:error, _} = result), do: result
  defp normalize_set_result(result), do: {:ok, result}
end

defmodule TcgCheap.Catalogue.CuratedPlayableCollectionAdmission do
  def admit(_key),
    do:
      Agent.get_and_update(Application.fetch_env!(:tcg_cheap, :curated_admissions), fn [h | t] ->
        {h, t}
      end)
end

defmodule TcgCheap.Catalogue.CuratedPlayableCollectionWorkerTest do
  use TcgCheap.DataCase, async: false
  import Oban.Testing

  alias TcgCheap.Catalogue.{CuratedPlayableCollectionWorker, CuratedPlayablePolicy}

  setup do
    {:ok, agent} =
      Agent.start_link(fn -> %{cards: %{}, sets: %{}, card_calls: 0, set_calls: 0} end)

    previous =
      for key <- [
            :catalogue_sync,
            :acquisition_budget,
            :acquisition_budget_admitter,
            :curated_admissions
          ],
          into: %{},
          do: {key, Application.get_env(:tcg_cheap, key)}

    Application.put_env(:tcg_cheap, :catalogue_sync,
      provider: TcgCheap.Catalogue.CuratedPlayableCollectionProvider,
      provider_options: [agent: agent],
      batch_size: 20,
      batch_delay_seconds: 900,
      budget_backoff_seconds: 3600
    )

    Application.put_env(:tcg_cheap, :acquisition_budget, budget_config())

    Application.put_env(
      :tcg_cheap,
      :acquisition_budget_admitter,
      TcgCheap.Catalogue.CuratedPlayableCollectionAdmission
    )

    {:ok, admissions} = Agent.start_link(fn -> List.duplicate({:ok, %{}}, 50) end)
    Application.put_env(:tcg_cheap, :curated_admissions, admissions)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:tcg_cheap, key)
        {key, value} -> Application.put_env(:tcg_cheap, key, value)
      end)
    end)

    %{agent: agent, admissions: admissions}
  end

  test "validates, admits exactly card then set, imports, scopes, and queues matched valuation",
       %{agent: agent, admissions: admissions} do
    entry = CuratedPlayablePolicy.entry("me01-131")

    Agent.update(
      agent,
      &%{
        &1
        | cards: %{entry.tcgdex_id => {:ok, card(entry)}},
          sets: %{entry.set_id => set(entry)}
      }
    )

    assert :ok = CuratedPlayableCollectionWorker.perform_on(job(entry.tcgdex_id), ~D[2026-08-19])
    assert %{card_calls: 1, set_calls: 1} = Agent.get(agent, & &1)
    assert length(Agent.get(admissions, & &1)) == 48
    imported = TcgCheap.Core.get_card_printing_by_tcgdex_id!(entry.tcgdex_id)
    assert imported.collection_scopes == ["curated_playable"]
    assert imported.collection_expires_on == ~D[2026-11-17]

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: TcgCheap.Pricing.Singles.ValuationWorker,
      args: %{"tcgdex_id" => entry.tcgdex_id}
    )
  end

  test "unknown, malformed, and out-of-window jobs do not call provider or admission", %{
    agent: agent,
    admissions: admissions
  } do
    assert {:cancel, :malformed_job_args} =
             CuratedPlayableCollectionWorker.perform_on(job("unknown"), ~D[2026-08-19])

    assert {:cancel, :evidence_not_yet_valid} =
             CuratedPlayableCollectionWorker.perform_on(job("me01-131"), ~D[2026-08-18])

    assert {:cancel, :evidence_expired} =
             CuratedPlayableCollectionWorker.perform_on(job("me01-131"), ~D[2026-11-18])

    assert {:cancel, :malformed_job_args} =
             CuratedPlayableCollectionWorker.perform_on(
               %Oban.Job{
                 args: %{
                   "evidence_version" => "2026-08-19-naic",
                   "tcgdex_id" => "me01-131",
                   "extra" => true
                 }
               },
               ~D[2026-08-19]
             )

    assert Agent.get(agent, &{&1.card_calls, &1.set_calls}) == {0, 0}
    assert length(Agent.get(admissions, & &1)) == 50
  end

  test "budget rejection prevents the corresponding provider request", %{
    agent: agent,
    admissions: admissions
  } do
    entry = CuratedPlayablePolicy.entry("me01-131")

    Agent.update(
      agent,
      &%{
        &1
        | cards: %{entry.tcgdex_id => {:ok, card(entry)}},
          sets: %{entry.set_id => set(entry)}
      }
    )

    Agent.update(admissions, fn _ -> [{:error, :limit}] end)

    assert {:error, :acquisition_budget_rejected} =
             CuratedPlayableCollectionWorker.perform_on(job(entry.tcgdex_id), ~D[2026-08-19])

    assert Agent.get(agent, &{&1.card_calls, &1.set_calls}) == {0, 0}
    assert Agent.get(admissions, & &1) == []

    Agent.update(admissions, fn _ -> [{:ok, %{}}, {:error, :limit}] end)

    assert {:error, :acquisition_budget_rejected} =
             CuratedPlayableCollectionWorker.perform_on(job(entry.tcgdex_id), ~D[2026-08-19])

    assert Agent.get(agent, &{&1.card_calls, &1.set_calls}) == {1, 0}
    assert Agent.get(admissions, & &1) == []
  end

  test "provider failures classify safely", %{agent: agent, admissions: admissions} do
    entry = CuratedPlayablePolicy.entry("me01-131")

    for {failure, expected} <- [
          {{:error, :timeout}, {:error, :provider_timeout}},
          {{:error, :transport_error}, {:error, :provider_transport_error}},
          {{:error, :rate_limited}, {:error, :provider_rate_limited}},
          {:raise, {:error, :provider_response}},
          {:throw, {:error, :provider_response}},
          {:exit, {:error, :provider_response}}
        ] do
      Agent.update(
        agent,
        &%{&1 | cards: %{entry.tcgdex_id => failure}, sets: %{entry.set_id => set(entry)}}
      )

      Agent.update(admissions, fn _ -> List.duplicate({:ok, %{}}, 4) end)

      assert CuratedPlayableCollectionWorker.perform_on(job(entry.tcgdex_id), ~D[2026-08-19]) ==
               expected
    end
  end

  test "identity, trainer, legality, set, series, and release mismatches fail closed", %{
    agent: agent
  } do
    entry = CuratedPlayablePolicy.entry("me01-131")
    base_card = card(entry)

    invalid_cards = [
      Map.put(base_card, "id", "me01-114"),
      Map.put(base_card, "localId", "999"),
      Map.put(base_card, "name", "Wrong"),
      Map.put(base_card, "category", "Pokémon"),
      Map.put(base_card, "trainerType", "Supporter"),
      Map.put(base_card, "regulationMark", "H"),
      Map.put(base_card, "legal", %{"standard" => false}),
      Map.put(base_card, "set", %{"id" => "me02"})
    ]

    Enum.each(invalid_cards, fn invalid ->
      Agent.update(
        agent,
        &%{&1 | cards: %{entry.tcgdex_id => {:ok, invalid}}, sets: %{entry.set_id => set(entry)}}
      )

      assert {:cancel, :provider_response} =
               CuratedPlayableCollectionWorker.perform_on(job(entry.tcgdex_id), ~D[2026-08-19])

      assert {:error, _} = TcgCheap.Core.get_card_printing_by_tcgdex_id(entry.tcgdex_id)
    end)

    for invalid_set <- [
          Map.put(set(entry), "id", "me02"),
          Map.delete(set(entry), "name"),
          Map.put(set(entry), "name", "   "),
          Map.put(set(entry), "name", 123),
          Map.put(set(entry), "serie", %{"id" => "sv"}),
          Map.put(set(entry), "releaseDate", "2026-08-20"),
          Map.put(set(entry), "releaseDate", 20_260_819),
          Map.put(set(entry), "releaseDate", "not-a-date")
        ] do
      Agent.update(
        agent,
        &%{
          &1
          | cards: %{entry.tcgdex_id => {:ok, base_card}},
            sets: %{entry.set_id => invalid_set}
        }
      )

      assert {:cancel, :provider_response} =
               CuratedPlayableCollectionWorker.perform_on(job(entry.tcgdex_id), ~D[2026-08-19])

      assert {:error, _} = TcgCheap.Core.get_card_printing_by_tcgdex_id(entry.tcgdex_id)
    end
  end

  test "reruns preserve administrator permanent expiry and legacy scopes", %{agent: agent} do
    entry = CuratedPlayablePolicy.entry("me01-131")

    card =
      TcgCheap.TestSupport.import_card_printing!(
        %{
          tcgdex_id: entry.tcgdex_id,
          name: entry.name,
          set_name: "Mega Evolution",
          collector_number: "131",
          mapping_status: "matched",
          cardmarket_product_id: 123
        },
        scoped?: false,
        card_set?: false
      )

    TcgCheap.TestSupport.set_collection_scope!(
      card,
      %{
        collection_scopes: ["legacy_local"],
        collection_scope_source: "administrator",
        collection_scoped_at: ~U[2025-01-01 00:00:00Z],
        collection_expires_on: nil
      },
      authorize?: false
    )

    Agent.update(
      agent,
      &%{
        &1
        | cards: %{entry.tcgdex_id => {:ok, card(entry)}},
          sets: %{entry.set_id => set(entry)}
      }
    )

    assert :ok = CuratedPlayableCollectionWorker.perform_on(job(entry.tcgdex_id), ~D[2026-08-19])
    updated = TcgCheap.Core.get_card_printing_by_tcgdex_id!(entry.tcgdex_id)
    assert updated.collection_scope_source == "administrator"
    assert updated.collection_expires_on == nil
    assert "legacy_local" in updated.collection_scopes
  end

  test "rerun is idempotent and preserves a later finite expiry", %{agent: agent} do
    entry = CuratedPlayablePolicy.entry("me01-131")

    existing =
      TcgCheap.TestSupport.import_card_printing!(
        %{
          tcgdex_id: entry.tcgdex_id,
          name: entry.name,
          set_name: "Mega Evolution",
          collector_number: "131"
        },
        scoped?: false,
        card_set?: false
      )

    TcgCheap.TestSupport.set_collection_scope!(
      existing,
      %{
        collection_scopes: ["rolling_ir_sir"],
        collection_scope_source: "administrator",
        collection_scoped_at: ~U[2025-01-01 00:00:00Z],
        collection_expires_on: ~D[2027-01-01]
      },
      authorize?: false
    )

    Agent.update(
      agent,
      &%{
        &1
        | cards: %{entry.tcgdex_id => {:ok, card(entry)}},
          sets: %{entry.set_id => set(entry)}
      }
    )

    assert :ok = CuratedPlayableCollectionWorker.perform_on(job(entry.tcgdex_id), ~D[2026-08-19])
    assert :ok = CuratedPlayableCollectionWorker.perform_on(job(entry.tcgdex_id), ~D[2026-08-19])
    updated = TcgCheap.Core.get_card_printing_by_tcgdex_id!(entry.tcgdex_id)
    assert updated.collection_expires_on == ~D[2027-01-01]
    assert updated.collection_scopes == ["curated_playable", "rolling_ir_sir"]
    assert length(Ash.read!(TcgCheap.Catalogue.CardPrinting, authorize?: false)) == 1
  end

  test "child uniqueness is scoped to exact evidence version and card" do
    one =
      Oban.insert!(
        CuratedPlayableCollectionWorker.new(%{
          "evidence_version" => "2026-08-19-naic",
          "tcgdex_id" => "me01-131"
        })
      )

    same =
      Oban.insert!(
        CuratedPlayableCollectionWorker.new(%{
          "evidence_version" => "2026-08-19-naic",
          "tcgdex_id" => "me01-131"
        })
      )

    other =
      Oban.insert!(
        CuratedPlayableCollectionWorker.new(%{
          "evidence_version" => "2026-08-19-naic",
          "tcgdex_id" => "me01-114"
        })
      )

    assert one.id == same.id
    refute one.id == other.id
  end

  test "completed child uniqueness is retained while the Pruner retains it" do
    args = %{"evidence_version" => "2026-08-19-naic", "tcgdex_id" => "me01-131"}
    first = Oban.insert!(CuratedPlayableCollectionWorker.new(args))

    {1, _} =
      TcgCheap.Repo.update_all(
        from(j in Oban.Job, where: j.id == ^first.id),
        set: [state: "completed", inserted_at: DateTime.add(DateTime.utc_now(), -8, :day)]
      )

    second = Oban.insert!(CuratedPlayableCollectionWorker.new(args))

    assert %{state: "completed"} = TcgCheap.Repo.get!(Oban.Job, first.id)
    assert second.id == first.id
  end

  test "budget failures use one-hour backoff and unsupported versions are malformed" do
    for reason <- [:acquisition_budget_rejected, :budget_persistence_failed] do
      assert CuratedPlayableCollectionWorker.backoff(%Oban.Job{
               attempt: 1,
               unsaved_error: %{reason: %Oban.PerformError{reason: reason}}
             }) == 3_600
    end

    assert {:cancel, :malformed_job_args} =
             CuratedPlayableCollectionWorker.perform_on(
               %Oban.Job{args: %{"evidence_version" => "wrong", "tcgdex_id" => "me01-131"}},
               ~D[2026-08-19]
             )
  end

  test "unmatched and review mappings do not enqueue valuation", %{agent: agent} do
    entry = CuratedPlayablePolicy.entry("me01-131")

    for payload <- [
          Map.delete(card(entry), "pricing"),
          Map.put(card(entry), "variants_detailed", %{"foil" => %{"foil" => "holo"}})
        ] do
      Agent.update(
        agent,
        &%{&1 | cards: %{entry.tcgdex_id => {:ok, payload}}, sets: %{entry.set_id => set(entry)}}
      )

      assert :ok =
               CuratedPlayableCollectionWorker.perform_on(job(entry.tcgdex_id), ~D[2026-08-19])

      refute_enqueued(repo: TcgCheap.Repo, worker: TcgCheap.Pricing.Singles.ValuationWorker)
    end
  end

  defp card(e),
    do: %{
      "id" => e.tcgdex_id,
      "name" => e.name,
      "localId" => String.split(e.tcgdex_id, "-") |> List.last(),
      "category" => e.category,
      "trainerType" => e.trainer_type,
      "regulationMark" => e.regulation_mark,
      "set" => %{"id" => e.set_id},
      "legal" => %{"standard" => true},
      "pricing" => %{"cardmarket" => %{"idProduct" => 123}}
    }

  defp set(e),
    do: %{
      "id" => e.set_id,
      "name" => "Mega Evolution",
      "releaseDate" => "2026-01-01",
      "serie" => %{"id" => String.slice(e.set_id, 0, 2)}
    }

  defp job(id),
    do: %Oban.Job{
      args: %{"evidence_version" => "2026-08-19-naic", "tcgdex_id" => id},
      attempt: 1,
      max_attempts: 5,
      worker: Atom.to_string(CuratedPlayableCollectionWorker),
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
