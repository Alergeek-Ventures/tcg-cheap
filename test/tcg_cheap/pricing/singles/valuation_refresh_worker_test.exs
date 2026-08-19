defmodule TcgCheap.Pricing.Singles.ValuationRefreshWorkerTest do
  use TcgCheap.DataCase, async: false
  import Oban.Testing
  alias TcgCheap.Core
  alias TcgCheap.Pricing.Singles.{ValuationRefreshWorker, ValuationWorker}
  alias TcgCheap.Repo

  setup do
    previous = Application.get_env(:tcg_cheap, :acquisition_budget)
    Application.put_env(:tcg_cheap, :acquisition_budget, budget_config())

    on_exit(fn ->
      if previous,
        do: Application.put_env(:tcg_cheap, :acquisition_budget, previous),
        else: Application.delete_env(:tcg_cheap, :acquisition_budget)
    end)

    :ok
  end

  test "refresh enqueues only active matched missing or stale cards" do
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
             Enum.sort(Enum.map([missing, stale], & &1.tcgdex_id))

    refute Enum.any?(
             jobs,
             &(&1.args["tcgdex_id"] in [
                 expired.tcgdex_id,
                 unmatched.tcgdex_id,
                 fresh.tcgdex_id,
                 unscoped.tcgdex_id
               ])
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
      cardmarket_product_id: 100 + System.unique_integer([:positive])
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
