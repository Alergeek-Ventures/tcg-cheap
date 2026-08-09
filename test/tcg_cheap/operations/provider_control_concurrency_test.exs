defmodule TcgCheap.Operations.ProviderControlConcurrencyTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.Accounts.Admin
  alias TcgCheap.Operations
  alias TcgCheap.Operations.{AcquisitionBudget, Overview}
  alias TcgCheap.Repo

  test "concurrent transitions sharing one displayed version allow one update" do
    with_runtime(fn key, actor, provider ->
      version = persisted_updated_at(provider.id)

      results =
        concurrently([
          fn -> Overview.set_provider_status(actor, key, "disabled", version) end,
          fn -> Overview.set_provider_status(actor, key, "disabled", version) end
        ])

      assert Enum.count(results, &match?({:ok, %{status: "disabled"}}, &1)) == 1
      assert Enum.count(results, &match?({:error, _}, &1)) == 1

      assert Sandbox.unboxed_run(Repo, fn -> Operations.get_provider_by_key!(key).status end) ==
               "disabled"
    end)
  end

  test "admission and disable linearize without admitting after disable" do
    with_runtime(fn key, actor, provider ->
      version = persisted_updated_at(provider.id)
      base = next_unused_base()

      [admission, control] =
        concurrently([
          fn -> AcquisitionBudget.admit(key, clock: fn -> base end) end,
          fn -> Overview.set_provider_status(actor, key, "disabled", version) end
        ])

      assert {:ok, %{status: "disabled"}} = control
      assert admission == {:error, :provider_disabled} or match?({:ok, _}, admission)

      admitted_requests =
        Sandbox.unboxed_run(Repo, fn ->
          Repo.query!(
            "SELECT COALESCE(SUM(request_count), 0)::bigint FROM acquisition_budget_usages WHERE provider_id = $1 AND window_kind = 'hour' AND window_started_at = $2",
            [Ecto.UUID.dump!(provider.id), hour_start(base)]
          ).rows
          |> List.first()
          |> List.first()
        end)

      expected_requests = if match?({:ok, _}, admission), do: 1, else: 0
      assert admitted_requests == expected_requests

      assert Sandbox.unboxed_run(Repo, fn -> Operations.get_provider_by_key!(key).status end) ==
               "disabled"
    end)
  end

  defp with_runtime(test) do
    previous = Application.get_env(:tcg_cheap, :acquisition_budget)
    key = "control-race-#{System.unique_integer([:positive])}"

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [provider_config(key)]
    )

    {actor, provider} =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, %{rows: [[admin_id]]}} =
          Repo.query(
            "INSERT INTO admins (id, email, hashed_password) VALUES (gen_random_uuid(), $1, 'test') RETURNING id",
            ["admin-#{key}@example.test"]
          )

        provider =
          Operations.register_provider!(
            key,
            "Provider",
            Decimal.new(0),
            100,
            1_000,
            10_000,
            Decimal.new("50.00"),
            authorize?: false
          )

        {%Admin{id: admin_id}, provider}
      end)

    try do
      test.(key, actor, provider)
    after
      if is_nil(previous),
        do: Application.delete_env(:tcg_cheap, :acquisition_budget),
        else: Application.put_env(:tcg_cheap, :acquisition_budget, previous)

      cleanup(provider.id, actor.id)
    end
  end

  defp concurrently(functions) do
    parent = self()

    tasks =
      Enum.map(functions, fn function ->
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> Sandbox.unboxed_run(Repo, function)
          end
        end)
      end)

    for _ <- tasks, do: assert_receive({:ready, _pid}, 5_000)
    Enum.each(tasks, &send(&1.pid, :go))
    Enum.map(tasks, &Task.await(&1, 10_000))
  end

  defp persisted_updated_at(provider_id) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("SELECT updated_at FROM acquisition_data_providers WHERE id = $1", [
        Ecto.UUID.dump!(provider_id)
      ]).rows
      |> List.first()
      |> List.first()
    end)
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

  defp hour_start(%DateTime{} = now),
    do: DateTime.truncate(%DateTime{now | minute: 0, second: 0}, :second)

  defp cleanup(provider_id, admin_id) do
    Sandbox.unboxed_run(Repo, fn ->
      dumped_provider_id = Ecto.UUID.dump!(provider_id)

      Repo.query!("DELETE FROM acquisition_budget_usages WHERE provider_id = $1", [
        dumped_provider_id
      ])

      Repo.query!("DELETE FROM acquisition_data_providers WHERE id = $1", [dumped_provider_id])
      Repo.query!("DELETE FROM admins WHERE id = $1", [dump_uuid!(admin_id)])
    end)
  end

  defp dump_uuid!(<<_::binary-size(16)>> = id), do: id
  defp dump_uuid!(id), do: Ecto.UUID.dump!(id)

  defp provider_config(key),
    do: [
      provider_key: key,
      display_name: "Provider",
      estimated_cost_per_request: "0.00",
      hourly_request_limit: 100,
      daily_request_limit: 1_000,
      monthly_request_limit: 10_000,
      monthly_spend_limit: "50.00"
    ]
end
