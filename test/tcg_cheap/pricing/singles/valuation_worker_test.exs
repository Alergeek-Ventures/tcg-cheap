defmodule TcgCheap.Pricing.Singles.ValuationWorkerTest do
  use TcgCheap.DataCase, async: false

  import Oban.Testing

  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.{ValuationAcquisition, ValuationWorker}

  defmodule ProviderStub do
    def fetch(card_id, _options) do
      pid = Application.fetch_env!(:tcg_cheap, :valuation_provider_stub)
      Agent.update(pid, &Map.update!(&1, :calls, fn calls -> calls + 1 end))

      case Agent.get(pid, & &1.mode) do
        :raise -> raise "stub failure"
        :throw -> throw(:stub_failure)
        :exit -> exit(:stub_failure)
        :malformed -> :not_a_provider_response
        {:error, reason} -> {:error, reason}
        mode -> {:ok, result(card_id, mode)}
      end
    end

    defp result(card_id, mode) do
      result = %TcgCheap.Pricing.Singles.TcgdexCardmarket.Result{
        card_id: card_id,
        value_eur: Decimal.new("12.34"),
        currency: :eur,
        policy_version: :tcgdex_cardmarket_v1,
        source: :tcgdex_cardmarket,
        source_metric: :avg7,
        fetched_at: ~U[2026-08-07 12:00:00Z],
        provider_updated_at: ~U[2026-08-07 11:00:00Z],
        cardmarket_product_id: 123
      }

      case mode do
        :mismatched_card -> %{result | card_id: "other-card"}
        :mismatched_policy -> %{result | policy_version: :other_policy}
        :mismatched_currency -> %{result | currency: :pln}
        :invalid_value -> %{result | value_eur: Decimal.new(0)}
        :invalid_product -> %{result | cardmarket_product_id: 0}
        _ -> result
      end
    end
  end

  setup do
    previous = Application.get_env(:tcg_cheap, :valuation_provider)
    previous_stub = Application.get_env(:tcg_cheap, :valuation_provider_stub)
    {:ok, stub} = Agent.start(fn -> %{mode: :success, calls: 0} end)

    Application.put_env(:tcg_cheap, :valuation_provider_stub, stub)

    Application.put_env(:tcg_cheap, :valuation_provider,
      adapter: ProviderStub,
      options: [deterministic: true]
    )

    on_exit(fn ->
      Application.put_env(:tcg_cheap, :valuation_provider, previous)
      Application.put_env(:tcg_cheap, :valuation_provider_stub, previous_stub)
      Agent.stop(stub)
    end)

    %{stub: stub}
  end

  test "enqueues one unique valuation and persists then broadcasts" do
    card = create_card()
    topic = ValuationAcquisition.topic(card.id)
    assert :ok = ValuationAcquisition.subscribe(card)

    assert {:ok, first} = ValuationAcquisition.enqueue(card)
    assert {:ok, second} = ValuationAcquisition.enqueue(card)
    assert first.id == second.id
    assert first.queue == "valuations"

    assert first.args == %{
             "local_card_id" => card.id,
             "tcgdex_id" => card.tcgdex_id,
             "policy_version" => "tcgdex_cardmarket_v1",
             "currency" => "EUR"
           }

    assert :ok = perform_job(test_job(first.args), [])
    assert {:ok, snapshot} = Core.get_current_single_valuation(card.id, "tcgdex_cardmarket_v1")
    assert Decimal.equal?(snapshot.value_eur, Decimal.new("12.34"))
    assert snapshot.source == "tcgdex_cardmarket"
    assert snapshot.source_metric == "avg7"

    assert_receive {:valuation_completed, %{card_printing_id: id, snapshot: event_snapshot}}, 500
    assert id == card.id
    assert event_snapshot.id == snapshot.id
    assert event_snapshot.value_eur == snapshot.value_eur
    refute_receive {:valuation_completed, _}, 50
    assert topic == ValuationAcquisition.topic(card)
  end

  test "a second successful perform replaces the current snapshot" do
    card = create_card()

    args = %{
      "local_card_id" => card.id,
      "tcgdex_id" => card.tcgdex_id,
      "policy_version" => "tcgdex_cardmarket_v1",
      "currency" => "EUR"
    }

    assert :ok = perform_job(test_job(args), [])
    assert :ok = perform_job(test_job(args), [])

    assert [first, second] =
             Core.list_single_valuation_history!(card.id, "tcgdex_cardmarket_v1")

    assert Enum.count([first, second], & &1.current?) == 1
    assert Enum.count([first, second], &(not &1.current?)) == 1
  end

  test "permanent provider errors and malformed results are cancelled", %{stub: stub} do
    permanent = [
      {:error, :not_found},
      {:error, :unavailable_pricing},
      {:error, {:unsupported_currency, :pln}},
      {:error, {:malformed_response, :bad_payload}},
      {:error, {:http_error, %{status: 400}}},
      {:error, {:decode_error, :bad_json}},
      {:error, :invalid_card_id},
      {:error, :invalid_options},
      :malformed,
      :mismatched_card,
      :mismatched_policy,
      :mismatched_currency,
      :invalid_value,
      :invalid_product
    ]

    Enum.each(permanent, fn mode ->
      card = create_card()
      Agent.update(stub, &Map.put(&1, :mode, mode))
      assert {:cancel, _reason} = perform_job(test_job(args(card)), [])
      assert {:ok, nil} = Core.get_current_single_valuation(card.id, "tcgdex_cardmarket_v1")
      refute_receive {:valuation_completed, _}, 10
    end)
  end

  test "transient provider errors are retryable", %{stub: stub} do
    transient = [
      {:error, :rate_limited},
      {:error, {:rate_limited, %{status: 429}}},
      {:error, :http_error},
      {:error, {:http_error, %{status: 503}}},
      {:error, :transport_error},
      {:error, {:transport_error, :econnrefused}},
      {:error, :timeout},
      {:error, {:timeout, 1}}
    ]

    Enum.each(transient, fn mode ->
      card = create_card()
      Agent.update(stub, &Map.put(&1, :mode, mode))
      assert {:error, reason} = perform_job(test_job(args(card)), [])

      assert reason in [:provider_transport_error, :provider_timeout] or
               match?({:provider_rate_limited, _}, reason) or
               match?({:provider_http_error, _}, reason)

      assert {:ok, nil} = Core.get_current_single_valuation(card.id, "tcgdex_cardmarket_v1")
    end)
  end

  test "callback raises, throws, and exits are stable retryable failures", %{stub: stub} do
    for mode <- [:raise, :throw, :exit] do
      card = create_card()
      Agent.update(stub, &Map.put(&1, :mode, mode))
      assert {:error, :provider_callback_failed} = perform_job(test_job(args(card)), [])
      assert {:ok, nil} = Core.get_current_single_valuation(card.id, "tcgdex_cardmarket_v1")
    end
  end

  test "permanent failures broadcast once after local card validation", %{stub: stub} do
    card = create_card()
    assert :ok = ValuationAcquisition.subscribe(card)
    Agent.update(stub, &Map.put(&1, :mode, {:error, :not_found}))

    assert {:cancel, :provider_not_found} = perform_job(test_job(args(card)), [])
    assert_receive {:valuation_failed, %{card_printing_id: id, reason: :provider_not_found}}, 500
    assert id == card.id
  end

  test "retryable failures broadcast only on the final attempt", %{stub: stub} do
    card = create_card()
    assert :ok = ValuationAcquisition.subscribe(card)
    Agent.update(stub, &Map.put(&1, :mode, {:error, :timeout}))

    assert {:error, :provider_timeout} = perform_job(test_job(args(card), 1, 5), [])
    refute_receive {:valuation_failed, _}, 20
    assert {:error, :provider_timeout} = perform_job(test_job(args(card), 5, 5), [])
    assert_receive {:valuation_failed, %{card_printing_id: id, reason: :provider_timeout}}, 500
    assert id == card.id
  end

  test "invalid provider configuration is cancelled without callback", %{stub: stub} do
    card = create_card()

    Application.put_env(:tcg_cheap, :valuation_provider,
      adapter: ProviderStub,
      options: [],
      unknown: true
    )

    assert {:cancel, :invalid_provider_configuration} = perform_job(test_job(args(card)), [])
    assert %{calls: 0} = Agent.get(stub, & &1)

    Application.put_env(:tcg_cheap, :valuation_provider,
      adapter: ProviderStub,
      options: [x: 1, x: 2]
    )

    assert {:cancel, :invalid_provider_configuration} = perform_job(test_job(args(card)), [])
    assert %{calls: 0} = Agent.get(stub, & &1)
  end

  test "invalid local cards are cancelled before provider invocation", %{stub: stub} do
    card = create_card()
    bad_args = %{args(card) | "local_card_id" => Ecto.UUID.generate()}
    assert {:cancel, :invalid_local_card} = perform_job(test_job(bad_args), [])

    assert {:cancel, :invalid_local_card} =
             perform_job(test_job(%{args(card) | "tcgdex_id" => "missing-card"}), [])

    assert %{calls: 0} = Agent.get(stub, & &1)
  end

  test "enqueue accepts a local TCGdex ID and rejects invalid input" do
    card = create_card()
    assert {:ok, job} = ValuationAcquisition.enqueue(card.tcgdex_id)
    assert job.args["tcgdex_id"] == card.tcgdex_id
    assert {:error, :invalid_local_card} = ValuationAcquisition.enqueue("missing-card")
    assert {:error, :invalid_local_card} = ValuationAcquisition.enqueue(%{})
  end

  test "enqueue_if_stale enqueues missing and stale, but skips fresh at the seven-day boundary" do
    missing = create_card()
    now = ~U[2026-08-14 12:00:00Z]

    assert {:enqueued, _job} =
             ValuationAcquisition.enqueue_if_stale(missing, clock: fn -> now end)

    fresh = create_card()
    record_snapshot(fresh, ~U[2026-08-07 12:00:01Z])

    assert {:fresh, _snapshot} =
             ValuationAcquisition.enqueue_if_stale(fresh, clock: fn -> now end)

    boundary = create_card()
    record_snapshot(boundary, ~U[2026-08-07 12:00:00Z])

    assert {:enqueued, _job} =
             ValuationAcquisition.enqueue_if_stale(boundary, clock: fn -> now end)
  end

  test "subscribe_and_request subscribes before returning the freshness result" do
    card = create_card()

    assert {:ok, returned_card, {:enqueued, _job}} =
             ValuationAcquisition.subscribe_and_request(card.tcgdex_id,
               clock: fn -> ~U[2026-08-14 12:00:00Z] end
             )

    assert returned_card.id == card.id
    assert :ok = perform_job(test_job(args(card)), [])
    assert_receive {:valuation_completed, %{card_printing_id: id}}, 500
    assert id == card.id
  end

  test "real Oban draining completes the queued job and persists its snapshot" do
    card = create_card()
    assert {:ok, job} = ValuationAcquisition.enqueue(card)
    assert %{success: 1} = Oban.drain_queue(queue: :valuations)
    assert {:ok, snapshot} = Core.get_current_single_valuation(card.id, "tcgdex_cardmarket_v1")
    assert snapshot.card_printing_id == card.id
    assert %Oban.Job{state: "completed"} = TcgCheap.Repo.get!(Oban.Job, job.id)
  end

  test "unique options cover active states but completed jobs are not included" do
    options = ValuationWorker.new(args(create_card())).changes.unique
    assert options.keys == [:local_card_id, :tcgdex_id, :policy_version]
    assert :available in options.states
    assert :scheduled in options.states
    assert :executing in options.states
    assert :retryable in options.states
    refute :completed in options.states
  end

  defp create_card do
    suffix = System.unique_integer([:positive])

    Core.create_card_printing!(%{
      tcgdex_id: "base1-4-worker-#{suffix}",
      name: "Charizard",
      set_name: "Base Set",
      collector_number: "4"
    })
  end

  defp test_job(args) do
    test_job(args, 1, 5)
  end

  defp test_job(args, attempt, max_attempts) do
    now = DateTime.utc_now()

    %Oban.Job{
      args: args,
      worker: Atom.to_string(ValuationWorker),
      queue: "valuations",
      max_attempts: max_attempts,
      attempt: attempt,
      scheduled_at: now,
      attempted_at: now,
      inserted_at: now
    }
  end

  defp args(card) do
    %{
      "local_card_id" => card.id,
      "tcgdex_id" => card.tcgdex_id,
      "policy_version" => "tcgdex_cardmarket_v1",
      "currency" => "EUR"
    }
  end

  defp record_snapshot(card, fetched_at) do
    Core.record_single_valuation!(%{
      card_printing_id: card.id,
      value_eur: Decimal.new("12.34"),
      policy_version: "tcgdex_cardmarket_v1",
      source: "tcgdex_cardmarket",
      source_metric: "avg7",
      fetched_at: fetched_at
    })
  end
end
