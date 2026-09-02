defmodule TcgCheap.Catalogue.CardDetailEnrichmentWorkerTestProvider do
  def fetch_card(_id, opts) do
    agent = Keyword.fetch!(opts, :agent)

    with :ok <- Keyword.fetch!(opts, :request_admitter).() do
      Agent.get_and_update(agent, fn state ->
        {state.result, %{state | fetch_cards: state.fetch_cards + 1}}
      end)
    end
  end

  def fetch_set(_, _), do: raise("detail enrichment must not fetch sets")
  def list_sets(_), do: raise("detail enrichment must not list sets")
end

defmodule TcgCheap.Catalogue.CardDetailEnrichmentWorkerAdmission do
  def admit(_key) do
    Agent.get_and_update(
      Application.fetch_env!(:tcg_cheap, :detail_worker_admissions),
      fn state ->
        {state.result, %{state | calls: state.calls + 1}}
      end
    )
  end
end

defmodule TcgCheap.Catalogue.CardDetailEnrichmentWorkerFailingValuation do
  def record_or_enqueue(_card, _provider_card, _fetched_at), do: {:error, :persistence_failed}
end

defmodule TcgCheap.Catalogue.CardDetailEnrichmentWorkerTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing

  alias TcgCheap.Catalogue.CardDetailEnrichmentWorker
  alias TcgCheap.Catalogue.CardDetailEnrichmentWorkerAdmission, as: AdmissionHelper
  alias TcgCheap.Catalogue.CardDetailEnrichmentWorkerTestProvider, as: ProviderHelper
  alias TcgCheap.Core
  alias TcgCheap.Operations
  alias TcgCheap.Pricing.Singles.ValuationWorker

  setup do
    previous_sync = Application.get_env(:tcg_cheap, :catalogue_sync)
    previous_admitter = Application.get_env(:tcg_cheap, :acquisition_budget_admitter)

    previous_valuation =
      Application.get_env(:tcg_cheap, :card_detail_enrichment_embedded_valuation)

    {:ok, provider} =
      Agent.start_link(fn -> %{fetch_cards: 0, result: {:ok, payload("sv1-1")}} end)

    {:ok, admissions} = Agent.start_link(fn -> %{calls: 0, result: {:ok, %{}}} end)

    Application.put_env(:tcg_cheap, :catalogue_sync,
      provider: __MODULE__.TestProvider,
      provider_options: [agent: provider],
      batch_size: 1,
      batch_delay_seconds: 900,
      budget_backoff_seconds: 3600
    )

    Application.put_env(:tcg_cheap, :acquisition_budget_admitter, __MODULE__.Admission)
    Application.put_env(:tcg_cheap, :detail_worker_admissions, admissions)

    on_exit(fn ->
      restore(:catalogue_sync, previous_sync)
      restore(:acquisition_budget_admitter, previous_admitter)
      restore(:card_detail_enrichment_embedded_valuation, previous_valuation)
      Application.delete_env(:tcg_cheap, :detail_worker_admissions)
    end)

    %{provider: provider, admissions: admissions}
  end

  test "performs a real detailed import, telemetry, embedded valuation, completion, and continuation",
       %{
         provider: provider,
         admissions: admissions
       } do
    {card, next} = cards()
    Agent.update(provider, &%{&1 | result: {:ok, payload(card.tcgdex_id)}})
    Phoenix.PubSub.subscribe(TcgCheap.PubSub, CardDetailEnrichmentWorker.topic(card.id))

    assert :ok = CardDetailEnrichmentWorker.perform(job(card, true, 11))
    assert %{fetch_cards: 1} = Agent.get(provider, & &1)
    assert %{calls: 1} = Agent.get(admissions, & &1)

    stored = Core.get_card_printing_by_tcgdex_id!(card.tcgdex_id)
    assert stored.name == "Fetched #{card.tcgdex_id}"
    assert stored.details_synced_at != nil
    assert stored.pricing_checked_at == stored.details_synced_at
    assert stored.collector_number == "1"
    assert stored.set_name == "Set"

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: CardDetailEnrichmentWorker,
      args: %{"tcgdex_id" => next.tcgdex_id, "continue" => true},
      priority: 5
    )

    refute_enqueued(
      repo: TcgCheap.Repo,
      worker: ValuationWorker,
      args: %{"card_printing_id" => card.id}
    )

    assert_receive {:card_detail_enrichment_completed, %{local_card_id: id}} when id == card.id

    assert {:ok, [%{value_eur: seven}]} =
             Core.list_current_single_valuations(card.id, authorize?: false)

    assert Decimal.equal?(seven, Decimal.new("2.5"))

    assert {:ok, [run]} =
             Operations.list_recent_acquisition_runs(["tcgdex_catalogue"], 10, authorize?: false)

    assert run.status == "succeeded"
    assert run.request_count == 1
  end

  test "enqueue is priority five and active duplicates reuse one job", %{provider: _provider} do
    {card, _next} = cards()
    assert {:ok, first} = CardDetailEnrichmentWorker.enqueue(card, false)
    assert {:ok, duplicate} = CardDetailEnrichmentWorker.enqueue(card, false)
    assert duplicate.conflict?
    assert duplicate.id == first.id
    assert first.priority == 5
  end

  test "navigation and background jobs conflict independently in either insertion order" do
    {card, _} = cards()
    assert {:ok, navigation} = CardDetailEnrichmentWorker.enqueue(card, false, priority: 0)
    assert {:ok, background} = CardDetailEnrichmentWorker.enqueue(card, true, priority: 5)
    assert navigation.priority == 0
    assert background.priority == 5

    assert {:ok, duplicate_navigation} =
             CardDetailEnrichmentWorker.enqueue(card, false, priority: 0)

    assert duplicate_navigation.conflict?

    {other, _} = cards()
    assert {:ok, background_first} = CardDetailEnrichmentWorker.enqueue(other, true, priority: 5)

    assert {:ok, navigation_second} =
             CardDetailEnrichmentWorker.enqueue(other, false, priority: 0)

    assert background_first.priority == 5
    assert navigation_second.priority == 0

    assert {:ok, duplicate_background} =
             CardDetailEnrichmentWorker.enqueue(other, true, priority: 5)

    assert duplicate_background.conflict?
  end

  test "checked cards skip the provider, continue in background, and no-op navigation", %{
    provider: provider
  } do
    {card, next} = cards()

    assert {:ok, _} =
             Core.mark_card_printing_pricing_checked(card, DateTime.utc_now(), authorize?: false)

    assert :ok = CardDetailEnrichmentWorker.perform(job(card, true, 31))
    assert {:ok, []} = Core.list_current_single_valuations(card.id, authorize?: false)
    assert %{fetch_cards: 0} = Agent.get(provider, & &1)

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: CardDetailEnrichmentWorker,
      args: %{"tcgdex_id" => next.tcgdex_id, "continue" => true}
    )

    assert :ok = CardDetailEnrichmentWorker.perform(job(card, false, 32))
    assert %{fetch_cards: 0} = Agent.get(provider, & &1)
  end

  test "staged detail imports resume pricing without fetching and continue", %{provider: provider} do
    synced_at = ~U[2026-03-01 00:00:00.123456Z]
    {card, next} = cards(details_synced_at: synced_at, source_payload: :matching_payload)

    assert :ok = CardDetailEnrichmentWorker.perform(job(card, true, 37))
    assert %{fetch_cards: 0} = Agent.get(provider, & &1)

    stored = Core.get_card_printing_by_tcgdex_id!(card.tcgdex_id)
    assert stored.details_synced_at == synced_at
    assert stored.pricing_checked_at != nil

    assert {:ok, [%{value_eur: seven}]} =
             Core.list_current_single_valuations(card.id, authorize?: false)

    assert Decimal.equal?(seven, Decimal.new("2.5"))

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: CardDetailEnrichmentWorker,
      args: %{"tcgdex_id" => next.tcgdex_id, "continue" => true},
      priority: 5
    )
  end

  test "max-attempt pricing persistence failures snooze without advancing", %{provider: provider} do
    synced_at = ~U[2026-03-01 00:00:00.123456Z]
    {card, _next} = cards(details_synced_at: synced_at, source_payload: :matching_payload)

    Application.put_env(
      :tcg_cheap,
      :card_detail_enrichment_embedded_valuation,
      TcgCheap.Catalogue.CardDetailEnrichmentWorkerFailingValuation
    )

    assert {:snooze, 60} = CardDetailEnrichmentWorker.perform(job(card, true, 38, 5))
    assert %{fetch_cards: 0} = Agent.get(provider, & &1)
    refute_enqueued(repo: TcgCheap.Repo, worker: CardDetailEnrichmentWorker)

    stored = Core.get_card_printing_by_tcgdex_id!(card.tcgdex_id)
    assert stored.pricing_checked_at == nil
    assert {:ok, []} = Core.list_current_single_valuations(card.id, authorize?: false)
  end

  test "permanent failures mark pricing checked and repeated execution skips provider", %{
    provider: provider
  } do
    {card, next} = cards()
    Agent.update(provider, &%{&1 | result: {:error, {:http_error, 404}}})

    assert {:cancel, :provider_response} = CardDetailEnrichmentWorker.perform(job(card, true, 33))
    checked = Core.get_card_printing_by_tcgdex_id!(card.tcgdex_id)
    assert checked.pricing_checked_at

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: CardDetailEnrichmentWorker,
      args: %{"tcgdex_id" => next.tcgdex_id, "continue" => true}
    )

    assert %{fetch_cards: 1} = Agent.get(provider, & &1)

    assert :ok = CardDetailEnrichmentWorker.perform(job(card, false, 34))
    assert %{fetch_cards: 1} = Agent.get(provider, & &1)
  end

  test "missing and Pocket card sets are rejected safely and background advances", %{
    provider: provider
  } do
    missing =
      TcgCheap.TestSupport.import_card_printing!(
        %{
          tcgdex_id: "missing-set-#{System.unique_integer([:positive])}",
          name: "Missing",
          set_name: "Missing",
          collector_number: "1"
        },
        scoped?: false,
        card_set?: false
      )

    pocket_set =
      Core.import_card_set!(%{
        tcgdex_id: "pocket-#{System.unique_integer([:positive])}",
        name: "Pocket",
        series_id: "tcgp"
      })

    pocket = import_card(pocket_set, "pocket-card-#{System.unique_integer([:positive])}")
    {_paper, next} = cards()

    assert {:cancel, :invalid_card_set} =
             CardDetailEnrichmentWorker.perform(job(missing, true, 35))

    assert {:cancel, :invalid_card_set} =
             CardDetailEnrichmentWorker.perform(job(pocket, true, 36))

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: CardDetailEnrichmentWorker,
      args: %{"tcgdex_id" => next.tcgdex_id, "continue" => true}
    )

    assert %{fetch_cards: 0} = Agent.get(provider, & &1)
  end

  test "hourly rejection snoozes by an exact positive delay without continuation", %{
    admissions: admissions
  } do
    {card, _next} = cards()
    card_id = card.id
    reset = DateTime.add(DateTime.utc_now(), 90, :second)

    Agent.update(
      admissions,
      &%{&1 | result: {:error, {:acquisition_budget_rejected, :hourly_limit_reached, reset}}}
    )

    Phoenix.PubSub.subscribe(TcgCheap.PubSub, CardDetailEnrichmentWorker.topic(card.id))
    assert {:snooze, delay} = CardDetailEnrichmentWorker.perform(job(card, true, 12))
    assert delay == 90
    refute_enqueued(repo: TcgCheap.Repo, worker: CardDetailEnrichmentWorker)
    assert_receive {:card_detail_enrichment_deferred, %{local_card_id: ^card_id}}
  end

  test "404 and malformed responses cancel and continue", %{provider: provider} do
    {card, next} = cards()
    Agent.update(provider, &%{&1 | result: {:error, {:http_error, 404}}})
    assert {:cancel, :provider_response} = CardDetailEnrichmentWorker.perform(job(card, true, 13))

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: CardDetailEnrichmentWorker,
      args: %{"tcgdex_id" => next.tcgdex_id, "continue" => true}
    )
  end

  test "malformed provider responses also cancel and advance the chain", %{provider: provider} do
    {card, next} = cards()
    Agent.update(provider, &%{&1 | result: {:error, {:malformed_response, :invalid_payload}}})

    assert {:cancel, :provider_response} = CardDetailEnrichmentWorker.perform(job(card, true, 16))

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: CardDetailEnrichmentWorker,
      args: %{"tcgdex_id" => next.tcgdex_id, "continue" => true}
    )
  end

  test "transport failures retry, defer completion, and do not continue", %{provider: provider} do
    {card, _next} = cards()
    card_id = card.id
    Agent.update(provider, &%{&1 | result: {:error, :provider_transport_error}})
    Phoenix.PubSub.subscribe(TcgCheap.PubSub, CardDetailEnrichmentWorker.topic(card.id))

    assert {:error, :provider_transport_error} =
             CardDetailEnrichmentWorker.perform(job(card, true, 14))

    refute_enqueued(repo: TcgCheap.Repo, worker: CardDetailEnrichmentWorker)
    assert_receive {:card_detail_enrichment_deferred, %{local_card_id: ^card_id}}
  end

  test "provider timeouts retry and defer completion without continuation", %{provider: provider} do
    {card, _next} = cards()
    card_id = card.id
    Agent.update(provider, &%{&1 | result: {:error, :provider_timeout}})
    Phoenix.PubSub.subscribe(TcgCheap.PubSub, CardDetailEnrichmentWorker.topic(card.id))

    assert {:error, :provider_timeout} = CardDetailEnrichmentWorker.perform(job(card, true, 15))
    refute_enqueued(repo: TcgCheap.Repo, worker: CardDetailEnrichmentWorker)
    assert_receive {:card_detail_enrichment_deferred, %{local_card_id: ^card_id}}
  end

  test "rate limits retry and defer completion without continuation", %{provider: provider} do
    {card, _next} = cards()
    card_id = card.id
    Agent.update(provider, &%{&1 | result: {:error, :rate_limited}})
    Phoenix.PubSub.subscribe(TcgCheap.PubSub, CardDetailEnrichmentWorker.topic(card.id))

    assert {:error, :provider_rate_limited} =
             CardDetailEnrichmentWorker.perform(job(card, true, 17))

    refute_enqueued(repo: TcgCheap.Repo, worker: CardDetailEnrichmentWorker)
    assert_receive {:card_detail_enrichment_deferred, %{local_card_id: ^card_id}}
  end

  defmodule TestProvider do
    def fetch_card(id, opts),
      do:
        ProviderHelper.fetch_card(
          id,
          Keyword.put(opts, :agent, Keyword.fetch!(opts, :agent))
        )

    def fetch_set(id, opts),
      do: ProviderHelper.fetch_set(id, opts)

    def list_sets(opts),
      do: ProviderHelper.list_sets(opts)
  end

  defmodule Admission do
    def admit(key), do: AdmissionHelper.admit(key)
  end

  defp cards(opts \\ []) do
    suffix = System.unique_integer([:positive])
    set = Core.import_card_set!(%{tcgdex_id: "sv1", name: "Set", series_id: "sv"})
    card = import_card(set, "a-card-#{suffix}", [matched?: true] ++ opts)
    next = import_card(set, "z-card-#{suffix}")
    {card, next}
  end

  defp import_card(set, id, opts \\ []) do
    source_payload =
      case Keyword.get(opts, :source_payload) do
        :matching_payload -> payload(id)
        value -> value
      end

    TcgCheap.TestSupport.import_card_printing!(
      %{
        tcgdex_id: id,
        name: "Brief",
        set_name: set.name,
        collector_number: "1",
        card_set_id: set.id,
        mapping_status: if(Keyword.get(opts, :matched?), do: "matched", else: "unmatched"),
        cardmarket_product_id: if(Keyword.get(opts, :matched?), do: 12),
        details_synced_at: Keyword.get(opts, :details_synced_at),
        source_payload: source_payload
      },
      scoped?: false
    )
  end

  defp payload(id),
    do: %{
      "id" => id,
      "name" => "Fetched #{id}",
      "localId" => "1",
      "set" => %{"id" => "sv1"},
      "pricing" => %{"cardmarket" => %{"unit" => "EUR", "idProduct" => 12, "avg7" => 2.5}}
    }

  defp job(card, continue?, id, attempt \\ 1),
    do: %Oban.Job{
      id: id,
      attempt: attempt,
      max_attempts: 5,
      worker: Oban.Worker.to_string(CardDetailEnrichmentWorker),
      queue: "catalogue_sync",
      args: %{
        "local_card_id" => card.id,
        "tcgdex_id" => card.tcgdex_id,
        "policy_version" => 1,
        "continue" => continue?
      }
    }

  defp restore(key, nil), do: Application.delete_env(:tcg_cheap, key)
  defp restore(key, value), do: Application.put_env(:tcg_cheap, key, value)
end
