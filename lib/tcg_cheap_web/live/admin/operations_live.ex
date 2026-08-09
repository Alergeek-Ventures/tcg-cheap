defmodule TcgCheapWeb.Admin.OperationsLive do
  @moduledoc "Authenticated operations control desk."

  use TcgCheapWeb, :live_view

  alias TcgCheap.Operations.Overview

  @operation_events ~w(disable_provider enable_provider)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Operations desk")
     |> assign(:overview_ready?, false)
     |> assign(:global, nil)
     |> assign(:provider_count, 0)
     |> assign(:job_count, 0)
     |> load_overview()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="admin-operations" class="admin-world">
        <header class="admin-header">
          <.link id="admin-operations-home" navigate={~p"/"}>TCG CHEAP</.link>
          <nav id="admin-operations-header-nav" aria-label="Admin sections">
            <.link id="admin-operations-review-header-link" navigate={~p"/admin/review"}>Review</.link>
            <.link
              id="admin-operations-header-link"
              navigate={~p"/admin/operations"}
              aria-current="page"
            >Operations</.link>
          </nav>
          <div class="admin-header-actions">
            <span>{@current_admin.email}</span>
            <.link id="admin-operations-sign-out" href={~p"/admin/sign-out"} method="delete">Sign out</.link>
          </div>
        </header>
        <main class="admin-main">
          <div class="admin-container">
            <section class="admin-intro" aria-labelledby="admin-operations-title">
              <div>
                <h1 id="admin-operations-title">Operations desk</h1>
                <p>Operate the provider bench without hiding what the counters do not know.</p>
                <p class="admin-disclosure">
                  Counters are estimated reservations before HTTP. Actual paid-cost reconciliation and source health are not tracked yet.
                </p>
              </div>
              <%= if @overview_ready? do %>
                <nav id="admin-operations-nav" aria-label="Operations sections">
                  <a href="#operations-global-ledger">Global <strong>UTC</strong></a>
                  <a href="#operations-providers">Providers <strong>{@provider_count}</strong></a>
                  <a href="#operations-retained-jobs">Jobs <strong>{@job_count}</strong></a>
                </nav>
              <% end %>
            </section>

            <%= if @overview_ready? do %>
              <section
                id="operations-global-ledger"
                class="admin-queue"
                aria-labelledby="operations-global-title"
              >
                <div class="admin-section-rule">
                  <h2 id="operations-global-title">Global control ledger</h2><span>UTC windows</span>
                </div>
                <dl class="admin-ledger">
                  <div>
                    <dt>Hour requests</dt><dd>
                      {request_usage(@global.hour)} / {@global.limits.hourly_request_limit}
                    </dd>
                  </div>
                  <div>
                    <dt>Day requests</dt><dd>
                      {request_usage(@global.day)} / {@global.limits.daily_request_limit}
                    </dd>
                  </div>
                  <div>
                    <dt>Month estimated spend</dt><dd>
                      {money(@global.month.estimated_spend_usd)} / {money(
                        @global.limits.monthly_spend_limit
                      )}
                    </dd>
                  </div>
                </dl>
              </section>

              <section
                id="operations-providers"
                class="admin-queue"
                aria-labelledby="operations-providers-title"
              >
                <div class="admin-section-rule">
                  <h2 id="operations-providers-title">Provider bench</h2><span>{@provider_count} configured</span>
                </div>
                <div
                  id="operations-provider-stream"
                  class="admin-dockets operations-provider-dockets"
                  phx-update="stream"
                >
                  <p id="operations-provider-empty" class="admin-empty hidden only:block">
                    No providers are configured.
                  </p>
                  <article
                    :for={{dom_id, provider} <- @streams.providers}
                    id={dom_id}
                    class="admin-docket operations-provider-docket"
                  >
                    <div class="admin-docket-heading">
                      <div>
                        <h3>{provider.display_name}</h3><p>{provider.provider_key}</p>
                      </div>
                      <span id={"provider-status-#{provider_dom_id(provider.provider_key)}"}>{provider_status(
                        provider
                      )}</span>
                    </div>
                    <dl class="admin-ledger provider-ledger">
                      <div>
                        <dt>Estimated / request</dt><dd>
                          {money(provider.estimated_cost_per_request)}
                        </dd>
                      </div>
                      <div>
                        <dt>Hour requests</dt><dd>
                          {request_usage(provider.current_usage.hour)} / {provider.hourly_request_limit}
                        </dd>
                      </div>
                      <div>
                        <dt>Day requests</dt><dd>
                          {request_usage(provider.current_usage.day)} / {provider.daily_request_limit}
                        </dd>
                      </div>
                      <div>
                        <dt>Month requests</dt><dd>
                          {request_usage(provider.current_usage.month)} / {provider.monthly_request_limit}
                        </dd>
                      </div>
                      <div>
                        <dt>Month estimated spend</dt><dd>
                          {money(provider.current_usage.month.estimated_spend_usd)} / {money(
                            provider.monthly_spend_limit
                          )}
                        </dd>
                      </div>
                      <div>
                        <dt>Updated</dt><dd>{provider_updated(provider.updated_at)}</dd>
                      </div>
                    </dl>
                    <div class="admin-decision-row">
                      <button
                        id={"provider-action-#{provider_dom_id(provider.provider_key)}"}
                        type="button"
                        phx-click={provider_event(provider)}
                        phx-value-provider-key={provider.provider_key}
                        phx-value-version={version(provider.updated_at)}
                      >{provider_action(provider)}</button>
                    </div>
                  </article>
                </div>
              </section>

              <section
                id="operations-retained-jobs"
                class="admin-queue"
                aria-labelledby="operations-retained-title"
              >
                <div class="admin-section-rule">
                  <h2 id="operations-retained-title">Retained jobs</h2><span>{@job_count} shown</span>
                </div>
                <div id="operations-job-stream" class="admin-dockets" phx-update="stream">
                  <p id="operations-job-empty" class="admin-empty hidden only:block">
                    No retained failed/retryable/cancelled jobs.
                  </p>
                  <article
                    :for={{dom_id, job} <- @streams.recent_jobs}
                    id={dom_id}
                    class="admin-docket operations-job-docket"
                  >
                    <div class="admin-docket-heading">
                      <div>
                        <h3>{job.state}</h3><p>{job.queue} · {job.worker}</p>
                      </div><span>{job.attempt}/{job.max_attempts}</span>
                    </div>
                    <dl class="admin-ledger">
                      <div>
                        <dt>Observed UTC</dt><dd>{datetime(job.observed_at)}</dd>
                      </div><div class="wide-evidence">
                        <dt>Failure category</dt><dd>{job.failure_category}</dd>
                      </div>
                    </dl>
                  </article>
                </div>
              </section>
            <% else %>
              <section
                id="operations-unavailable"
                class="admin-state-error"
                aria-labelledby="operations-unavailable-title"
              >
                <h2 id="operations-unavailable-title">Operations unavailable</h2>
                <p>
                  Unable to load the operations overview. No healthy or empty state is being assumed.
                </p>
              </section>
            <% end %>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event(event, params, socket) when event in @operation_events do
    with {:ok, provider_key} <- fetch_binary(params, "provider-key"),
         {:ok, expected} <- fetch_version(params),
         status <- if(event == "enable_provider", do: "active", else: "disabled"),
         {:ok, _provider} <-
           Overview.set_provider_status(
             socket.assigns.current_admin,
             provider_key,
             status,
             expected
           ) do
      {:noreply, socket |> put_flash(:info, "Provider status updated.") |> load_overview()}
    else
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Provider status was not updated. Reload and try again.")
         |> load_overview()}
    end
  end

  defp load_overview(socket) do
    case Overview.load(socket.assigns.current_admin) do
      {:ok, overview} ->
        providers =
          Enum.map(overview.providers, fn provider ->
            Map.put(provider, :id, "provider-#{provider_dom_id(provider.provider_key)}")
          end)

        socket
        |> assign(:overview_ready?, true)
        |> assign(:global, overview.global)
        |> assign(:provider_count, length(providers))
        |> assign(:job_count, length(overview.recent_jobs))
        |> stream(:providers, providers, reset: true)
        |> stream(:recent_jobs, overview.recent_jobs, reset: true)

      {:error, _reason} ->
        socket
        |> assign(:overview_ready?, false)
        |> assign(:global, nil)
        |> assign(:provider_count, 0)
        |> assign(:job_count, 0)
        |> stream(:providers, [], reset: true)
        |> stream(:recent_jobs, [], reset: true)
    end
  end

  defp fetch_binary(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, :invalid_event}
    end
  end

  defp fetch_binary(_, _), do: {:error, :invalid_event}

  defp fetch_version(params) do
    case Map.get(params, "version") do
      value when is_binary(value) -> {:ok, value}
      _ -> {:error, :invalid_event}
    end
  end

  defp provider_dom_id(key), do: Base.url_encode64(to_string(key), padding: false)
  defp provider_status(%{status: "disabled"}), do: "DISABLED"
  defp provider_status(%{persisted?: false}), do: "ACTIVE ON FIRST USE"
  defp provider_status(_), do: "ACTIVE"
  defp provider_event(%{status: "disabled"}), do: "enable_provider"
  defp provider_event(_), do: "disable_provider"
  defp provider_action(%{status: "disabled"}), do: "Enable provider"
  defp provider_action(_), do: "Disable provider"
  defp request_usage(value), do: value.request_count
  defp money(nil), do: "—"

  defp money(value),
    do: value |> Decimal.round(2) |> Decimal.to_string(:normal) |> Kernel.<>(" USD")

  defp version(nil), do: ""
  defp version(value), do: DateTime.to_iso8601(value)
  defp provider_updated(nil), do: "Not registered yet"
  defp provider_updated(value), do: DateTime.to_iso8601(value)
  defp datetime(nil), do: "Unknown"
  defp datetime(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value) <> "Z"
  defp datetime(value), do: DateTime.to_iso8601(value)
end
