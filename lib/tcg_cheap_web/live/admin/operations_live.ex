defmodule TcgCheapWeb.Admin.OperationsLive do
  @moduledoc "Authenticated operations control desk."

  use TcgCheapWeb, :live_view

  alias TcgCheap.Operations.{BuyingModelInspection, ManualRefresh, Overview}

  @operation_events ~w(disable_provider enable_provider)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Operations desk")
     |> assign(:overview_ready?, false)
     |> assign(:global, nil)
     |> assign(:provider_count, 0)
     |> assign(:run_count, 0)
     |> assign(:job_count, 0)
     |> assign(:model_ready?, false)
     |> assign(:buying_model, nil)
     |> assign(:manual_ready?, false)
     |> assign(:manual_exchange_rate, nil)
     |> assign(:manual_valuation, nil)
     |> assign(:manual_available_count, 0)
     |> assign(:manual_form, to_form(%{"tcgdex_id" => ""}, as: :manual_refresh))
     |> stream(:manual_retailers, [], reset: true)
     |> load_buying_model()
     |> load_manual()
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
            <.link id="admin-operations-products-header-link" navigate={~p"/admin/catalogue/products"}>Products</.link>
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
                  Counters are estimated reservations before HTTP. Tracked provider attempts retain safe outcomes and admitted request counts; actual paid-cost reconciliation is not tracked yet.
                </p>
                <p class="admin-disclosure">
                  Running attempts older than the configured boundary are reconciled automatically; this desk does not probe providers or break circuits.
                </p>
              </div>
              <%= if @overview_ready? or @model_ready? or @manual_ready? do %>
                <nav id="admin-operations-nav" aria-label="Operations sections">
                  <%= if @overview_ready? do %>
                    <a href="#operations-global-ledger">Global <strong>UTC</strong></a>
                    <a href="#operations-providers">Providers <strong>{@provider_count}</strong></a>
                    <a href="#operations-acquisition-runs">Runs <strong>{@run_count}</strong></a>
                    <a href="#operations-retained-jobs">Jobs <strong>{@job_count}</strong></a>
                  <% end %>
                  <a href="#operations-buying-model">
                    Model <strong>{if(@model_ready?, do: 1, else: 0)}</strong>
                  </a>
                  <a href="#operations-manual-refresh">
                    Manual <strong>{@manual_available_count}</strong>
                  </a>
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
                      <div>
                        <dt>Last completed run</dt><dd>{health_status(provider.health)}</dd>
                      </div>
                      <div>
                        <dt>Last success UTC</dt><dd>
                          {health_time(provider.health, :last_succeeded_at)}
                        </dd>
                      </div>
                      <div>
                        <dt>Source freshness</dt><dd id={"provider-source-state-#{provider_dom_id(provider.provider_key)}"}>
                          {source_state(provider.source_state)}
                        </dd>
                      </div>
                      <div>
                        <dt>Failure streak</dt><dd>{failure_streak(provider.health)}</dd>
                      </div>
                      <div class="wide-evidence">
                        <dt>Last failure category</dt><dd>{health_failure(provider.health)}</dd>
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
                id="operations-acquisition-runs"
                class="admin-queue"
                aria-labelledby="operations-acquisition-runs-title"
              >
                <div class="admin-section-rule">
                  <h2 id="operations-acquisition-runs-title">Acquisition runs</h2><span>{@run_count} shown</span>
                </div>
                <div id="operations-run-stream" class="admin-dockets" phx-update="stream">
                  <p id="operations-run-empty" class="admin-empty hidden only:block">
                    No tracked acquisition attempts yet.
                  </p>
                  <article
                    :for={{dom_id, run} <- @streams.recent_runs}
                    id={dom_id}
                    class="admin-docket operations-run-docket"
                  >
                    <div class="admin-docket-heading">
                      <div>
                        <h3>{operation_name(run.operation)}</h3><p>{run.provider_key}</p>
                      </div><span>{run_status(run)}</span>
                    </div>
                    <dl class="admin-ledger">
                      <div class="wide-evidence">
                        <dt>Canonical target</dt><dd>{run.target_key}</dd>
                      </div>
                      <div>
                        <dt>Attempt</dt><dd>{run.attempt}/{run.max_attempts}</dd>
                      </div>
                      <div>
                        <dt>Admitted requests</dt><dd>{run.request_count}</dd>
                      </div>
                      <div>
                        <dt>Started UTC</dt><dd>{datetime(run.started_at)}</dd>
                      </div>
                      <div>
                        <dt>Finished UTC</dt><dd>{datetime(run.finished_at)}</dd>
                      </div>
                      <div class="wide-evidence">
                        <dt>Failure category</dt><dd>{run_failure(run.failure_category)}</dd>
                      </div>
                    </dl>
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

            <section
              id="operations-buying-model"
              class="admin-queue"
              aria-labelledby="operations-buying-model-title"
            >
              <div class="admin-section-rule">
                <h2 id="operations-buying-model-title">Buying model</h2><span>Read only · current code policy</span>
              </div>
              <%= if @model_ready? do %>
                <p class="admin-disclosure">
                  This policy is provisional and validated with synthetic cases only. Real Polish-market validation remains required; changing policy values requires a new model version so retained snapshots keep their meaning.
                </p>
                <div
                  id="operations-buying-model-dockets"
                  class="admin-dockets operations-provider-dockets"
                >
                  <article id="operations-model-identity" class="admin-docket">
                    <div class="admin-docket-heading">
                      <div>
                        <h3>Current policy</h3>
                        <p>Version identity, delegated aggregate, and deterministic arithmetic.</p>
                      </div>
                      <span>{@buying_model.model_status}</span>
                    </div>
                    <dl id="operations-model-identity-ledger" class="admin-ledger">
                      <div class="wide-evidence">
                        <dt>Buying model version</dt><dd>{@buying_model.model_version}</dd>
                      </div>
                      <div class="wide-evidence">
                        <dt>Aggregate version</dt><dd>{@buying_model.aggregate_version}</dd>
                      </div>
                      <div class="wide-evidence">
                        <dt>Validation basis</dt><dd>{@buying_model.validation_basis}</dd>
                      </div>
                    </dl>
                    <.policy_ledger
                      id="operations-model-calculation-ledger"
                      rows={
                        @buying_model.aggregate ++
                          @buying_model.rounding ++
                          @buying_model.decimal_arithmetic
                      }
                    />
                  </article>

                  <article id="operations-model-reference" class="admin-docket">
                    <div class="admin-docket-heading">
                      <div>
                        <h3>Reference blend</h3>
                        <p>
                          Available inputs renormalize around the live regular-retailer benchmark.
                        </p>
                      </div>
                      <span>WEIGHTS</span>
                    </div>
                    <.policy_ledger
                      id="operations-model-component-weights"
                      rows={@buying_model.component_weights}
                    />
                  </article>

                  <article id="operations-model-confidence" class="admin-docket">
                    <div class="admin-docket-heading">
                      <div>
                        <h3>Confidence score</h3>
                        <p>Six weighted signals must reach the ready threshold.</p>
                      </div>
                      <span>{@buying_model.confidence.ready_threshold}</span>
                    </div>
                    <.policy_ledger
                      id="operations-model-confidence-weights"
                      rows={@buying_model.confidence.weights}
                    />
                    <.policy_ledger
                      id="operations-model-confidence-targets"
                      rows={@buying_model.confidence.targets}
                    />
                  </article>

                  <article id="operations-model-readiness" class="admin-docket">
                    <div class="admin-docket-heading">
                      <div>
                        <h3>Readiness gates</h3>
                        <p>Hard evidence requirements apply before four-band guidance can render.</p>
                      </div>
                      <span>FAIL CLOSED</span>
                    </div>
                    <.policy_ledger
                      id="operations-model-hard-requirements"
                      rows={@buying_model.confidence.hard_requirements}
                    />
                    <.policy_ledger
                      id="operations-model-history-rules"
                      rows={@buying_model.freshness_and_history}
                    />
                  </article>

                  <article id="operations-model-market-signals" class="admin-docket">
                    <div class="admin-docket-heading">
                      <div>
                        <h3>Market signals</h3>
                        <p>Availability and sold-out recency alter confidence and band position.</p>
                      </div>
                      <span>30 DAYS</span>
                    </div>
                    <.policy_ledger
                      id="operations-model-availability-rules"
                      rows={@buying_model.availability}
                    />
                    <.policy_ledger
                      id="operations-model-sold-out-rules"
                      rows={@buying_model.sold_out_recency}
                    />
                  </article>

                  <article id="operations-model-bands" class="admin-docket">
                    <div class="admin-docket-heading">
                      <div>
                        <h3>Band construction</h3>
                        <p>Inclusive ceilings are adjusted by trend and availability evidence.</p>
                      </div>
                      <span>PLN</span>
                    </div>
                    <.policy_ledger
                      id="operations-model-band-bases"
                      rows={@buying_model.bands.base_multipliers ++ @buying_model.bands.guardrail}
                    />
                    <.policy_ledger
                      id="operations-model-trend-adjustments"
                      rows={@buying_model.bands.trend_adjustments}
                    />
                    <.policy_ledger
                      id="operations-model-availability-adjustments"
                      rows={
                        @buying_model.bands.availability_adjustments ++
                          @buying_model.bands.availability_trend_adjustments
                      }
                    />
                  </article>

                  <article id="operations-model-limited" class="admin-docket">
                    <div class="admin-docket-heading">
                      <div>
                        <h3>Limited data precedence</h3>
                        <p>The first matching reason suppresses confident buying bands.</p>
                      </div>
                      <span>{length(@buying_model.limited_reason_precedence)} REASONS</span>
                    </div>
                    <dl id="operations-model-limited-reasons" class="admin-ledger">
                      <div :for={reason <- @buying_model.limited_reason_precedence}>
                        <dt>Priority {reason.position}</dt><dd>{reason.label}</dd>
                      </div>
                    </dl>
                  </article>
                </div>
              <% else %>
                <div id="operations-buying-model-unavailable" class="admin-state-error">
                  <h2>Model policy unavailable</h2>
                  <p>
                    The current policy did not pass strict inspection. No configuration is being assumed.
                  </p>
                </div>
              <% end %>
            </section>

            <section
              id="operations-manual-refresh"
              class="admin-queue"
              aria-labelledby="operations-manual-refresh-title"
            >
              <div class="admin-section-rule">
                <h2 id="operations-manual-refresh-title">Manual refresh</h2><span>Canonical jobs only</span>
              </div>
              <%= if @manual_ready? do %>
                <p class="admin-disclosure">
                  Active duplicates reuse the canonical queued job. Provider budget is checked before HTTP; this action never marks work complete.
                </p>
                <div id="manual-refresh-fixed" class="admin-dockets operations-provider-dockets">
                  <article id="manual-refresh-exchange-rate-panel" class="admin-docket">
                    <div class="admin-docket-heading">
                      <div>
                        <h3>EUR / PLN rate</h3>
                        <p>One fixed NBP Table A request.</p>
                      </div>
                      <span id="manual-refresh-exchange-rate-status">
                        {manual_status(@manual_exchange_rate)}
                      </span>
                    </div>
                    <div class="admin-decision-row">
                      <button
                        id="manual-refresh-exchange-rate"
                        type="button"
                        phx-click="manual_exchange_rate"
                        phx-disable-with="Queueing…"
                        disabled={@manual_exchange_rate.status != :available}
                      >Queue EUR / PLN refresh</button>
                    </div>
                  </article>

                  <article id="manual-refresh-valuation-panel" class="admin-docket">
                    <div class="admin-docket-heading">
                      <div>
                        <h3>Single valuation</h3>
                        <p>One exact locally imported TCGdex printing.</p>
                      </div>
                      <span id="manual-refresh-valuation-status">
                        {manual_status(@manual_valuation)}
                      </span>
                    </div>
                    <.form
                      for={@manual_form}
                      id="manual-refresh-valuation-form"
                      phx-submit="manual_single_valuation"
                    >
                      <.input
                        field={@manual_form[:tcgdex_id]}
                        type="text"
                        label="Exact TCGdex ID"
                        maxlength="240"
                        autocomplete="off"
                      />
                      <div class="admin-decision-row">
                        <button
                          id="manual-refresh-valuation"
                          type="submit"
                          phx-disable-with="Queueing…"
                          disabled={@manual_valuation.status != :available}
                        >Queue valuation refresh</button>
                      </div>
                    </.form>
                  </article>
                </div>

                <div
                  id="manual-refresh-retailer-stream"
                  class="admin-dockets compact-dockets"
                  phx-update="stream"
                >
                  <p id="manual-refresh-retailer-empty" class="admin-empty hidden only:block">
                    No active configured sealed retailers.
                  </p>
                  <article
                    :for={{dom_id, retailer} <- @streams.manual_retailers}
                    id={dom_id}
                    class="admin-docket"
                  >
                    <div class="admin-docket-heading">
                      <div>
                        <h3>{retailer.label}</h3>
                        <p>{retailer.source_key}</p>
                      </div>
                      <span>{manual_status(retailer)}</span>
                    </div>
                    <div class="admin-decision-row">
                      <button
                        id={"manual-refresh-retailer-#{retailer_dom_id(retailer.retailer_id)}"}
                        type="button"
                        phx-click="manual_sealed_retailer"
                        phx-value-retailer-id={retailer.retailer_id}
                        phx-disable-with="Queueing…"
                        disabled={retailer.status != :available}
                      >Queue sealed retailer refresh</button>
                    </div>
                  </article>
                </div>
              <% else %>
                <p id="operations-manual-unavailable">
                  Manual refresh is unavailable. No acquisition target was assumed safe.
                </p>
              <% end %>
            </section>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("manual_exchange_rate", _params, socket),
    do: manual_enqueue(:exchange_rate, "EUR / PLN refresh", socket)

  def handle_event("manual_single_valuation", %{"manual_refresh" => %{"tcgdex_id" => id}}, socket) do
    case ManualRefresh.enqueue(socket.assigns.current_admin, {:single_valuation, id}) do
      {:ok, result} ->
        {:noreply,
         socket
         |> put_flash(:info, manual_flash(result, "valuation"))
         |> assign(:manual_form, to_form(%{"tcgdex_id" => id}, as: :manual_refresh))}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Valuation was not queued. Check the exact TCGdex ID and try again."
         )
         |> assign(:manual_form, to_form(%{"tcgdex_id" => id}, as: :manual_refresh))}
    end
  end

  def handle_event("manual_single_valuation", _params, socket),
    do:
      {:noreply,
       put_flash(
         socket,
         :error,
         "Valuation was not queued. Check the exact TCGdex ID and try again."
       )}

  def handle_event("manual_sealed_retailer", %{"retailer-id" => id}, socket),
    do: manual_enqueue({:sealed_retailer, id}, "Sealed retailer refresh", socket)

  def handle_event("manual_sealed_retailer", _params, socket),
    do:
      {:noreply,
       put_flash(socket, :error, "Sealed refresh was not queued. Reload and try again.")}

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
      {:noreply,
       socket
       |> put_flash(:info, "Provider status updated.")
       |> load_manual()
       |> load_overview()}
    else
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Provider status was not updated. Reload and try again.")
         |> load_manual()
         |> load_overview()}
    end
  end

  defp manual_enqueue(target, noun, socket) do
    case ManualRefresh.enqueue(socket.assigns.current_admin, target) do
      {:ok, result} ->
        {:noreply, put_flash(socket, :info, manual_flash(result, noun))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Acquisition was not queued. Reload and try again.")}
    end
  end

  defp manual_flash(%{status: :queued}, noun), do: "#{String.capitalize(noun)} queued."

  defp manual_flash(%{status: :already_queued}, noun),
    do: "#{String.capitalize(noun)} already queued; reused the canonical job."

  defp load_buying_model(socket) do
    case BuyingModelInspection.load(socket.assigns.current_admin) do
      {:ok, model} ->
        socket
        |> assign(:model_ready?, true)
        |> assign(:buying_model, model)

      {:error, _reason} ->
        socket
        |> assign(:model_ready?, false)
        |> assign(:buying_model, nil)
    end
  end

  defp load_manual(socket) do
    case ManualRefresh.targets(socket.assigns.current_admin) do
      {:ok, targets} ->
        exchange = Enum.find(targets, &(&1.kind == :exchange_rate)) || %{status: :unconfigured}

        valuation =
          Enum.find(targets, &(&1.kind == :single_valuation)) || %{status: :unconfigured}

        retailers =
          targets
          |> Enum.filter(&(&1.kind == :sealed_retailer))
          |> Enum.map(fn retailer ->
            Map.put(retailer, :id, "manual-retailer-#{retailer_dom_id(retailer.retailer_id)}")
          end)

        socket
        |> assign(:manual_ready?, true)
        |> assign(:manual_exchange_rate, exchange)
        |> assign(:manual_valuation, valuation)
        |> assign(:manual_available_count, Enum.count(targets, &(&1.status == :available)))
        |> stream(:manual_retailers, retailers, reset: true)

      _ ->
        socket
        |> assign(:manual_ready?, false)
        |> assign(:manual_exchange_rate, nil)
        |> assign(:manual_valuation, nil)
        |> assign(:manual_available_count, 0)
        |> stream(:manual_retailers, [], reset: true)
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
        |> assign(:run_count, length(overview.recent_runs))
        |> assign(:job_count, length(overview.recent_jobs))
        |> stream(:providers, providers, reset: true)
        |> stream(:recent_runs, overview.recent_runs, reset: true)
        |> stream(:recent_jobs, overview.recent_jobs, reset: true)

      {:error, _reason} ->
        socket
        |> assign(:overview_ready?, false)
        |> assign(:global, nil)
        |> assign(:provider_count, 0)
        |> assign(:run_count, 0)
        |> assign(:job_count, 0)
        |> stream(:providers, [], reset: true)
        |> stream(:recent_runs, [], reset: true)
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

  defp manual_status(%{status: :available}), do: "AVAILABLE"
  defp manual_status(%{status: :disabled}), do: "DISABLED"
  defp manual_status(_), do: "UNCONFIGURED"
  defp retailer_dom_id(id), do: Base.url_encode64(id, padding: false)

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
  defp health_status(nil), do: "No completed acquisition"
  defp health_status(%{last_status: nil}), do: "No completed acquisition"
  defp health_status(%{last_status: status}), do: run_status(status)
  defp source_state(:current), do: "CURRENT"
  defp source_state(:stale), do: "STALE"
  defp source_state(:not_observed), do: "NO SUCCESS YET"
  defp source_state(:on_demand), do: "ON DEMAND"
  defp source_state(:invalid), do: "INVALID EVIDENCE"
  defp source_state(_), do: "INVALID EVIDENCE"
  defp health_time(nil, _field), do: "None yet"

  defp health_time(health, field) do
    case Map.fetch!(health, field) do
      nil -> "None yet"
      value -> datetime(value)
    end
  end

  defp failure_streak(nil), do: 0
  defp failure_streak(health), do: health.consecutive_failures
  defp health_failure(nil), do: "None"
  defp health_failure(%{last_failure_category: nil}), do: "None"
  defp health_failure(health), do: failure_name(health.last_failure_category)
  defp operation_name("single_valuation"), do: "Single valuation"
  defp operation_name("exchange_rate"), do: "EUR/PLN rate"
  defp operation_name("sealed_retailer_refresh"), do: "Sealed retailer refresh"
  defp operation_name(_), do: "Acquisition"
  defp run_status(%{overdue?: true, status: "running"}), do: "OVERDUE"
  defp run_status(%{status: status}), do: run_status(status)
  defp run_status("succeeded"), do: "SUCCEEDED"
  defp run_status("retryable_failure"), do: "RETRYABLE FAILURE"
  defp run_status("failed"), do: "FAILED"
  defp run_status("cancelled"), do: "CANCELLED"
  defp run_status("running"), do: "RUNNING"
  defp run_status(_), do: "UNKNOWN"
  defp run_failure(nil), do: "None"
  defp run_failure(category), do: failure_name(category)

  defp failure_name(category),
    do: category |> String.replace("_", " ") |> String.capitalize()

  defp datetime(nil), do: "Unknown"
  defp datetime(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value) <> "Z"
  defp datetime(value), do: DateTime.to_iso8601(value)

  attr :id, :string, required: true
  attr :rows, :list, required: true

  defp policy_ledger(assigns) do
    ~H"""
    <dl id={@id} class="admin-ledger">
      <div :for={row <- @rows}>
        <dt>{row.label}</dt><dd>{row.value}</dd>
      </div>
    </dl>
    """
  end
end
