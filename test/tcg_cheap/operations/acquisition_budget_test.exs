defmodule TcgCheap.Operations.AcquisitionBudgetTest do
  use TcgCheap.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.Operations
  alias TcgCheap.Operations.AcquisitionBudget

  setup do
    previous = Application.get_env(:tcg_cheap, :acquisition_budget)
    key = "test-provider-#{System.unique_integer([:positive])}"

    config = [
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [
        provider(key, hourly_request_limit: 2, daily_request_limit: 3, monthly_request_limit: 4)
      ]
    ]

    Application.put_env(:tcg_cheap, :acquisition_budget, config)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:tcg_cheap, :acquisition_budget, previous),
        else: Application.delete_env(:tcg_cheap, :acquisition_budget)
    end)

    {:ok, key: key, config: config}
  end

  test "admits within all request limits and persists all UTC windows", %{key: key} do
    now = next_unused_base()
    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> now end)
    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> now end)
    assert {:error, :hourly_limit_reached} = AcquisitionBudget.admit(key, clock: fn -> now end)

    provider = TcgCheap.Operations.get_provider_by_key!(key)

    rows =
      TcgCheap.Repo.query!(
        "SELECT window_kind, request_count FROM acquisition_budget_usages WHERE provider_id = $1",
        [Ecto.UUID.dump!(provider.id)]
      ).rows

    assert Enum.sort(rows) == Enum.sort([["day", 2], ["hour", 2], ["month", 2]])
  end

  test "microseconds do not split hourly or daily windows", %{key: key} do
    %DateTime{} = base = next_unused_base()
    first = %DateTime{base | microsecond: {123_456, 6}}
    second = %DateTime{base | microsecond: {654_321, 6}}

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [provider(key, hourly_request_limit: 1)]
    )

    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> first end)
    assert {:error, :hourly_limit_reached} = AcquisitionBudget.admit(key, clock: fn -> second end)
    assert usage_counts(key) == %{"day" => 1, "hour" => 1, "month" => 1}
  end

  test "rejects malformed configuration, options, and clocks", %{key: key, config: config} do
    assert {:error, :invalid_clock} = AcquisitionBudget.admit(key, ~U[2026-08-09 00:00:00Z])
    assert {:error, :invalid_clock} = AcquisitionBudget.admit(key, [:not_a_keyword])
    assert {:error, :invalid_clock} = AcquisitionBudget.admit(key, clock: nil)

    assert {:error, :invalid_clock} =
             AcquisitionBudget.admit(key, clock: fn -> DateTime.now!("Europe/Warsaw") end)

    assert {:error, :invalid_clock} = AcquisitionBudget.admit(key, clock: fn -> :bad end)
    assert {:error, :invalid_clock} = AcquisitionBudget.admit(key, clock: fn -> raise "boom" end)

    assert {:error, :invalid_clock} =
             AcquisitionBudget.admit(key,
               clock: fn -> DateTime.utc_now() end,
               clock: fn -> DateTime.utc_now() end
             )

    other_key = "other-provider-#{System.unique_integer([:positive])}"

    for invalid <- [
          [],
          [
            global_hourly_request_limit: 100,
            global_daily_request_limit: 1_000,
            global_monthly_spend_limit: "50.00",
            providers: []
          ],
          config ++ [providers: Keyword.fetch!(config, :providers)],
          Keyword.put(config, :unexpected, true),
          Keyword.put(config, :global_monthly_spend_limit, "not-a-decimal"),
          Keyword.put(config, :global_monthly_spend_limit, "NaN"),
          Keyword.put(config, :global_monthly_spend_limit, "Infinity"),
          Keyword.put(config, :global_monthly_spend_limit, "-1.00"),
          Keyword.put(config, :global_monthly_spend_limit, "50.01"),
          Keyword.put(config, :global_hourly_request_limit, 9_223_372_036_854_775_808),
          Keyword.put(config, :global_daily_request_limit, 9_223_372_036_854_775_808),
          Keyword.put(config, :providers, [provider(key, monthly_spend_limit: "51.00")]),
          Keyword.put(config, :providers, [provider(String.duplicate("k", 161))]),
          Keyword.put(config, :providers, [
            provider(key, display_name: String.duplicate("d", 241))
          ]),
          Keyword.put(config, :providers, [
            provider(key, estimated_cost_per_request: "1000000000")
          ]),
          Keyword.put(config, :providers, [
            provider(key, hourly_request_limit: 9_223_372_036_854_775_808)
          ]),
          Keyword.put(config, :providers, [
            provider(key, daily_request_limit: 9_223_372_036_854_775_808)
          ]),
          Keyword.put(config, :providers, [
            provider(key, monthly_request_limit: 9_223_372_036_854_775_808)
          ]),
          Keyword.put(config, :providers, [provider(" #{key}")]),
          Keyword.put(config, :providers, [provider(key, display_name: " Test Provider")]),
          Keyword.put(config, :providers, [provider(key, display_name: "   ")]),
          Keyword.put(config, :providers, [provider(key), provider(key)]),
          Keyword.put(config, :providers, [provider(key) ++ [provider_key: key]]),
          Keyword.put(config, :providers, [[:not_a_keyword]]),
          Keyword.put(config, :providers, [provider(key), provider(" #{other_key}")]),
          Keyword.put(config, :providers, [
            provider(key),
            provider(other_key, display_name: "Other ")
          ]),
          Keyword.put(config, :providers, [provider(key, hourly_request_limit: 21)]),
          Keyword.put(config, :providers, [provider(key, daily_request_limit: 31)]),
          Keyword.put(config, :providers, [provider(key, estimated_cost_per_request: "NaN")]),
          Keyword.put(config, :providers, [provider(key, estimated_cost_per_request: "Infinity")]),
          Keyword.put(config, :providers, [provider(key, estimated_cost_per_request: "-0.01")]),
          Keyword.put(config, :providers, [provider(key, monthly_spend_limit: "NaN")]),
          Keyword.put(config, :providers, [provider(key, monthly_spend_limit: "-0.01")]),
          [
            global_hourly_request_limit: 100,
            global_daily_request_limit: 1_000,
            global_monthly_spend_limit: "1.00",
            providers: [provider(key, monthly_spend_limit: "1.01")]
          ]
        ] do
      Application.put_env(:tcg_cheap, :acquisition_budget, invalid)
      assert {:error, :invalid_provider_configuration} = AcquisitionBudget.admit(key)
    end

    Application.delete_env(:tcg_cheap, :acquisition_budget)
    assert {:error, :invalid_provider_configuration} = AcquisitionBudget.admit(key)

    Application.put_env(:tcg_cheap, :acquisition_budget, config)
    assert {:error, :invalid_provider_configuration} = AcquisitionBudget.admit(other_key)
    assert {:ok, nil} = Operations.get_provider_by_key(key)
    assert usage_counts(key) == %{}
  end

  test "refresh preserves a disabled provider and adds no usage", %{key: key} do
    assert {:ok, _} = AcquisitionBudget.admit(key)
    provider = TcgCheap.Operations.get_provider_by_key!(key)
    Ash.update!(provider, %{}, action: :disable, authorize?: false)
    assert {:error, :provider_disabled} = AcquisitionBudget.admit(key)

    assert 3 ==
             TcgCheap.Repo.query!(
               "SELECT count(*) FROM acquisition_budget_usages WHERE provider_id = $1",
               [Ecto.UUID.dump!(provider.id)]
             ).rows
             |> List.first()
             |> List.first()
  end

  test "UTC month boundaries use separate monthly windows", %{key: key} do
    base = next_unused_month_boundary()

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "1.00",
      providers: [
        provider(key, estimated_cost_per_request: "1.00", monthly_spend_limit: "1.00")
      ]
    )

    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> base end)

    assert {:ok, _} =
             AcquisitionBudget.admit(key, clock: fn -> DateTime.add(base, 86_400, :second) end)

    provider = TcgCheap.Operations.get_provider_by_key!(key)

    assert 2 ==
             TcgCheap.Repo.query!(
               "SELECT count(*) FROM acquisition_budget_usages WHERE provider_id = $1 AND window_kind = 'month'",
               [Ecto.UUID.dump!(provider.id)]
             ).rows
             |> List.first()
             |> List.first()
  end

  test "enforces provider and global spend caps across providers", %{key: key} do
    second_key = "second-provider-#{System.unique_integer([:positive])}"
    base = next_unused_base()

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "1.00",
      providers: [
        provider(key, estimated_cost_per_request: "1.00", monthly_spend_limit: "1.00"),
        provider(second_key, estimated_cost_per_request: "1.00", monthly_spend_limit: "1.00")
      ]
    )

    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> base end)

    assert {:error, :global_monthly_spend_limit_reached} =
             AcquisitionBudget.admit(second_key, clock: fn -> base end)

    assert {:ok, nil} = Operations.get_provider_by_key(second_key)
    assert usage_counts(second_key) == %{}
  end

  test "enforces global hourly and daily request caps across providers", %{key: key} do
    second_key = "global-limit-provider-#{System.unique_integer([:positive])}"
    now = next_unused_base()

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 2,
      global_daily_request_limit: 3,
      global_monthly_spend_limit: "50.00",
      providers: [provider(key), provider(second_key)]
    )

    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> now end)
    assert {:ok, _} = AcquisitionBudget.admit(second_key, clock: fn -> now end)

    assert {:error, :global_hourly_limit_reached} =
             AcquisitionBudget.admit(key, clock: fn -> now end)

    next_hour = DateTime.add(now, 3_600, :second)
    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> next_hour end)

    assert {:error, :global_daily_limit_reached} =
             AcquisitionBudget.admit(second_key, clock: fn -> next_hour end)
  end

  test "pairs provider and global counters with their exact UTC windows", %{key: key} do
    base = next_unused_month_boundary()
    midnight = DateTime.add(base, 1, :second)
    later_hour = DateTime.add(midnight, 3_600, :second)
    next_day = DateTime.add(midnight, 86_400, :second)
    next_day_later_hour = DateTime.add(next_day, 3_600, :second)

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 1,
      global_daily_request_limit: 2,
      global_monthly_spend_limit: "50.00",
      providers: [provider(key, hourly_request_limit: 2, daily_request_limit: 2)]
    )

    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> midnight end)
    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> later_hour end)

    assert {:error, :global_hourly_limit_reached} =
             AcquisitionBudget.admit(key, clock: fn -> later_hour end)

    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> next_day end)
    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> next_day_later_hour end)

    assert {:error, :daily_limit_reached} =
             AcquisitionBudget.admit(key,
               clock: fn -> DateTime.add(next_day_later_hour, 3_600, :second) end
             )
  end

  test "independent daily, monthly request, and provider spend caps reject atomically", %{
    key: key
  } do
    base = next_unused_base()

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [
        provider(key,
          hourly_request_limit: 3,
          daily_request_limit: 3,
          monthly_request_limit: 4,
          monthly_spend_limit: "50.00"
        )
      ]
    )

    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> base end)

    assert {:ok, _} =
             AcquisitionBudget.admit(key, clock: fn -> DateTime.add(base, 3_600, :second) end)

    assert {:ok, _} =
             AcquisitionBudget.admit(key, clock: fn -> DateTime.add(base, 7_200, :second) end)

    assert {:error, :daily_limit_reached} =
             AcquisitionBudget.admit(key, clock: fn -> DateTime.add(base, 10_800, :second) end)

    assert usage_counts(key, month_start(base)) == %{
             "day" => 3,
             "hour" => 3,
             "month" => 3
           }

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [
        provider(key,
          hourly_request_limit: 1,
          daily_request_limit: 2,
          monthly_request_limit: 2,
          monthly_spend_limit: "50.00"
        )
      ]
    )

    second_base = DateTime.add(base, 86_400 * 31, :second)
    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> second_base end)

    assert {:ok, _} =
             AcquisitionBudget.admit(key,
               clock: fn -> DateTime.add(second_base, 86_400, :second) end
             )

    assert {:error, :monthly_request_limit_reached} =
             AcquisitionBudget.admit(key,
               clock: fn -> DateTime.add(second_base, 86_400 * 2, :second) end
             )

    assert usage_counts(key, month_start(second_base)) == %{
             "day" => 2,
             "hour" => 2,
             "month" => 2
           }

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [provider(key, estimated_cost_per_request: "0.75", monthly_spend_limit: "1.00")]
    )

    third_base = DateTime.add(base, 86_400 * 62, :second)
    assert {:ok, _} = AcquisitionBudget.admit(key, clock: fn -> third_base end)

    assert {:error, :provider_monthly_spend_limit_reached} =
             AcquisitionBudget.admit(key,
               clock: fn -> DateTime.add(third_base, 3_600, :second) end
             )

    assert usage_counts(key, month_start(third_base)) == %{
             "day" => 1,
             "hour" => 1,
             "month" => 1
           }
  end

  test "Ash and PostgreSQL reject incoherent provider limits" do
    key = "invalid-provider-#{System.unique_integer([:positive])}"

    assert {:error, %Ash.Error.Invalid{}} =
             Operations.register_provider(
               key,
               "Invalid Provider",
               Decimal.new("0"),
               3,
               2,
               4,
               Decimal.new("0")
             )

    assert {:error,
            %Postgrex.Error{
              postgres: %{constraint: "acquisition_data_providers_request_limit_order_invariant"}
            }} =
             TcgCheap.Repo.query(
               "INSERT INTO acquisition_data_providers (id, provider_key, display_name, estimated_cost_per_request, hourly_request_limit, daily_request_limit, monthly_request_limit, monthly_spend_limit) VALUES ($1, $2, 'Invalid Provider', 0, 3, 2, 4, 0)",
               [Ecto.UUID.dump!(Ecto.UUID.generate()), key]
             )
  end

  test "PostgreSQL rejects invalid budget usage values" do
    provider =
      Operations.register_provider!(
        "usage-provider-#{System.unique_integer([:positive])}",
        "Usage Provider",
        Decimal.new("0"),
        1,
        1,
        1,
        Decimal.new("0")
      )

    assert {:error,
            %Postgrex.Error{
              postgres: %{constraint: "acquisition_budget_usages_window_kind_invariant"}
            }} =
             TcgCheap.Repo.query(
               "INSERT INTO acquisition_budget_usages (id, provider_id, window_kind, window_started_at, request_count, estimated_spend_usd) VALUES ($1, $2, 'week', $3, 1, 0)",
               [
                 Ecto.UUID.dump!(Ecto.UUID.generate()),
                 Ecto.UUID.dump!(provider.id),
                 ~U[2026-08-09 00:00:00Z]
               ]
             )
  end

  defp provider(key, overrides \\ []) do
    Keyword.merge(
      [
        provider_key: key,
        display_name: "Test Provider",
        estimated_cost_per_request: "1.00",
        hourly_request_limit: 10,
        daily_request_limit: 20,
        monthly_request_limit: 30,
        monthly_spend_limit: "50.00"
      ],
      overrides
    )
  end

  defp usage_counts(provider_key, month_started_at \\ nil) do
    {month_filter, params} =
      if month_started_at do
        {" AND date_trunc('month', u.window_started_at) = $2", [provider_key, month_started_at]}
      else
        {"", [provider_key]}
      end

    TcgCheap.Repo.query!(
      "SELECT u.window_kind, u.request_count FROM acquisition_budget_usages u JOIN acquisition_data_providers p ON p.id = u.provider_id WHERE p.provider_key = $1" <>
        month_filter,
      params
    ).rows
    |> Enum.reduce(%{}, fn [kind, count], counts ->
      Map.update(counts, kind, count, &(&1 + count))
    end)
  end

  defp next_unused_base do
    Sandbox.unboxed_run(TcgCheap.Repo, fn ->
      TcgCheap.Repo.query!(
        "SELECT COALESCE(MAX(window_started_at), '2000-01-01 00:00:00+00'::timestamptz) FROM acquisition_budget_usages"
      ).rows
      |> List.first()
      |> List.first()
      |> DateTime.add(86_400 * 10_000, :second)
      |> DateTime.truncate(:second)
    end)
  end

  defp next_unused_month_boundary do
    next_unused_base()
    |> DateTime.to_date()
    |> Date.beginning_of_month()
    |> Date.add(32)
    |> Date.beginning_of_month()
    |> then(&DateTime.new!(&1, ~T[00:00:00], "Etc/UTC"))
    |> DateTime.add(-1, :second)
  end

  defp month_start(datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.beginning_of_month()
    |> then(&DateTime.new!(&1, ~T[00:00:00], "Etc/UTC"))
  end
end
