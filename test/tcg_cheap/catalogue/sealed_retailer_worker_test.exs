defmodule TcgCheap.Catalogue.SealedRetailerWorkerTestAdapter do
  alias TcgCheap.Catalogue.SealedRetailerAdapter

  def source_key, do: "worker-stub"

  def fetch_listings(_, options) do
    with :ok <- Keyword.fetch!(options, :request_admitter).(), do: fetch_admitted()
  end

  defp fetch_admitted do
    if pid = Application.get_env(:tcg_cheap, :sealed_retailer_worker_test_stub),
      do: Agent.update(pid, &Map.update!(&1, :calls, fn calls -> calls + 1 end))

    case Application.fetch_env!(:tcg_cheap, :sealed_retailer_worker_test_mode) do
      :success -> {:ok, [listing()]}
      :raise -> raise "worker adapter failed"
      :throw -> throw(:worker_adapter_failed)
      :exit -> exit(:worker_adapter_failed)
      :batch -> {:ok, [:not_a_listing]}
      {:error, reason} -> {:error, reason}
      value -> value
    end
  end

  defp listing do
    now = ~U[2026-08-09 12:00:00Z]

    %SealedRetailerAdapter.Listing{
      source_listing_id: "worker-listing",
      source_title: "Worker Booster",
      direct_url: "https://example.test/worker-listing",
      current_price_pln: Decimal.new("12.34"),
      currency: "PLN",
      stock_status: "in_stock",
      first_seen_at: now,
      last_seen_at: now,
      last_checked_at: now,
      source_payload: %{"fixture" => true}
    }
  end
end

defmodule TcgCheap.Catalogue.SealedRetailerWorkerSourceOnlyAdapter do
  def source_key, do: "worker-stub"
end

defmodule TcgCheap.Catalogue.SealedRetailerWorkerUnsafeKeyAdapter do
  def source_key, do: "worker stub"

  defdelegate fetch_listings(retailer, options),
    to: TcgCheap.Catalogue.SealedRetailerWorkerTestAdapter
end

defmodule TcgCheap.Catalogue.SealedRetailerWorkerTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Catalogue.{SealedRetailerAcquisition, SealedRetailerWorker}
  alias TcgCheap.Core

  defmodule BudgetStub do
    def admit(_provider_key),
      do: Application.fetch_env!(:tcg_cheap, :sealed_retailer_budget_stub_result)
  end

  setup do
    TcgCheap.Repo.delete_all("import_issues")
    previous_adapters = Application.get_env(:tcg_cheap, :sealed_retailer_adapters)
    previous_mode = Application.get_env(:tcg_cheap, :sealed_retailer_worker_test_mode)
    previous_budget = Application.get_env(:tcg_cheap, :acquisition_budget)
    previous_health = Application.get_env(:tcg_cheap, :acquisition_health)
    previous_admitter = Application.get_env(:tcg_cheap, :acquisition_budget_admitter)
    previous_budget_result = Application.get_env(:tcg_cheap, :sealed_retailer_budget_stub_result)
    previous_stub = Application.get_env(:tcg_cheap, :sealed_retailer_worker_test_stub)
    {:ok, stub} = Agent.start_link(fn -> %{calls: 0} end)

    Application.put_env(:tcg_cheap, :sealed_retailer_adapters, %{
      "worker-stub" => %{adapter: TcgCheap.Catalogue.SealedRetailerWorkerTestAdapter, options: []}
    })

    Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_mode, :success)
    Application.put_env(:tcg_cheap, :acquisition_budget, budget_config())
    Application.put_env(:tcg_cheap, :acquisition_health, health_config())
    Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_stub, stub)

    on_exit(fn ->
      restore_env(:sealed_retailer_adapters, previous_adapters)
      restore_env(:sealed_retailer_worker_test_mode, previous_mode)
      restore_env(:acquisition_budget, previous_budget)
      restore_env(:acquisition_health, previous_health)
      restore_env(:acquisition_budget_admitter, previous_admitter)
      restore_env(:sealed_retailer_budget_stub_result, previous_budget_result)
      restore_env(:sealed_retailer_worker_test_stub, previous_stub)
      if Process.alive?(stub), do: Agent.stop(stub)
    end)

    retailer =
      Core.register_retailer!(%{
        slug: "worker-#{System.unique_integer([:positive])}",
        source_key: "worker-stub",
        name: "Worker Shop",
        category: "regular_retailer",
        homepage_url: "https://example.test"
      })

    %{retailer: retailer, stub: stub}
  end

  defp health_config,
    do: [
      stranded_after_seconds: 900,
      reconcile_limit: 100,
      circuit_breaker_failure_threshold: 100,
      stale_after_seconds: %{}
    ]

  test "enqueues a unique canonical job", %{retailer: retailer} do
    assert {:ok, job} = SealedRetailerAcquisition.enqueue(retailer.id, retailer.source_key)
    assert job.queue == "sealed_retailers"
    assert job.args == args(retailer)

    assert {:ok, %{conflict?: true, id: duplicate_id}} =
             SealedRetailerAcquisition.enqueue(retailer.id, retailer.source_key)

    assert duplicate_id == job.id
  end

  test "performs a configured refresh and persists one observation", %{retailer: retailer} do
    assert :ok = SealedRetailerWorker.perform(job(retailer))
    assert usage_counts("sealed_retailer:worker-stub") == %{"day" => 1, "hour" => 1, "month" => 1}
    assert {:ok, [listing]} = Core.list_active_retailer_listings(retailer.id)
    assert listing.source_listing_id == "worker-listing"
    assert {:ok, [_observation]} = Core.list_sealed_listing_observation_history(listing.id)
    run = latest_run("sealed_retailer:worker-stub")
    assert run.operation == "sealed_retailer_refresh"
    assert run.target_key == retailer.id
    assert run.status == "succeeded"
    assert run.request_count == 1
    assert source_health("sealed_retailer:worker-stub").last_status == "succeeded"
  end

  test "a capped provider is rejected before the adapter", %{retailer: retailer, stub: stub} do
    assert :ok = SealedRetailerWorker.perform(job(retailer))
    provider = TcgCheap.Operations.get_provider_by_key!("sealed_retailer:worker-stub")
    TcgCheap.Operations.disable_provider!(provider, provider.updated_at, authorize?: false)

    assert {:cancel, {:acquisition_budget_rejected, :provider_disabled}} =
             SealedRetailerWorker.perform(job(retailer))

    assert %{calls: 1} = Agent.get(stub, & &1)
  end

  test "budget persistence failure is retryable without adapter invocation", %{
    retailer: retailer,
    stub: stub
  } do
    Application.put_env(:tcg_cheap, :acquisition_budget_admitter, BudgetStub)

    Application.put_env(:tcg_cheap, :sealed_retailer_budget_stub_result, {
      :error,
      :budget_persistence_failed
    })

    assert {:error, :budget_persistence_failed} = SealedRetailerWorker.perform(job(retailer))
    assert %{calls: 0} = Agent.get(stub, & &1)
    assert usage_counts("sealed_retailer:worker-stub") == %{}
  end

  test "timestamped budget rejection remains a budget cancellation", %{
    retailer: retailer,
    stub: stub
  } do
    Application.put_env(:tcg_cheap, :acquisition_budget_admitter, BudgetStub)

    Application.put_env(
      :tcg_cheap,
      :sealed_retailer_budget_stub_result,
      {:error, {:acquisition_budget_rejected, :provider_disabled, ~U[2026-09-02 00:00:00Z]}}
    )

    assert {:cancel, {:acquisition_budget_rejected, :provider_disabled}} =
             SealedRetailerWorker.perform(job(retailer))

    assert %{calls: 0} = Agent.get(stub, & &1)
  end

  test "malformed admission configuration fails closed without usage", %{
    retailer: retailer,
    stub: stub
  } do
    Application.put_env(:tcg_cheap, :acquisition_budget_admitter, String)

    assert {:cancel, {:acquisition_budget_rejected, :invalid_admission_configuration}} =
             SealedRetailerWorker.perform(job(retailer))

    assert %{calls: 0} = Agent.get(stub, & &1)
    assert usage_counts("sealed_retailer:worker-stub") == %{}
  end

  test "cancels malformed, forged, and disabled jobs before calling the adapter", %{
    retailer: retailer
  } do
    assert {:cancel, :malformed_job_args} = SealedRetailerWorker.perform(%Oban.Job{args: %{}})

    assert {:cancel, :malformed_job_args} =
             SealedRetailerWorker.perform(%Oban.Job{
               args: %{"retailer_id" => "not-a-uuid", "source_key" => retailer.source_key}
             })

    forged_job = %{
      job(retailer)
      | args: %{
          "retailer_id" => Ecto.UUID.generate(),
          "source_key" => retailer.source_key
        }
    }

    assert {:cancel, :retailer_not_active_or_mismatched} =
             SealedRetailerWorker.perform(forged_job)

    forged_run = latest_run("sealed_retailer:worker-stub")
    assert forged_run.status == "cancelled"
    assert forged_run.failure_category == "local_input"

    disabled = Core.disable_retailer!(retailer)

    assert {:cancel, :retailer_not_active_or_mismatched} =
             SealedRetailerWorker.perform(job(disabled))

    assert {:ok, []} = Core.list_active_retailer_listings(retailer.id)
    assert usage_counts("sealed_retailer:worker-stub") == %{}
  end

  test "retries transient failures and returns the final failure", %{
    retailer: retailer,
    stub: stub
  } do
    for reason <- [
          :transport_error,
          {:transport_error, :closed},
          :timeout,
          {:timeout, 10_000},
          :rate_limited,
          {:rate_limited, %{status: 429}},
          {:http_error, %{status: 408}},
          {:http_error, %{status: 429}},
          {:http_error, %{status: 503}},
          :retailer_lookup_failed,
          :pagination_changed
        ] do
      Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_mode, {:error, reason})
      assert {:error, _reason} = SealedRetailerWorker.perform(job(retailer, 1, 5))
    end

    Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_mode, {
      :error,
      {:http_error, %{status: 503}}
    })

    assert {:error, {:http_error, 503}} = SealedRetailerWorker.perform(job(retailer, 5, 5))

    Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_mode, :raise)
    assert {:cancel, :adapter_exception} = SealedRetailerWorker.perform(job(retailer))

    Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_mode, :throw)
    assert {:cancel, :adapter_throw} = SealedRetailerWorker.perform(job(retailer))

    Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_mode, :exit)
    assert {:cancel, :adapter_exit} = SealedRetailerWorker.perform(job(retailer))

    Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_mode, {
      :error,
      {:rate_limited, %{status: 429, retry_after_seconds: 120}}
    })

    assert {:error, {:rate_limited, 120}} = SealedRetailerWorker.perform(job(retailer))
    assert %{calls: 16} = Agent.get(stub, & &1)

    assert usage_counts("sealed_retailer:worker-stub") == %{
             "day" => 16,
             "hour" => 16,
             "month" => 16
           }

    retry_after_job = %{
      job(retailer)
      | unsaved_error: %{
          reason: %Oban.PerformError{reason: {:rate_limited, 120}}
        }
    }

    assert SealedRetailerWorker.backoff(retry_after_job) == 120
    assert SealedRetailerWorker.backoff(job(retailer, 3, 5)) == 270
    assert SealedRetailerWorker.timeout(job(retailer)) == 360_000
  end

  test "drains a queued refresh and releases uniqueness after completion", %{retailer: retailer} do
    assert {:ok, first_job} = SealedRetailerAcquisition.enqueue(retailer.id, retailer.source_key)
    assert %{success: 1} = Oban.drain_queue(queue: :sealed_retailers)
    assert %{state: "completed"} = TcgCheap.Repo.get!(Oban.Job, first_job.id)
    assert {:ok, [listing]} = Core.list_active_retailer_listings(retailer.id)
    assert {:ok, [_observation]} = Core.list_sealed_listing_observation_history(listing.id)

    assert {:ok, second_job} = SealedRetailerAcquisition.enqueue(retailer.id, retailer.source_key)
    refute second_job.id == first_job.id
  end

  test "cancels permanent and malformed provider failures", %{retailer: retailer} do
    for reason <- [
          :malformed_json,
          :malformed_shape,
          :invalid_pagination
        ] do
      Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_mode, {:error, reason})
      assert {:cancel, ^reason} = SealedRetailerWorker.perform(job(retailer))
    end

    Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_mode, {
      :error,
      {:http_error, %{status: 404, response: "secret"}}
    })

    assert {:cancel, {:http_error, 404}} = SealedRetailerWorker.perform(job(retailer))

    Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_mode, :malformed)
    assert {:cancel, :malformed_provider_result} = SealedRetailerWorker.perform(job(retailer))
  end

  test "retains secret-safe transport, callback, and listing diagnostics", %{retailer: retailer} do
    for {mode, result, stage, kind, code} <- [
          {{:error, {:transport_error, "https://secret.example/token"}},
           {:error, :transport_error}, "retailer_fetch", "failed", "transport"},
          {:raise, {:cancel, :adapter_exception}, "retailer_fetch", "failed",
           "provider_response"},
          {{:error, {:http_error, %{status: 408}}}, {:error, {:http_error, 408}},
           "retailer_fetch", "failed", "timeout"},
          {{:error, {:http_error, %{status: 429}}}, {:error, {:http_error, 429}},
           "retailer_fetch", "failed", "rate_limit"},
          {:batch, {:cancel, :malformed_listing}, "listing_validation", "malformed",
           "malformed_response"},
          {{:error, {:malformed_listing, "https://secret.example/listing"}},
           {:cancel, :malformed_listing}, "listing_validation", "malformed",
           "malformed_response"},
          {{:error, {:provider_error, "https://secret.example/provider"}},
           {:cancel, :provider_failure}, "retailer_fetch", "failed", "unknown"}
        ] do
      Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_mode, mode)
      assert SealedRetailerWorker.perform(job(retailer)) == result
      assert {:ok, [issue]} = TcgCheap.Operations.list_admin_import_issues(authorize?: false)
      assert issue.stage == stage
      assert issue.issue_kind == kind
      assert issue.issue_code == code
      refute inspect(issue) =~ "secret.example"
      TcgCheap.Repo.delete_all("import_issues")
    end
  end

  test "repeated failures converge and malformed jobs retain no issue", %{retailer: retailer} do
    Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_mode, {:error, :transport_error})
    assert {:error, :transport_error} = SealedRetailerWorker.perform(job(retailer))
    assert {:error, :transport_error} = SealedRetailerWorker.perform(job(retailer))
    assert {:ok, issues} = TcgCheap.Operations.list_admin_import_issues(authorize?: false)
    assert length(issues) == 1

    TcgCheap.Repo.delete_all("import_issues")
    assert {:cancel, :malformed_job_args} = SealedRetailerWorker.perform(%Oban.Job{args: %{}})
    assert {:ok, []} = TcgCheap.Operations.list_admin_import_issues(authorize?: false)
  end

  test "falls back to a safe diagnostic provider for a legacy source key" do
    source_key = "worker stub"

    retailer =
      Core.register_retailer!(%{
        slug: "unsafe-worker-#{System.unique_integer([:positive])}",
        source_key: source_key,
        name: "Unsafe key worker",
        category: "regular_retailer",
        homepage_url: "https://example.test"
      })

    Application.put_env(:tcg_cheap, :sealed_retailer_adapters, %{
      source_key => %{
        adapter: TcgCheap.Catalogue.SealedRetailerWorkerUnsafeKeyAdapter,
        options: []
      }
    })

    Application.put_env(
      :tcg_cheap,
      :acquisition_budget,
      budget_config(provider_key: "sealed_retailer:" <> source_key)
    )

    Application.put_env(:tcg_cheap, :sealed_retailer_worker_test_mode, {
      :error,
      :transport_error
    })

    assert {:error, :transport_error} = SealedRetailerWorker.perform(job(retailer))
    assert {:ok, [issue]} = TcgCheap.Operations.list_admin_import_issues(authorize?: false)
    assert issue.provider_key == "sealed_retailer:other"
    assert issue.target_key == retailer.id
    refute inspect(issue) =~ source_key
  end

  test "rejects malformed or absent dynamic configuration before enqueue", %{retailer: retailer} do
    for config <- [
          %{},
          %{"worker-stub" => %{adapter: TcgCheap.Catalogue.SealedRetailerWorkerTestAdapter}},
          %{
            "worker-stub" => %{
              adapter: TcgCheap.Catalogue.SealedRetailerWorkerTestAdapter,
              options: [plug: nil, plug: Req]
            }
          },
          %{
            "worker-stub" => %{
              adapter: TcgCheap.Catalogue.SealedRetailerWorkerSourceOnlyAdapter,
              options: []
            }
          }
        ] do
      Application.put_env(:tcg_cheap, :sealed_retailer_adapters, config)

      assert {:error, :invalid_provider_configuration} =
               SealedRetailerAcquisition.enqueue(retailer.id, retailer.source_key)
    end

    assert usage_counts("sealed_retailer:worker-stub") == %{}
  end

  test "configures the queue without adding a sealed retailer refresh cron" do
    config = Application.fetch_env!(:tcg_cheap, Oban)
    assert Keyword.get(config, :queues)[:sealed_retailers] == 1

    crontab =
      config
      |> Keyword.get(:plugins)
      |> Enum.find_value(fn
        {Oban.Plugins.Cron, opts} -> opts[:crontab]
        _ -> nil
      end)

    assert Enum.any?(crontab, fn
             {"0 15 * * *", TcgCheap.Pricing.ExchangeRateWorker, _options} -> true
             _ -> false
           end)

    refute Enum.any?(crontab, fn {_schedule, worker, _options} ->
             worker == SealedRetailerWorker
           end)
  end

  defp args(retailer),
    do: %{"retailer_id" => retailer.id, "source_key" => retailer.source_key}

  defp job(retailer, attempt \\ 1, max_attempts \\ 5) do
    %Oban.Job{
      args: args(retailer),
      attempt: attempt,
      max_attempts: max_attempts,
      worker: Atom.to_string(SealedRetailerWorker),
      queue: "sealed_retailers"
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:tcg_cheap, key)
  defp restore_env(key, value), do: Application.put_env(:tcg_cheap, key, value)

  defp usage_counts(provider_key) do
    TcgCheap.Repo.query!(
      "SELECT u.window_kind, u.request_count FROM acquisition_budget_usages u JOIN acquisition_data_providers p ON p.id = u.provider_id WHERE p.provider_key = $1",
      [provider_key]
    ).rows
    |> Enum.reduce(%{}, fn [kind, count], acc -> Map.update(acc, kind, count, &(&1 + count)) end)
  end

  defp budget_config(opts \\ []) do
    [
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [
        [
          provider_key: Keyword.get(opts, :provider_key, "sealed_retailer:worker-stub"),
          display_name: "Worker Stub",
          estimated_cost_per_request: "0.00",
          hourly_request_limit: Keyword.get(opts, :hourly, 100),
          daily_request_limit: 1_000,
          monthly_request_limit: 20_000,
          monthly_spend_limit: "0.00"
        ]
      ]
    ]
  end

  defp latest_run(provider_key),
    do:
      TcgCheap.Operations.list_recent_acquisition_runs!([provider_key], 1, authorize?: false)
      |> hd()

  defp source_health(provider_key),
    do: TcgCheap.Operations.list_source_health!([provider_key], authorize?: false) |> hd()
end
