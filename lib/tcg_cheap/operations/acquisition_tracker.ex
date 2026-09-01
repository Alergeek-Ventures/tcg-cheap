defmodule TcgCheap.Operations.AcquisitionTracker do
  @moduledoc "Small worker-facing boundary for secret-safe acquisition telemetry."

  alias TcgCheap.Operations
  alias TcgCheap.Operations.AcquisitionBudget
  defstruct [:run, :provider_key, :counter]
  @type t :: %__MODULE__{run: struct(), provider_key: String.t(), counter: reference()}

  @spec start(Oban.Job.t(), keyword()) :: {:ok, t()} | {:error, :acquisition_tracking_failed}
  def start(%Oban.Job{} = job, opts) when is_list(opts) do
    with {:ok, attrs} <- attrs(job, opts),
         {:ok, run} <- start_run(attrs) do
      {:ok,
       %__MODULE__{
         run: run,
         provider_key: attrs.provider_key,
         counter: :atomics.new(1, signed: false)
       }}
    else
      _ -> {:error, :acquisition_tracking_failed}
    end
  rescue
    _ -> {:error, :acquisition_tracking_failed}
  end

  def start(_job, _opts), do: {:error, :acquisition_tracking_failed}

  def request_admitter(%__MODULE__{} = tracker) do
    fn ->
      case AcquisitionBudget.admit_attempt(tracker.provider_key) do
        {:ok, _} ->
          :atomics.add_get(tracker.counter, 1, 1)
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def admit_request(tracker), do: request_admitter(tracker).()

  @doc "Runs one worker attempt after durably opening its acquisition run."
  def run(job, opts, callback) when is_list(opts) and is_function(callback, 1) do
    case start(job, opts) do
      {:ok, tracker} ->
        run_callback(tracker, callback)

      {:error, :acquisition_tracking_failed} = error ->
        error
    end
  end

  def run(_job, _opts, _callback), do: {:error, :acquisition_tracking_failed}

  def finish(%__MODULE__{} = tracker, result) do
    {status, category} = outcome(tracker, result)
    count = :atomics.get(tracker.counter, 1)

    case Operations.finish_acquisition_run(
           tracker.run,
           status,
           category && Atom.to_string(category),
           count,
           authorize?: false
         ) do
      {:ok, run} -> {:ok, run}
      _ -> {:error, :acquisition_tracking_failed}
    end
  rescue
    _ -> {:error, :acquisition_tracking_failed}
  end

  @doc "Returns the fixed, secret-safe category retained for a worker failure."
  def classify(reason), do: category(reason)

  defp run_callback(tracker, callback) do
    result = callback.(request_admitter(tracker))

    case finish(tracker, result) do
      {:ok, _run} -> result
      {:error, :acquisition_tracking_failed} -> {:error, :acquisition_tracking_failed}
    end
  catch
    kind, reason ->
      stacktrace = __STACKTRACE__
      _ = finish(tracker, {:error, :worker_callback_exception})
      :erlang.raise(kind, reason, stacktrace)
  end

  defp outcome(_tracker, :ok), do: {"succeeded", nil}

  defp outcome(_tracker, {:snooze, period}) when is_integer(period) and period > 0,
    do: {"succeeded", nil}

  defp outcome(_tracker, {:cancel, reason}), do: {"cancelled", category(reason)}

  defp outcome(tracker, {:error, rejection = {:acquisition_budget_rejected, _reason, _reset_at}}) do
    case AcquisitionBudget.budget_reason_disposition(rejection) do
      disposition when disposition in [:hourly, :daily, :monthly] ->
        {"retryable_failure", :budget}

      _ ->
        outcome_error(tracker, rejection)
    end
  end

  defp outcome(tracker, {:error, reason}) do
    outcome_error(tracker, reason)
  end

  defp outcome(tracker, _result), do: {error_status(tracker), :unknown}

  defp outcome_error(tracker, reason) do
    status =
      if tracker.run.attempt >= tracker.run.max_attempts, do: "failed", else: "retryable_failure"

    {status, category(reason)}
  end

  defp error_status(tracker) do
    if tracker.run.attempt >= tracker.run.max_attempts, do: "failed", else: "retryable_failure"
  end

  defp category(reason) when reason in [:acquisition_budget_rejected, :provider_disabled],
    do: :budget

  defp category(reason) when is_tuple(reason) and elem(reason, 0) == :acquisition_budget_rejected,
    do: :budget

  defp category(reason)
       when reason in [
              :rate_limited,
              :rate_limit_reached,
              :too_many_requests,
              :provider_rate_limited
            ],
       do: :rate_limit

  defp category({:rate_limit, _}), do: :rate_limit
  defp category({:rate_limited, _}), do: :rate_limit
  defp category({:provider_rate_limited, _}), do: :rate_limit

  defp category(reason) when reason in [:timeout, :request_timeout, :provider_timeout],
    do: :timeout

  defp category({:timeout, _}), do: :timeout
  defp category({:provider_timeout, _}), do: :timeout
  defp category({:transport_error, %Req.TransportError{reason: :timeout}}), do: :timeout

  defp category(reason)
       when reason in [
              :transport,
              :transport_error,
              :provider_transport_error,
              :econnrefused,
              :closed,
              :nxdomain
            ],
       do: :transport

  defp category({:transport, _}), do: :transport
  defp category({:transport_error, _}), do: :transport
  defp category({:provider_transport_error, _}), do: :transport

  defp category({:http_error, %{status: status}}), do: http_category(status)
  defp category({:http_error, status}), do: http_category(status)
  defp category({:provider_http_error, status}), do: http_category(status)
  defp category({:provider_callback_error, _function, _outcome}), do: :provider_response
  defp category({:decode_error, _reason}), do: :provider_response
  defp category({:malformed_response, _reason}), do: :provider_response

  defp category(reason)
       when reason in [
              :provider_response,
              :invalid_provider_response,
              :provider_callback_failed,
              :catalogue_sync_incomplete,
              :provider_not_found,
              :pricing_unavailable,
              :unsupported_currency,
              :malformed_provider_response,
              :malformed_provider_result,
              :no_published_rate,
              :pagination_changed,
              :adapter_exception,
              :adapter_throw,
              :adapter_exit
            ],
       do: :provider_response

  defp category({:provider_response, _}), do: :provider_response

  defp category(reason)
       when reason in [
              :persistence,
              :persistence_invalid,
              :persistence_failed,
              :budget_persistence_failed,
              :database_error,
              :retailer_lookup_failed
            ],
       do: :persistence

  defp category({:persistence, _}), do: :persistence

  defp category(reason)
       when reason in [
              :configuration,
              :invalid_provider_configuration,
              :invalid_admission_configuration
            ],
       do: :configuration

  defp category(reason)
       when reason in [
              :local_input,
              :invalid_input,
              :invalid_local_card,
              :invalid_provider_request,
              :retailer_not_found,
              :retailer_not_active_or_mismatched,
              :malformed_job_args
            ],
       do: :local_input

  defp category(_), do: :unknown

  defp http_category(408), do: :timeout
  defp http_category(429), do: :rate_limit
  defp http_category(_), do: :provider_response

  defp attrs(job, opts) do
    allowed = [:provider_key, :operation, :target_key]

    if valid_options?(opts, allowed),
      do: opts |> tracker_values(job) |> build_attrs(),
      else: {:error, :invalid_input}
  end

  defp tracker_values(opts, job) do
    %{
      provider: Keyword.get(opts, :provider_key),
      operation: Keyword.get(opts, :operation),
      target: Keyword.get(opts, :target_key),
      worker: job.worker,
      queue: job.queue,
      attempt: job.attempt,
      max_attempts: job.max_attempts,
      job_id: job.id
    }
  end

  defp build_attrs(values) do
    valid? =
      valid_identity?(
        values.provider,
        values.operation,
        values.target,
        values.worker,
        values.queue
      ) and valid_attempt?(values.attempt, values.max_attempts) and valid_job_id?(values.job_id)

    if valid?, do: {:ok, attributes(values)}, else: {:error, :invalid_input}
  end

  defp attributes(values) do
    %{
      attempt_key: attempt_key(values.job_id, values.attempt),
      provider_key: values.provider,
      operation: values.operation,
      target_key: values.target,
      worker: values.worker,
      queue: values.queue,
      job_id: values.job_id,
      attempt: values.attempt,
      max_attempts: values.max_attempts,
      started_at: DateTime.utc_now()
    }
  end

  defp attempt_key(job_id, attempt) when is_integer(job_id), do: "oban:#{job_id}:#{attempt}"
  defp attempt_key(nil, _attempt), do: "manual:" <> Ecto.UUID.generate()

  defp start_run(attrs) do
    Operations.start_acquisition_run(
      attrs.attempt_key,
      attrs.provider_key,
      attrs.operation,
      attrs.target_key,
      attrs.worker,
      attrs.queue,
      attrs.job_id,
      attrs.attempt,
      attrs.max_attempts,
      attrs.started_at,
      authorize?: false
    )
  end

  defp valid_options?(opts, allowed) do
    keys = Keyword.keys(opts)
    Keyword.keyword?(opts) and keys == Enum.uniq(keys) and Enum.all?(keys, &(&1 in allowed))
  end

  defp valid_identity?(provider, operation, target, worker, queue) do
    valid_text?(provider, 160) and
      operation in [
        "single_valuation",
        "exchange_rate",
        "sealed_retailer_refresh",
        "card_catalogue_sync"
      ] and
      valid_text?(target, 240) and valid_text?(worker, 240) and valid_text?(queue, 160)
  end

  defp valid_attempt?(attempt, maximum),
    do: is_integer(attempt) and is_integer(maximum) and attempt > 0 and maximum >= attempt

  defp valid_job_id?(nil), do: true
  defp valid_job_id?(job_id), do: is_integer(job_id) and job_id > 0

  defp valid_text?(value, maximum),
    do:
      is_binary(value) and byte_size(value) > 0 and byte_size(value) <= maximum and
        value == String.trim(value)
end
