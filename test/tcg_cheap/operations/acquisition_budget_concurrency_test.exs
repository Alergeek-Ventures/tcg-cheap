defmodule TcgCheap.Operations.AcquisitionBudgetConcurrencyTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.Operations
  alias TcgCheap.Operations.AcquisitionBudget
  alias TcgCheap.Repo

  test "independent concurrent admissions cannot exceed the cap" do
    previous = Application.get_env(:tcg_cheap, :acquisition_budget)
    key = "concurrent-provider-#{System.unique_integer([:positive])}"
    base = next_unused_base()

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 3,
      global_daily_request_limit: 3,
      global_monthly_spend_limit: "50.00",
      providers: [
        [
          provider_key: key,
          display_name: "Concurrent",
          estimated_cost_per_request: "0.00",
          hourly_request_limit: 3,
          daily_request_limit: 3,
          monthly_request_limit: 3,
          monthly_spend_limit: "50.00"
        ]
      ]
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:tcg_cheap, :acquisition_budget, previous),
        else: Application.delete_env(:tcg_cheap, :acquisition_budget)

      cleanup_providers([key])
    end)

    parent = self()

    tasks =
      for _ <- 1..8 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go ->
              Sandbox.unboxed_run(Repo, fn ->
                AcquisitionBudget.admit(key, clock: fn -> base end)
              end)
          end
        end)
      end

    for _ <- tasks, do: assert_receive({:ready, _}, 5_000)
    Enum.each(tasks, &send(&1.pid, :go))
    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.count(results, &match?({:ok, _}, &1)) == 3
    assert Enum.count(results, &match?({:error, :hourly_limit_reached}, &1)) == 5

    Sandbox.unboxed_run(Repo, fn ->
      provider = Operations.get_provider_by_key!(key)

      rows =
        Repo.query!(
          "SELECT window_kind, request_count FROM acquisition_budget_usages WHERE provider_id = $1",
          [Ecto.UUID.dump!(provider.id)]
        ).rows

      assert Enum.sort(rows) == [["day", 3], ["hour", 3], ["month", 3]]
    end)
  end

  test "concurrent admissions across providers cannot exceed global cap" do
    previous = Application.get_env(:tcg_cheap, :acquisition_budget)

    keys =
      for prefix <- ["concurrent-a", "concurrent-b"],
          do: "#{prefix}-#{System.unique_integer([:positive])}"

    base = next_unused_base()

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 3,
      global_daily_request_limit: 3,
      global_monthly_spend_limit: "50.00",
      providers:
        Enum.map(keys, fn key ->
          [
            provider_key: key,
            display_name: key,
            estimated_cost_per_request: "0.00",
            hourly_request_limit: 10,
            daily_request_limit: 10,
            monthly_request_limit: 10,
            monthly_spend_limit: "50.00"
          ]
        end)
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:tcg_cheap, :acquisition_budget, previous),
        else: Application.delete_env(:tcg_cheap, :acquisition_budget)

      cleanup_providers(keys)
    end)

    tasks =
      for index <- 1..8 do
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            AcquisitionBudget.admit(Enum.at(keys, rem(index, 2)),
              clock: fn -> base end
            )
          end)
        end)
      end

    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.count(results, &match?({:ok, _}, &1)) == 3
    assert Enum.count(results, &match?({:error, :global_hourly_limit_reached}, &1)) == 5
  end

  defp next_unused_base do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!(
        "SELECT COALESCE(MAX(window_started_at), '2000-01-01 00:00:00+00'::timestamptz) FROM acquisition_budget_usages"
      ).rows
      |> List.first()
      |> List.first()
      |> DateTime.add(86_400 * 20_000, :second)
      |> DateTime.truncate(:second)
    end)
  end

  defp cleanup_providers(keys) do
    Sandbox.unboxed_run(Repo, fn ->
      ids =
        Repo.query!("SELECT id FROM acquisition_data_providers WHERE provider_key = ANY($1)", [
          keys
        ]).rows
        |> Enum.map(&List.first/1)

      if ids != [] do
        Repo.query!("DELETE FROM acquisition_budget_usages WHERE provider_id = ANY($1)", [ids])
        Repo.query!("DELETE FROM acquisition_data_providers WHERE id = ANY($1)", [ids])
      end
    end)
  end
end
