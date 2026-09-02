defmodule TcgCheap.Pricing.Singles.ValuationRefreshWorkerTest do
  use TcgCheap.DataCase, async: false
  import Oban.Testing
  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.{ValuationRefreshWorker, ValuationWorker}
  alias TcgCheap.Repo

  defmodule ProviderStub do
    def fetch(card_id, options) do
      with :ok <- Keyword.fetch!(options, :request_admitter).() do
        stub = Application.fetch_env!(:tcg_cheap, :valuation_provider_stub)
        Agent.update(stub, &Map.update!(&1, :calls, fn calls -> calls + 1 end))
        fetched_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        {:ok,
         %TcgCheap.Pricing.Singles.TcgdexCardmarket.Result{
           card_id: card_id,
           value_eur: Decimal.new("12.34"),
           currency: :eur,
           policy_version: :tcgdex_cardmarket_v1,
           source: :tcgdex_cardmarket,
           source_metric: :avg7,
           fetched_at: fetched_at,
           provider_updated_at: DateTime.add(fetched_at, -3600, :second),
           cardmarket_product_id: 123
         }}
      end
    end
  end

  setup do
    previous = Application.get_env(:tcg_cheap, :acquisition_budget)
    previous_provider = Application.get_env(:tcg_cheap, :valuation_provider)
    previous_stub = Application.get_env(:tcg_cheap, :valuation_provider_stub)
    {:ok, stub} = Agent.start(fn -> %{mode: :success, calls: 0} end)
    Application.put_env(:tcg_cheap, :acquisition_budget, budget_config())
    Application.put_env(:tcg_cheap, :valuation_provider_stub, stub)
    Application.put_env(:tcg_cheap, :valuation_provider, adapter: ProviderStub, options: [])

    on_exit(fn ->
      if previous,
        do: Application.put_env(:tcg_cheap, :acquisition_budget, previous),
        else: Application.delete_env(:tcg_cheap, :acquisition_budget)

      restore_env(:valuation_provider, previous_provider)
      restore_env(:valuation_provider_stub, previous_stub)
      Agent.stop(stub)
    end)

    %{stub: stub}
  end

  defp restore_env(key, nil), do: Application.delete_env(:tcg_cheap, key)
  defp restore_env(key, value), do: Application.put_env(:tcg_cheap, key, value)

  test "daily refresh enqueues fresh card and child creates a second snapshot", %{stub: stub} do
    card =
      TcgCheap.TestSupport.import_card_printing!(
        Map.put(attrs("fresh-child"), :cardmarket_product_id, 123),
        expires_on: ~D[2027-01-01]
      )

    Core.record_single_valuation!(%{
      card_printing_id: card.id,
      value_eur: Decimal.new("1.00"),
      policy_version: "tcgdex_cardmarket_v1",
      source: "tcgdex_cardmarket",
      source_metric: "avg7",
      fetched_at: DateTime.utc_now(),
      cardmarket_product_id: 123
    })

    assert provider_usage_count() == 0
    assert :ok = ValuationRefreshWorker.perform(%Oban.Job{args: %{}})
    assert provider_usage_count() == 0
    assert [job] = all_enqueued(repo: TcgCheap.Repo, worker: ValuationWorker)

    assert :ok =
             perform_job(
               %Oban.Job{
                 args: job.args,
                 worker: "TcgCheap.Pricing.Singles.ValuationWorker",
                 inserted_at: DateTime.utc_now(),
                 scheduled_at: DateTime.utc_now(),
                 attempted_at: DateTime.utc_now(),
                 attempt: 1,
                 max_attempts: 5
               },
               []
             )

    assert %{calls: 1} = Agent.get(stub, & &1)
    # One admitted request materializes the hour/day/month budget windows.
    assert provider_usage_count() == 3

    assert {:ok, %{value_eur: value}} =
             Core.get_current_single_valuation(card.id, "tcgdex_cardmarket_v1")

    assert Decimal.equal?(value, Decimal.new("12.34"))
    assert [_, _] = Core.list_single_valuation_history!(card.id, "tcgdex_cardmarket_v1")
  end

  test "refresh enqueues every active matched candidate, including fresh cards" do
    missing = candidate("missing", ~D[2027-01-01])
    stale = candidate("stale", ~D[2027-01-01])
    fresh = candidate("fresh", ~D[2027-01-01])
    unscoped = TcgCheap.TestSupport.import_card_printing!(attrs("unscoped"), scoped?: false)
    expired = candidate("expired", ~D[2026-08-18])

    unmatched =
      TcgCheap.TestSupport.import_card_printing!(
        Map.merge(attrs("unmatched"), %{mapping_status: "unmatched", cardmarket_product_id: nil}),
        expires_on: ~D[2027-01-01]
      )

    Core.record_single_valuation!(%{
      card_printing_id: stale.id,
      value_eur: Decimal.new("1.00"),
      policy_version: "tcgdex_cardmarket_v1",
      source: "tcgdex_cardmarket",
      source_metric: "avg7",
      fetched_at: DateTime.add(DateTime.utc_now(), -8 * 86_400, :second),
      cardmarket_product_id: stale.cardmarket_product_id
    })

    Core.record_single_valuation!(%{
      card_printing_id: fresh.id,
      value_eur: Decimal.new("1.00"),
      policy_version: "tcgdex_cardmarket_v1",
      source: "tcgdex_cardmarket",
      source_metric: "avg7",
      fetched_at: DateTime.utc_now(),
      cardmarket_product_id: fresh.cardmarket_product_id
    })

    before_usage_count = provider_usage_count()
    assert unscoped.collection_scopes == []
    assert :ok = ValuationRefreshWorker.perform(%Oban.Job{args: %{}})
    jobs = all_enqueued(repo: TcgCheap.Repo, worker: ValuationWorker)

    assert Enum.map(jobs, & &1.args["tcgdex_id"]) |> Enum.sort() ==
             Enum.sort(Enum.map([missing, stale, fresh, expired, unscoped], & &1.tcgdex_id))

    refute Enum.any?(
             jobs,
             &(&1.args["tcgdex_id"] in [unmatched.tcgdex_id])
           )

    assert provider_usage_count() == before_usage_count
  end

  test "refresh jobs remain unique when run twice" do
    card = candidate("duplicate", ~D[2027-01-01])
    assert :ok = ValuationRefreshWorker.perform(%Oban.Job{args: %{}})
    assert :ok = ValuationRefreshWorker.perform(%Oban.Job{args: %{}})
    assert [job] = all_enqueued(repo: TcgCheap.Repo, worker: ValuationWorker)
    assert job.args["tcgdex_id"] == card.tcgdex_id
  end

  defp candidate(label, expires),
    do: TcgCheap.TestSupport.import_card_printing!(attrs(label), expires_on: expires)

  defp attrs(label),
    do: %{
      tcgdex_id: "sv-refresh-#{label}-#{System.unique_integer([:positive])}",
      name: "Refresh #{label}",
      set_name: "Set",
      collector_number: "1",
      mapping_status: "matched",
      cardmarket_product_id: 100 + System.unique_integer([:positive]),
      card_set_id:
        Core.import_card_set!(%{
          tcgdex_id: "set-#{label}-#{System.unique_integer([:positive])}",
          name: "Set #{label}",
          series_id: "sv"
        }).id
    }

  defp budget_config,
    do: [
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1000,
      global_monthly_spend_limit: "50.00",
      providers: [
        [
          provider_key: "tcgdex_cardmarket",
          display_name: "TCGdex",
          estimated_cost_per_request: "0.00",
          hourly_request_limit: 100,
          daily_request_limit: 1000,
          monthly_request_limit: 20_000,
          monthly_spend_limit: "0.00"
        ]
      ]
    ]

  defp provider_usage_count do
    %{rows: [[count]]} =
      Repo.query!("""
      SELECT count(*)
      FROM acquisition_budget_usages u
      JOIN acquisition_data_providers p ON p.id = u.provider_id
      WHERE p.provider_key = 'tcgdex_cardmarket'
      """)

    count
  end
end
