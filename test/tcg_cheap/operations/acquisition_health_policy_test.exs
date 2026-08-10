defmodule TcgCheap.Operations.AcquisitionHealthPolicyTest do
  use ExUnit.Case, async: false

  alias TcgCheap.Operations.AcquisitionHealthPolicy

  setup do
    previous = Application.get_env(:tcg_cheap, :acquisition_health)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:tcg_cheap, :acquisition_health),
        else: Application.put_env(:tcg_cheap, :acquisition_health, previous)
    end)

    :ok
  end

  test "strictly normalizes the configured policy" do
    assert {:ok, policy} = AcquisitionHealthPolicy.load()
    assert policy.reconcile_limit == 100
    assert policy.circuit_breaker_failure_threshold == 5
    assert policy.stale_after_seconds == %{"nbp" => 129_600}
    assert {:ok, ^policy} = AcquisitionHealthPolicy.validate_provider_keys(policy, ["nbp"])

    assert {:error, :invalid_acquisition_health_configuration} =
             AcquisitionHealthPolicy.validate_provider_keys(policy, ["tcgdex_cardmarket"])

    Application.put_env(:tcg_cheap, :acquisition_health,
      stranded_after_seconds: 0,
      reconcile_limit: 1,
      stale_after_seconds: %{}
    )

    assert {:error, :invalid_acquisition_health_configuration} = AcquisitionHealthPolicy.load()
  end

  test "classifies only fixed provider failure categories as circuit eligible" do
    for category <- ["rate_limit", "timeout", "transport", "provider_response"],
        do: assert(AcquisitionHealthPolicy.circuit_eligible_category?(category))

    for category <- ["budget", "persistence", "configuration", "local_input", "unknown", nil],
        do: refute(AcquisitionHealthPolicy.circuit_eligible_category?(category))
  end

  test "uses exact boundaries and rejects future or non-UTC successes" do
    now = ~U[2026-08-10 12:00:00Z]
    threshold = 900

    assert AcquisitionHealthPolicy.overdue?(
             DateTime.add(now, -threshold, :second),
             now,
             threshold
           )

    refute AcquisitionHealthPolicy.overdue?(
             DateTime.add(now, -threshold + 1, :second),
             now,
             threshold
           )

    policy = %{stale_after_seconds: %{"nbp" => 3_600}}
    assert AcquisitionHealthPolicy.provider_state(policy, "nbp", nil, now) == :not_observed

    assert AcquisitionHealthPolicy.provider_state(
             policy,
             "nbp",
             DateTime.add(now, -3_600, :second),
             now
           ) == :stale

    assert AcquisitionHealthPolicy.provider_state(
             policy,
             "nbp",
             DateTime.add(now, 1, :second),
             now
           ) == :invalid

    assert AcquisitionHealthPolicy.provider_state(policy, "other", nil, now) == :on_demand
    refute AcquisitionHealthPolicy.overdue?(DateTime.add(now, 1, :second), now, threshold)

    non_utc_now = %{now | time_zone: "Europe/Warsaw", zone_abbr: "CEST"}
    assert AcquisitionHealthPolicy.provider_state(policy, "nbp", nil, non_utc_now) == :invalid

    assert AcquisitionHealthPolicy.provider_state(
             policy,
             "nbp",
             DateTime.add(now, -3_600, :second),
             now
           ) == :stale
  end

  test "rejects unknown keys, duplicate keys, invalid values, and normalized collisions" do
    valid = [
      stranded_after_seconds: 900,
      reconcile_limit: 1,
      circuit_breaker_failure_threshold: 5,
      stale_after_seconds: %{}
    ]

    for config <- [
          Keyword.delete(valid, :circuit_breaker_failure_threshold),
          Keyword.put(valid, :circuit_breaker_failure_threshold, 0),
          Keyword.put(valid, :circuit_breaker_failure_threshold, 101),
          valid ++ [circuit_breaker_failure_threshold: 5],
          valid ++ [extra: true]
        ] do
      Application.put_env(:tcg_cheap, :acquisition_health, config)
      assert {:error, :invalid_acquisition_health_configuration} = AcquisitionHealthPolicy.load()
    end

    invalid = [
      [
        stranded_after_seconds: 900,
        reconcile_limit: 1,
        circuit_breaker_failure_threshold: 5,
        stale_after_seconds: %{},
        extra: true
      ],
      [
        stranded_after_seconds: 900,
        reconcile_limit: 1,
        circuit_breaker_failure_threshold: 5,
        stale_after_seconds: %{"nbp" => 1},
        reconcile_limit: 2
      ],
      [
        stranded_after_seconds: 900,
        reconcile_limit: 1,
        circuit_breaker_failure_threshold: 5,
        stale_after_seconds: %{" nbp " => 1}
      ],
      %{
        stranded_after_seconds: 900,
        reconcile_limit: 0,
        circuit_breaker_failure_threshold: 5,
        stale_after_seconds: %{}
      },
      %{
        stranded_after_seconds: 900,
        reconcile_limit: 1,
        circuit_breaker_failure_threshold: 5,
        stale_after_seconds: %{"nbp" => 31_536_001}
      },
      :invalid
    ]

    for config <- invalid do
      Application.put_env(:tcg_cheap, :acquisition_health, config)
      assert {:error, :invalid_acquisition_health_configuration} = AcquisitionHealthPolicy.load()
    end
  end
end
