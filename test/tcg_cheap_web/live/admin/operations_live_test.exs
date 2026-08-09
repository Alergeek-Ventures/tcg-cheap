defmodule TcgCheapWeb.Admin.OperationsLiveTest do
  use TcgCheapWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Phoenix.Plug, as: AuthenticationPlug
  alias TcgCheap.Accounts
  alias TcgCheap.Operations

  setup do
    previous = Application.get_env(:tcg_cheap, :acquisition_budget)
    key = "web-ops-#{System.unique_integer([:positive])}"

    Application.put_env(:tcg_cheap, :acquisition_budget, budget_config(key))

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:tcg_cheap, :acquisition_budget),
        else: Application.put_env(:tcg_cheap, :acquisition_budget, previous)
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
    assert has_element?(view, "#admin-operations-header-link")
    assert has_element?(view, "#operations-global-ledger")
    assert has_element?(view, "#operations-providers")
    assert has_element?(view, "#operations-retained-jobs")
    assert has_element?(view, "#operations-provider-stream[phx-update=stream]")
    assert has_element?(view, "#operations-job-stream[phx-update=stream]")
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
