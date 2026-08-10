defmodule TcgCheapWeb.Admin.OperationsManualRefreshTestAdapter do
  def source_key, do: "web-manual-refresh"
  def fetch_listings(_retailer, _options), do: {:ok, []}
end

defmodule TcgCheapWeb.Admin.OperationsLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Oban.Testing
  import Phoenix.LiveViewTest

  alias AshAuthentication.Phoenix.Plug, as: AuthenticationPlug
  alias TcgCheap.Accounts
  alias TcgCheap.Catalogue.SealedRetailerWorker
  alias TcgCheap.Core
  alias TcgCheap.Operations
  alias TcgCheap.Operations.AcquisitionTracker
  alias TcgCheap.Pricing.ExchangeRateWorker
  alias TcgCheap.Pricing.Singles.ValuationWorker

  setup do
    previous = Application.get_env(:tcg_cheap, :acquisition_budget)
    previous_health = Application.get_env(:tcg_cheap, :acquisition_health)
    previous_adapters = Application.get_env(:tcg_cheap, :sealed_retailer_adapters)
    key = "web-ops-#{System.unique_integer([:positive])}"

    Application.put_env(:tcg_cheap, :acquisition_budget, budget_config(key))

    Application.put_env(:tcg_cheap, :acquisition_health,
      stranded_after_seconds: 900,
      reconcile_limit: 100,
      stale_after_seconds: %{}
    )

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:tcg_cheap, :acquisition_budget),
        else: Application.put_env(:tcg_cheap, :acquisition_budget, previous)

      if is_nil(previous_health),
        do: Application.delete_env(:tcg_cheap, :acquisition_health),
        else: Application.put_env(:tcg_cheap, :acquisition_health, previous_health)

      if is_nil(previous_adapters),
        do: Application.delete_env(:tcg_cheap, :sealed_retailer_adapters),
        else: Application.put_env(:tcg_cheap, :sealed_retailer_adapters, previous_adapters)
    end)

    {:ok, key: key}
  end

  test "unauthenticated operations access redirects to sign in", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/admin/operations")) == "/admin/sign-in"
  end

  test "authenticated page exposes operations structure and navigation", %{conn: conn} do
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")

    assert has_element?(view, "#admin-operations")
    assert has_element?(view, "#admin-operations-header-nav")
    assert has_element?(view, "#admin-operations-review-header-link")
    assert has_element?(view, "#admin-operations-products-header-link")
    assert has_element?(view, "#admin-operations-header-link")
    assert has_element?(view, "#operations-global-ledger")
    assert has_element?(view, "#operations-providers")
    assert has_element?(view, "#operations-acquisition-runs")
    assert has_element?(view, "#operations-retained-jobs")
    assert has_element?(view, "#operations-provider-stream[phx-update=stream]")
    assert has_element?(view, "#operations-run-stream[phx-update=stream]")
    assert has_element?(view, "#operations-job-stream[phx-update=stream]")
    assert has_element?(view, "#operations-manual-refresh")
    assert has_element?(view, "#manual-refresh-valuation-form")
    assert has_element?(view, "#manual-refresh-exchange-rate[phx-disable-with]")
    assert has_element?(view, "#manual-refresh-retailer-stream[phx-update=stream]")
    assert has_element?(view, "#manual-refresh-exchange-rate[disabled]")
    assert has_element?(view, "#manual-refresh-valuation[disabled]")
  end

  test "manual controls enqueue only the three canonical target shapes", %{conn: conn, key: key} do
    {card, retailer} = configure_manual_targets(key)
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")
    html = render(view)

    refute html =~ "retailer-source-secret"
    refute html =~ "OperationsManualRefreshTestAdapter"
    refute html =~ "adapter_options"

    view |> element("#manual-refresh-exchange-rate") |> render_click()

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: ExchangeRateWorker,
      args: %{
        "source" => "nbp",
        "table" => "A",
        "base_currency" => "EUR",
        "quote_currency" => "PLN"
      }
    )

    view
    |> form("#manual-refresh-valuation-form", manual_refresh: %{tcgdex_id: card.tcgdex_id})
    |> render_submit()

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: ValuationWorker,
      args: %{
        "local_card_id" => card.id,
        "tcgdex_id" => card.tcgdex_id,
        "policy_version" => "tcgdex_cardmarket_v1",
        "currency" => "EUR"
      }
    )

    view
    |> element("#manual-refresh-retailer-#{provider_id(retailer.id)}")
    |> render_click()

    assert_enqueued(
      repo: TcgCheap.Repo,
      worker: SealedRetailerWorker,
      args: %{"retailer_id" => retailer.id, "source_key" => "web-manual-refresh"}
    )

    view |> element("#manual-refresh-exchange-rate") |> render_click()
    assert has_element?(view, "#flash-info", "already queued")
  end

  test "manual valuation keeps invalid input and queues nothing", %{conn: conn, key: key} do
    configure_manual_targets(key)
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")
    invalid_id = "missing-manual-card"

    view
    |> form("#manual-refresh-valuation-form", manual_refresh: %{tcgdex_id: invalid_id})
    |> render_submit()

    assert has_element?(
             view,
             "#manual-refresh-valuation-form input[value='#{invalid_id}']"
           )

    assert has_element?(view, "#flash-error", "not queued")
    refute_enqueued(repo: TcgCheap.Repo, worker: ValuationWorker)
  end

  test "manual retailer event rejects a tampered local identifier", %{conn: conn, key: key} do
    configure_manual_targets(key)
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")

    render_click(view, "manual_sealed_retailer", %{"retailer-id" => Ecto.UUID.generate()})

    assert has_element?(view, "#flash-error", "not queued")
    refute_enqueued(repo: TcgCheap.Repo, worker: SealedRetailerWorker)
  end

  test "provider controls immediately disable the matching manual action", %{conn: conn, key: key} do
    configure_manual_targets(key)
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")

    refute has_element?(view, "#manual-refresh-exchange-rate[disabled]")
    view |> element("#provider-action-#{provider_id("nbp")}") |> render_click()
    assert has_element?(view, "#manual-refresh-exchange-rate[disabled]")
    assert has_element?(view, "#manual-refresh-exchange-rate-status", "DISABLED")
    refute_enqueued(repo: TcgCheap.Repo, worker: ExchangeRateWorker)
  end

  test "provider freshness has stable accessible identifiers", %{conn: conn, key: key} do
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")

    assert has_element?(view, "#provider-source-state-#{provider_id(key)}", "ON DEMAND")

    assert has_element?(
             view,
             "#provider-source-state-#{provider_id("other-#{key}")}",
             "ON DEMAND"
           )
  end

  test "running attempts beyond the boundary render as overdue", %{conn: conn, key: key} do
    Application.put_env(:tcg_cheap, :acquisition_health,
      stranded_after_seconds: 1,
      reconcile_limit: 100,
      stale_after_seconds: %{}
    )

    now = DateTime.utc_now()

    TcgCheap.Repo.query!(
      "INSERT INTO acquisition_runs (attempt_key, provider_key, operation, target_key, worker, queue, attempt, max_attempts, status, started_at) VALUES ($1, $2, 'single_valuation', 'overdue-target', 'TestWorker', 'ops', 1, 5, 'running', $3)",
      ["overdue-#{key}", key, DateTime.add(now, -2, :second)]
    )

    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")

    assert has_element?(view, "#operations-acquisition-runs", "OVERDUE")
  end

  test "tracked source health and safe acquisition evidence render", %{conn: conn, key: key} do
    job = %Oban.Job{
      id: System.unique_integer([:positive]),
      attempt: 1,
      max_attempts: 5,
      worker: "TcgCheap.TestWorker",
      queue: "valuations"
    }

    assert {:error, {:provider_rate_limited, "bearer-secret"}} =
             AcquisitionTracker.run(
               job,
               [
                 provider_key: key,
                 operation: "single_valuation",
                 target_key: "base1-4"
               ],
               fn _request_admitter -> {:error, {:provider_rate_limited, "bearer-secret"}} end
             )

    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")
    html = render(view)

    assert has_element?(view, "#operations-providers", "RETRYABLE FAILURE")
    assert has_element?(view, "#operations-acquisition-runs", "Rate limit")
    assert has_element?(view, "#operations-acquisition-runs", "base1-4")
    refute html =~ "bearer-secret"
  end

  test "configured unpersisted provider is honest and can be toggled", %{conn: conn, key: key} do
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")
    provider_id = provider_id(key)

    assert has_element?(view, "#provider-status-#{provider_id}", "ACTIVE ON FIRST USE")
    view |> element("#provider-action-#{provider_id}") |> render_click()
    assert has_element?(view, "#provider-status-#{provider_id}", "DISABLED")
    view |> element("#provider-action-#{provider_id}") |> render_click()
    assert has_element?(view, "#provider-status-#{provider_id}", "ACTIVE")
  end

  test "persisted provider and global totals render", %{conn: conn, key: key} do
    now = DateTime.utc_now()
    assert {:ok, _} = Operations.AcquisitionBudget.admit(key, clock: fn -> now end)
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")

    assert has_element?(view, "#operations-global-ledger", "1 / 100")
    assert has_element?(view, "#operations-providers", "1 / 10")
  end

  test "retained jobs expose safe projection only", %{conn: conn} do
    insert_job(
      "retryable",
      "secret-worker",
      "timeout bearer secret-error-token",
      "secret-args",
      "secret-meta"
    )

    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")
    html = render(view)
    document = LazyHTML.from_fragment(html)

    assert has_element?(view, "#operations-job-stream", "Timeout")
    refute LazyHTML.text(document) =~ "secret-error-token"
    refute LazyHTML.text(document) =~ "secret-args"
    refute LazyHTML.text(document) =~ "secret-meta"
  end

  test "stale displayed version cannot overwrite a newer active state", %{conn: conn, key: key} do
    assert {:ok, _} = Operations.AcquisitionBudget.admit(key)
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")
    provider_id = provider_id(key)
    version = element(view, "#provider-action-#{provider_id}") |> render() |> extract_version()

    assert {:ok, disabled} =
             Operations.Overview.set_provider_status(admin(), key, "disabled", version)

    assert {:ok, _active} =
             Operations.Overview.set_provider_status(
               admin(),
               key,
               "active",
               DateTime.to_iso8601(disabled.updated_at)
             )

    view
    |> element("#provider-action-#{provider_id}")
    |> render_click(%{"provider-key" => key, "version" => version})

    assert has_element?(view, "#provider-status-#{provider_id}", "ACTIVE")
  end

  test "invalid configuration is explicitly unavailable", %{conn: conn} do
    Application.put_env(:tcg_cheap, :acquisition_budget, [])
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")
    assert has_element?(view, "#operations-unavailable")
    refute has_element?(view, "#operations-provider-stream")
  end

  test "render and provider action do not enqueue jobs", %{conn: conn, key: key} do
    before = job_count()
    {:ok, view, _html} = live(authenticated_conn(conn), ~p"/admin/operations")
    assert job_count() == before
    view |> element("#provider-action-#{provider_id(key)}") |> render_click()
    assert job_count() == before
  end

  defp authenticated_conn(conn) do
    admin =
      Accounts.register_admin!(
        %{
          email: "ops-#{System.unique_integer([:positive])}@example.test",
          password: "correct horse battery staple",
          password_confirmation: "correct horse battery staple"
        },
        authorize?: false
      )

    conn |> init_test_session(%{}) |> AuthenticationPlug.store_in_session(admin)
  end

  defp admin do
    Accounts.register_admin!(
      %{
        email: "actor-#{System.unique_integer([:positive])}@example.test",
        password: "correct horse battery staple",
        password_confirmation: "correct horse battery staple"
      },
      authorize?: false
    )
  end

  defp configure_manual_targets(key) do
    Application.put_env(:tcg_cheap, :sealed_retailer_adapters, %{
      "web-manual-refresh" => %{
        adapter: TcgCheapWeb.Admin.OperationsManualRefreshTestAdapter,
        options: []
      }
    })

    Application.put_env(:tcg_cheap, :acquisition_budget,
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [
        provider(key),
        provider("other-#{key}"),
        provider("nbp"),
        provider("tcgdex_cardmarket"),
        provider("sealed_retailer:web-manual-refresh")
      ]
    )

    unique = System.unique_integer([:positive])

    card =
      Core.import_card_printing!(%{
        tcgdex_id: "web-manual-card-#{unique}",
        name: "Web manual card #{unique}",
        set_name: "Web manual set",
        collector_number: Integer.to_string(unique)
      })

    retailer =
      Core.register_retailer!(%{
        slug: "web-manual-retailer-#{unique}",
        source_key: "web-manual-refresh",
        name: "Web Manual Shop",
        category: "regular_retailer",
        homepage_url: "https://example.test/manual",
        source_payload: %{"secret" => "retailer-source-secret"}
      })

    {card, retailer}
  end

  defp budget_config(key) do
    [
      global_hourly_request_limit: 100,
      global_daily_request_limit: 1_000,
      global_monthly_spend_limit: "50.00",
      providers: [provider(key), provider("other-#{key}")]
    ]
  end

  defp provider(key),
    do: [
      provider_key: key,
      display_name: "Provider #{key}",
      estimated_cost_per_request: "1.00",
      hourly_request_limit: 10,
      daily_request_limit: 20,
      monthly_request_limit: 30,
      monthly_spend_limit: "50.00"
    ]

  defp provider_id(key), do: Base.url_encode64(key, padding: false)

  defp insert_job(state, worker, error, args, meta) do
    TcgCheap.Repo.query!(
      "INSERT INTO oban_jobs (state, queue, worker, args, errors, attempt, max_attempts, inserted_at, scheduled_at, meta) VALUES ($1, 'ops', $2, $3::jsonb, ARRAY[$4::jsonb], 1, 5, now(), now(), $5::jsonb)",
      [
        state,
        worker,
        Jason.encode!(%{secret: args}),
        Jason.encode!(%{error: error}),
        Jason.encode!(%{secret: meta})
      ]
    )
  end

  defp job_count do
    TcgCheap.Repo.query!("SELECT count(*) FROM oban_jobs").rows |> List.first() |> List.first()
  end

  defp extract_version(html) do
    [version | _] = Regex.run(~r/phx-value-version="([^"]*)"/, html, capture: :all_but_first)
    version
  end
end
