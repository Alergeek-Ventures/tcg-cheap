defmodule TcgCheap.Operations.CardmarketBulkCoverage do
  @moduledoc "Authenticated, bounded projection of Cardmarket bulk catalogue coverage."

  import Ash.Query

  alias TcgCheap.Accounts.{Admin, AdminActor}
  alias TcgCheap.Operations.AcquisitionHealthPolicy
  alias TcgCheap.Operations.CatalogueSyncRun
  alias TcgCheap.Pricing.CardmarketBulk.Batch

  @policy "cardmarket_bulk_v1"
  @provider "cardmarket_bulk"
  @cutover_keys [
    :relative_value_tolerance,
    :row_count_anomaly_bound,
    :minimum_coverage_gain,
    :minimum_coverage_ratio,
    :minimum_overlap,
    :minimum_agreement_ratio
  ]

  @doc "Loads the persisted coverage evidence for internal, fail-closed decisions."
  def load_system(opts \\ []), do: load_report(nil, opts, false)

  @spec load(Admin.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def load(actor, opts \\ [])

  def load(%Admin{} = actor, opts) do
    with :ok <- AdminActor.validate(actor), do: load_report(actor, opts, true)
  end

  def load(_, _), do: {:error, :invalid_actor}

  defp load_report(actor, opts, admin?) do
    with {:ok, clock} <- parse_options(opts),
         {:ok, now} <- valid_clock(clock),
         {:ok, {latest, previous}} <- batches(actor, admin?),
         :ok <- validate_batches(latest, previous, now),
         {:ok, counts} <- counts(latest),
         :ok <- validate_aggregate(counts, latest),
         {:ok, policy} <- AcquisitionHealthPolicy.load(),
         {:ok, health} <- source_health(actor, admin?),
         :ok <- validate_health(health, now),
         {:ok, catalogue} <- catalogue_evidence(actor, admin?, now),
         {:ok, comparison} <- comparison(latest, previous) do
      readiness =
        readiness(latest, previous, counts, comparison, health, policy, catalogue, now)

      {:ok,
       %{
         status:
           case latest do
             nil -> :no_batch
             _ -> :ok
           end,
         latest_batch: batch_projection(latest, now),
         previous_batch: batch_projection(previous, now),
         counts: counts,
         source: source_projection(health, policy, now),
         catalogue: catalogue,
         comparison: comparison,
         cutover: readiness,
         cutover_readiness: readiness
       }}
    else
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :cardmarket_bulk_coverage_failed}
  end

  defp parse_options(opts) when is_list(opts) do
    keys = Keyword.keys(opts)

    if Keyword.keyword?(opts) and keys == Enum.uniq(keys) and keys -- [:clock] == [] and
         is_function(Keyword.get(opts, :clock, &DateTime.utc_now/0), 0) and
         valid_cutover_config?(),
       do: {:ok, Keyword.get(opts, :clock, &DateTime.utc_now/0)},
       else: {:error, :invalid_cardmarket_bulk_coverage_input}
  end

  defp parse_options(_), do: {:error, :invalid_cardmarket_bulk_coverage_input}

  defp valid_cutover_config? do
    config = Application.get_env(:tcg_cheap, :cardmarket_bulk_cutover)

    is_list(config) and Keyword.keyword?(config) and valid_cutover_keys?(config) and
      valid_cutover_values?(config)
  end

  defp valid_cutover_keys?(config) do
    keys = Keyword.keys(config)
    Enum.sort(keys) == Enum.sort(@cutover_keys) and length(keys) == length(Enum.uniq(keys))
  end

  defp valid_cutover_values?(config) do
    valid_fraction?(Keyword.get(config, :relative_value_tolerance)) and
      valid_fraction?(Keyword.get(config, :row_count_anomaly_bound)) and
      positive_integer?(Keyword.get(config, :minimum_coverage_gain)) and
      finite_number_at_least?(Keyword.get(config, :minimum_coverage_ratio), 1) and
      positive_integer?(Keyword.get(config, :minimum_overlap)) and
      finite_number_between?(Keyword.get(config, :minimum_agreement_ratio), 0, 1, false)
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp valid_fraction?(value), do: finite_number_between?(value, 0, 1, true)

  defp finite_number_at_least?(value, minimum),
    do: finite_number?(value) and value >= minimum

  defp finite_number_between?(value, minimum, maximum, inclusive_minimum),
    do:
      finite_number?(value) and value <= maximum and
        if(inclusive_minimum, do: value >= minimum, else: value > minimum)

  defp finite_number?(value) when is_integer(value), do: true

  defp finite_number?(value) when is_float(value),
    do: value < Float.max_finite() and value > -Float.max_finite()

  defp finite_number?(_), do: false

  defp valid_clock(clock) do
    case clock.() do
      %DateTime{time_zone: "Etc/UTC"} = now -> {:ok, now}
      _ -> {:error, :invalid_clock}
    end
  rescue
    _ -> {:error, :invalid_clock}
  end

  defp batches(actor, admin?) do
    result =
      Batch
      |> for_read(:read, %{}, actor: actor)
      |> filter(status == "succeeded")
      |> sort(product_created_at: :desc, price_created_at: :desc, inserted_at: :desc, id: :desc)
      |> limit(2)
      |> Ash.read(authorize?: admin?)

    case result do
      {:ok, [latest, previous]} -> {:ok, {latest, previous}}
      {:ok, [latest]} -> {:ok, {latest, nil}}
      {:ok, []} -> {:ok, {nil, nil}}
      _ -> {:error, :batch_query_failed}
    end
  end

  defp validate_batches(nil, nil, _now), do: :ok

  defp validate_batches(latest, previous, now) do
    with :ok <- validate_batch(latest, now),
         :ok <- validate_optional_batch(previous, now),
         do: validate_order(latest, previous)
  end

  defp validate_optional_batch(nil, _), do: :ok
  defp validate_optional_batch(batch, now), do: validate_batch(batch, now)

  defp validate_order(_, nil), do: :ok

  defp validate_order(latest, previous) do
    source_ordered? =
      DateTime.compare(previous.product_created_at, latest.product_created_at) != :gt and
        DateTime.compare(previous.price_created_at, latest.price_created_at) != :gt

    tie_breaker? =
      latest.product_created_at != previous.product_created_at or
        latest.price_created_at != previous.price_created_at or
        latest.inserted_at > previous.inserted_at

    if source_ordered? and tie_breaker?,
      do: :ok,
      else: {:error, :incoherent_batch_evidence}
  end

  defp validate_batch(batch, now) do
    timestamps = [
      batch.product_created_at,
      batch.price_created_at,
      batch.fetched_at,
      batch.completed_at
    ]

    if batch.status == "succeeded" and is_nil(batch.failure_summary) and
         valid_batch_times?(batch, timestamps, now) and valid_batch_identity?(batch) and
         valid_batch_sizes?(batch) and valid_counts?(batch),
       do: :ok,
       else: {:error, :incoherent_batch_evidence}
  end

  defp valid_batch_times?(batch, timestamps, now) do
    Enum.all?(timestamps ++ [batch.inserted_at], &past_utc?(&1, now)) and
      DateTime.compare(batch.fetched_at, batch.product_created_at) != :lt and
      DateTime.compare(batch.fetched_at, batch.price_created_at) != :lt and
      DateTime.compare(batch.completed_at, batch.fetched_at) != :lt
  end

  defp valid_batch_identity?(batch) do
    is_binary(batch.policy_version) and is_binary(batch.parser_version) and
      batch.policy_version == @policy and valid_hash?(batch.product_sha256) and
      valid_hash?(batch.price_sha256)
  end

  defp valid_batch_sizes?(batch) do
    is_integer(batch.product_byte_size) and is_integer(batch.price_byte_size) and
      batch.product_byte_size > 0 and batch.price_byte_size > 0
  end

  defp valid_counts?(b) do
    Enum.all?(
      [
        b.product_row_count,
        b.price_row_count,
        b.singles_price_row_count,
        b.priceable_singles_count
      ],
      &is_integer/1
    ) and
      b.product_row_count > 0 and b.price_row_count >= b.singles_price_row_count and
      b.product_row_count == b.singles_price_row_count and
      b.priceable_singles_count > 0 and
      b.priceable_singles_count <= b.singles_price_row_count
  end

  defp valid_hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-fA-F]{64}\z/, value)

  defp past_utc?(%DateTime{time_zone: "Etc/UTC"} = value, now),
    do: DateTime.compare(value, now) != :gt

  defp past_utc?(_, _), do: false

  defp batch_projection(nil, _), do: nil

  defp batch_projection(batch, now) do
    %{
      id: batch.id,
      status: batch.status,
      failure_summary: batch.failure_summary,
      policy_version: batch.policy_version,
      parser_version: batch.parser_version,
      product_created_at: batch.product_created_at,
      price_created_at: batch.price_created_at,
      fetched_at: batch.fetched_at,
      completed_at: batch.completed_at,
      age_seconds: DateTime.diff(now, batch.completed_at),
      product_sha256: batch.product_sha256,
      price_sha256: batch.price_sha256,
      product_byte_size: batch.product_byte_size,
      price_byte_size: batch.price_byte_size,
      product_row_count: batch.product_row_count,
      price_row_count: batch.price_row_count,
      singles_price_row_count: batch.singles_price_row_count,
      priceable_singles_count: batch.priceable_singles_count
    }
  end

  defp counts(batch) do
    batch_id = if batch, do: Ecto.UUID.dump!(batch.id), else: nil

    result =
      TcgCheap.Repo.query(
        """
        WITH canonical AS (SELECT cp.* FROM card_printings cp JOIN card_sets cs ON cs.id=cp.card_set_id AND cs.tcgdex_id <> 'tcgp'),
        latest_batch AS (SELECT fetched_at, price_created_at FROM cardmarket_bulk_batches WHERE id=$1::uuid),
        staged_products AS (SELECT p.* FROM cardmarket_bulk_products p WHERE $1::uuid IS NOT NULL AND p.last_batch_id=$1),
        staged_prices AS (SELECT p.* FROM cardmarket_bulk_prices p WHERE $1::uuid IS NOT NULL AND p.last_batch_id=$1)
        SELECT
          (SELECT count(*) FROM canonical),
          (SELECT count(*) FROM canonical WHERE mapping_status='pending'), (SELECT count(*) FROM canonical WHERE mapping_status='matched'),
          (SELECT count(*) FROM canonical WHERE mapping_status='unmatched'), (SELECT count(*) FROM canonical WHERE mapping_status='review'),
          (SELECT count(*) FROM canonical WHERE details_synced_at IS NULL), (SELECT count(*) FROM canonical WHERE details_enrichment_failed_at IS NOT NULL),
          (SELECT count(*) FROM canonical WHERE pricing_checked_at IS NULL), (SELECT count(*) FROM staged_products), (SELECT count(*) FROM staged_prices),
          (SELECT count(*) FROM staged_prices WHERE selected_value_eur IS NOT NULL AND selected_value_eur > 0),
          (SELECT count(DISTINCT p.id) FROM staged_products p JOIN canonical c ON c.cardmarket_product_id=p.cardmarket_product_id AND c.mapping_status='matched'),
          (SELECT count(DISTINCT c.id) FROM canonical c JOIN staged_products p ON p.cardmarket_product_id=c.cardmarket_product_id WHERE c.mapping_status='matched'),
          (SELECT count(DISTINCT c.id) FROM canonical c JOIN staged_products p ON p.cardmarket_product_id=c.cardmarket_product_id JOIN staged_prices pr ON pr.cardmarket_product_id=p.cardmarket_product_id WHERE c.mapping_status='matched' AND pr.selected_value_eur > 0),
          (SELECT count(*) FROM single_valuation_snapshots v JOIN canonical c ON c.id=v.card_printing_id AND c.mapping_status='matched' AND v.cardmarket_product_id=c.cardmarket_product_id WHERE v."current?"=true AND v.policy_version=$2),
          (SELECT count(DISTINCT c.id) FROM single_valuation_snapshots v JOIN canonical c ON c.id=v.card_printing_id AND c.mapping_status='matched' AND v.cardmarket_product_id=c.cardmarket_product_id JOIN staged_products p ON p.cardmarket_product_id=c.cardmarket_product_id JOIN staged_prices pr ON pr.cardmarket_product_id=p.cardmarket_product_id AND pr.selected_value_eur > 0 CROSS JOIN latest_batch b WHERE v."current?"=true AND v.policy_version=$2 AND v.fetched_at=b.fetched_at AND v.provider_updated_at=b.price_created_at)
        """,
        [batch_id, @policy]
      )

    case result do
      {:ok, %{rows: [row]}} -> validate_counts_row(row)
      _ -> {:error, :coverage_query_failed}
    end
  rescue
    _ -> {:error, :coverage_query_failed}
  end

  defp validate_counts_row(row) when is_list(row) and length(row) == 16 do
    keys = [
      :canonical_printings,
      :mapping_pending,
      :mapping_matched,
      :mapping_unmatched,
      :mapping_review,
      :details_pending,
      :detail_failures,
      :pricing_check_pending,
      :staged_products,
      :staged_prices,
      :priceable_staged_prices,
      :staged_products_linked,
      :matched_printings_linked,
      :matched_linked_positive_prices,
      :current_valuations,
      :latest_batch_current_valuations
    ]

    # Keep the SQL row deliberately scalar and fail closed if Postgres returns an unexpected shape.
    if Enum.all?(row, &is_integer/1),
      do: {:ok, derive_counts(Map.new(Enum.zip(keys, row)))},
      else: {:error, :invalid_coverage_shape}
  end

  defp validate_counts_row(_), do: {:error, :invalid_coverage_shape}

  defp validate_aggregate(c, batch) do
    statuses = c.mapping_pending + c.mapping_matched + c.mapping_unmatched + c.mapping_review

    if non_negative_counts?(c) and statuses == c.canonical_printings and
         bounded_catalogue_counts?(c) and staging_coherent?(c, batch) and
         links_coherent?(c),
       do: :ok,
       else: {:error, :incoherent_coverage}
  end

  defp non_negative_counts?(c),
    do: Enum.all?(Map.values(c), &is_integer/1) and Enum.all?(Map.values(c), &(&1 >= 0))

  defp bounded_catalogue_counts?(c) do
    c.details_pending <= c.canonical_printings and
      c.detail_failures <= c.details_pending and
      c.pricing_check_pending <= c.canonical_printings
  end

  defp staging_coherent?(c, nil),
    do: c.staged_products == 0 and c.staged_prices == 0 and c.priceable_staged_prices == 0

  defp staging_coherent?(c, b),
    do:
      c.staged_products == b.product_row_count and c.staged_prices == b.singles_price_row_count and
        c.priceable_staged_prices == b.priceable_singles_count

  defp links_coherent?(c),
    do:
      c.staged_products_linked <= c.staged_products and
        c.matched_printings_linked <= c.mapping_matched and
        c.matched_linked_positive_prices <= c.matched_printings_linked and
        c.current_valuations <= c.mapping_matched and
        c.latest_batch_current_valuations <= c.matched_linked_positive_prices

  defp derive_counts(counts) do
    Map.merge(counts, %{
      unmapped_printings: max(counts.canonical_printings - counts.mapping_matched, 0),
      unpriced_matched_printings:
        max(counts.matched_printings_linked - counts.matched_linked_positive_prices, 0)
    })
  end

  # This query intentionally uses the exact card -> product mapping, rather than
  # names or sets, so every reported comparison remains conservative.
  defp comparison(batch, previous) do
    if is_nil(batch), do: {:ok, empty_comparison()}, else: comparison_query(batch, previous)
  end

  defp comparison_query(batch, previous) do
    result =
      TcgCheap.Repo.query(
        """
        WITH canonical AS (
          SELECT cp.id, cp.card_set_id, cp.cardmarket_product_id
          FROM card_printings cp JOIN card_sets cs ON cs.id=cp.card_set_id
          WHERE cs.tcgdex_id <> 'tcgp' AND cp.mapping_status='matched'
        ), tcg AS (
          SELECT DISTINCT v.card_printing_id, v.value_eur FROM single_valuation_snapshots v
          JOIN canonical c ON c.id=v.card_printing_id AND c.cardmarket_product_id=v.cardmarket_product_id
          WHERE v."current?"=true AND v.policy_version='tcgdex_cardmarket_v1'
         ), prices AS (
          SELECT p.cardmarket_product_id, p.selected_value_eur, p.selected_metric
          FROM cardmarket_bulk_prices p WHERE p.last_batch_id=$1::uuid
        ), products AS (
          SELECT p.cardmarket_product_id, p.expansion_id
          FROM cardmarket_bulk_products p WHERE p.last_batch_id=$1::uuid
        ), valuations AS (
          SELECT v.card_printing_id, v.cardmarket_product_id, v.value_eur,
                 v.source_metric, v.fetched_at, v.provider_updated_at
          FROM single_valuation_snapshots v
          JOIN canonical c ON c.id=v.card_printing_id AND c.cardmarket_product_id=v.cardmarket_product_id
          WHERE v."current?"=true
            AND v.policy_version='cardmarket_bulk_v1'
            AND v.fetched_at=$2 AND v.provider_updated_at=$3
         ), valid AS (
           SELECT candidate.*,
             (candidate.approved AND candidate.value_eur=candidate.selected_value_eur
               AND candidate.source_metric=candidate.selected_metric) AS accepted
           FROM (
             SELECT v.*, c.card_set_id, p.selected_value_eur, p.selected_metric,
                     (p.cardmarket_product_id IS NOT NULL AND p.selected_value_eur > 0
                     AND pr.cardmarket_product_id IS NOT NULL
                     AND m.id IS NOT NULL AND
                       ((setmap.cardmarket_mapping_authority='administrator' AND
                        setmap.cardmarket_expansion_id=pr.expansion_id) OR
                       (coalesce(setmap.cardmarket_mapping_authority, '') <> 'administrator' AND
                        m.status='approved')) AND m.source_batch_id=$1::uuid
                   AND m.card_set_id=c.card_set_id AND m.expansion_id=pr.expansion_id
                   AND EXISTS (SELECT 1 FROM cardmarket_card_mapping_evidence e
                     WHERE e.source_batch_id=$1::uuid AND e.card_printing_id=v.card_printing_id
                        AND e.cardmarket_product_id=v.cardmarket_product_id
                        AND e.expansion_mapping_id=m.id AND e.decision IN ('anchor','auto_matched'))) AS approved
             FROM valuations v JOIN canonical c ON c.id=v.card_printing_id
               AND c.cardmarket_product_id=v.cardmarket_product_id
               LEFT JOIN prices p ON p.cardmarket_product_id=c.cardmarket_product_id
               LEFT JOIN products pr ON pr.cardmarket_product_id=c.cardmarket_product_id
                LEFT JOIN cardmarket_expansion_mappings m
                  ON m.source_batch_id=$1::uuid AND m.card_set_id=c.card_set_id
                  AND m.expansion_id=pr.expansion_id
                LEFT JOIN card_sets setmap ON setmap.id=c.card_set_id
           ) candidate
         ), accepted AS (
           SELECT DISTINCT card_printing_id, value_eur
           FROM valid
           WHERE accepted
         )
         SELECT
           (SELECT count(*) FROM tcg),
           (SELECT count(*) FROM accepted),
           (SELECT count(*) FROM tcg t JOIN accepted b ON b.card_printing_id=t.card_printing_id),
           (SELECT count(*) FROM tcg t JOIN accepted b ON b.card_printing_id=t.card_printing_id
             WHERE abs(t.value_eur-b.value_eur)/GREATEST(t.value_eur,b.value_eur) <= $4),
           (SELECT count(*) FROM valuations),
           (SELECT count(*) FROM valid WHERE approved),
           (SELECT count(*) FROM valid WHERE accepted),
           (SELECT count(*) FROM valid WHERE NOT approved)
        """,
        [
          Ecto.UUID.dump!(batch.id),
          batch.fetched_at,
          batch.price_created_at,
          relative_tolerance()
        ]
      )

    case result do
      {:ok, %{rows: [[tcgdex, bulk, overlap, agreement, latest, approved, exact, ambiguous]]}}
      when is_integer(tcgdex) and is_integer(bulk) and is_integer(overlap) ->
        {:ok,
         %{
           current_tcgdex_count: tcgdex,
           current_bulk_count: bulk,
           overlap: overlap,
           bulk_only: max(bulk - overlap, 0),
           tcgdex_only: max(tcgdex - overlap, 0),
           latest_batch_valuation_count: latest,
           latest_batch_approved_valuations: approved,
           latest_batch_exact_valuations: exact,
           overlap_value_agreement: agreement,
           latest_batch_ambiguous_or_unapproved: ambiguous,
           previous_product_row_count: previous && previous.product_row_count
         }}

      _ ->
        {:error, :coverage_query_failed}
    end
  rescue
    _ -> {:error, :coverage_query_failed}
  end

  defp empty_comparison do
    %{
      current_tcgdex_count: 0,
      current_bulk_count: 0,
      overlap: 0,
      bulk_only: 0,
      tcgdex_only: 0,
      latest_batch_valuation_count: 0,
      latest_batch_approved_valuations: 0,
      latest_batch_exact_valuations: 0,
      overlap_value_agreement: 0,
      latest_batch_ambiguous_or_unapproved: 0,
      previous_product_row_count: nil
    }
  end

  defp readiness(latest, previous, counts, comparison, health, policy, catalogue, now) do
    checks = %{
      canonical_catalogue_complete: catalogue.complete?,
      latest_and_previous_batches: batches_ready?(latest, previous),
      source_healthy_and_current: source_ready?(health, policy, now),
      batch_evidence_fresh: batch_evidence_fresh?(latest, policy, now),
      row_count_anomaly_bounded: row_count_anomaly_bounded?(latest, previous),
      materialization_complete: materialization_complete?(latest, comparison, counts),
      approved_mapping_evidence: approved_mapping_evidence?(latest, comparison),
      staged_value_metric_agreement: staged_value_metric_agreement?(comparison),
      no_ambiguous_or_unapproved: comparison.latest_batch_ambiguous_or_unapproved == 0,
      material_coverage_gain:
        coverage_gain?(comparison.current_bulk_count, comparison.current_tcgdex_count),
      overlap_value_agreement: overlap_value_agreement?(comparison)
    }

    failed = checks |> Enum.filter(fn {_key, value} -> not value end) |> Enum.map(&elem(&1, 0))

    %{
      ready?: failed == [],
      checks: checks,
      failed_checks: failed,
      reason: if(failed == [], do: :ready, else: hd(failed))
    }
  end

  # The all_sets run is the durable discovery watermark.  A later failed_sets
  # repair is intentionally not used as a replacement for discovery evidence.
  defp catalogue_evidence(actor, admin?, now) do
    with {:ok, latest} <- latest_catalogue_run(actor, admin?),
         {:ok, running?} <- running_catalogue_run?(actor, admin?),
         {:ok, unresolved_count} <- unresolved_catalogue_issue_count() do
      {:ok, catalogue_projection(latest, running?, unresolved_count, now)}
    end
  end

  defp latest_catalogue_run(actor, admin?) do
    case catalogue_runs(actor, admin?, "completed", :all_sets) do
      {:ok, [latest | _]} -> {:ok, latest}
      {:ok, []} -> {:ok, nil}
      {:error, _} = error -> error
    end
  end

  defp running_catalogue_run?(actor, admin?) do
    case catalogue_runs(actor, admin?, "running", :any_scope) do
      {:ok, [_run | _]} -> {:ok, true}
      {:ok, []} -> {:ok, false}
      {:error, _} = error -> error
    end
  end

  defp catalogue_projection(nil, running?, unresolved_count, _now) do
    %{
      complete?: false,
      running?: running?,
      unresolved_issue_count: unresolved_count,
      discovered_sets: 0,
      synced_sets: 0,
      partial_sets: 0,
      failed_sets: 0,
      excluded_sets: 0,
      started_at: nil,
      completed_at: nil,
      inserted_at: nil,
      run_id: nil
    }
  end

  defp catalogue_projection(%{} = latest, running?, unresolved_count, now) do
    %{
      complete?: catalogue_complete?(latest, running?, unresolved_count, now),
      running?: running?,
      unresolved_issue_count: unresolved_count,
      discovered_sets: catalogue_count(latest, :set_ids, 0, &length/1),
      synced_sets: catalogue_count(latest, :synced_sets),
      partial_sets: catalogue_count(latest, :partial_sets),
      failed_sets: catalogue_count(latest, :failed_sets),
      excluded_sets: catalogue_count(latest, :excluded_sets),
      started_at: catalogue_timestamp(latest, :started_at),
      completed_at: catalogue_timestamp(latest, :completed_at),
      inserted_at: catalogue_timestamp(latest, :inserted_at),
      run_id: catalogue_timestamp(latest, :id)
    }
  end

  defp catalogue_complete?(latest, running?, unresolved_count, now) do
    with true <- catalogue_run_coherent?(latest, now),
         false <- running?,
         0 <- unresolved_count do
      true
    else
      _ -> false
    end
  end

  defp catalogue_count(run, field), do: Map.fetch!(run, field)

  defp catalogue_count(%{} = run, field, _default, transform),
    do: run |> Map.fetch!(field) |> transform.()

  defp catalogue_timestamp(run, field), do: Map.fetch!(run, field)

  defp catalogue_runs(actor, admin?, status, scope) do
    query =
      CatalogueSyncRun
      |> for_read(:read, %{}, actor: actor)
      |> filter(provider_key == "tcgdex_catalogue" and status == ^status)

    query =
      case scope do
        :all_sets -> filter(query, scope == "all_sets")
        :any_scope -> query
      end

    result =
      query
      |> sort(completed_at: :desc, started_at: :desc, inserted_at: :desc, id: :desc)
      |> limit(1)
      |> Ash.read(authorize?: admin?)

    case result do
      {:ok, runs} when is_list(runs) -> {:ok, runs}
      _ -> {:error, :catalogue_sync_run_query_failed}
    end
  rescue
    _ -> {:error, :catalogue_sync_run_query_failed}
  end

  defp catalogue_run_coherent?(%{} = run, now) do
    with true <- catalogue_identity?(run),
         true <- catalogue_progress?(run),
         true <- catalogue_timestamps?(run, now) do
      true
    else
      _ -> false
    end
  end

  defp catalogue_identity?(run),
    do:
      run.provider_key == "tcgdex_catalogue" and run.scope == "all_sets" and
        run.status == "completed"

  defp catalogue_progress?(run) do
    discovered = length(run.set_ids)
    counters = catalogue_counters(run)

    discovered > 0 and valid_catalogue_counters?(counters) and
      is_integer(run.next_index) and run.next_index == discovered and
      Enum.sum(counters) == run.next_index
  end

  defp catalogue_counters(run),
    do: [run.synced_sets, run.partial_sets, run.failed_sets, run.excluded_sets]

  defp valid_catalogue_counters?(counters),
    do: Enum.all?(counters, &is_integer/1) and Enum.all?(counters, &(&1 >= 0))

  defp catalogue_timestamps?(run, now) do
    not is_nil(run.completed_at) and past_utc?(run.started_at, now) and
      past_utc?(run.completed_at, now) and past_utc?(run.inserted_at, now) and
      DateTime.compare(run.completed_at, run.started_at) != :lt
  end

  # ImportIssue's unresolved_catalogue_sets action predates partial issues and
  # therefore cannot represent the complete cutover predicate. Keep this query
  # scalar and bounded: no issue payloads or provider secrets enter the report.
  defp unresolved_catalogue_issue_count do
    result =
      TcgCheap.Repo.query("""
      SELECT count(*)
      FROM (
        SELECT 1
        FROM import_issues
        WHERE provider_key = 'tcgdex_catalogue'
          AND operation = 'card_catalogue_sync'
          AND target_type = 'set'
          AND issue_kind IN ('partial', 'malformed', 'failed')
          AND resolved_at IS NULL
        LIMIT 1001
      ) unresolved
      """)

    case result do
      {:ok, %{rows: [[count]]}} when is_integer(count) -> {:ok, count}
      _ -> {:error, :catalogue_issue_query_failed}
    end
  rescue
    _ -> {:error, :catalogue_issue_query_failed}
  end

  defp batches_ready?(latest, previous), do: not is_nil(latest) and not is_nil(previous)

  defp source_ready?(health, policy, now) do
    health != nil and health.last_status == "succeeded" and
      AcquisitionHealthPolicy.provider_state(policy, @provider, health.last_succeeded_at, now) ==
        :current
  end

  defp batch_evidence_fresh?(
         %{
           fetched_at: fetched,
           completed_at: completed,
           product_created_at: product,
           price_created_at: price
         },
         %{stale_after_seconds: stale},
         now
       )
       when is_map(stale) do
    with {:ok, threshold} <- Map.fetch(stale, @provider),
         true <- is_integer(threshold) and threshold > 0 do
      Enum.all?([fetched, completed, product, price], &fresh_timestamp?(&1, now, threshold))
    else
      _ -> false
    end
  end

  defp batch_evidence_fresh?(_, _, _), do: false

  defp fresh_timestamp?(%DateTime{} = timestamp, %DateTime{} = now, threshold) do
    utc_timestamp?(timestamp) and utc_timestamp?(now) and
      DateTime.compare(timestamp, now) != :gt and DateTime.diff(now, timestamp) < threshold
  end

  defp fresh_timestamp?(_, _, _), do: false
  defp utc_timestamp?(%DateTime{time_zone: "Etc/UTC"}), do: true
  defp utc_timestamp?(_), do: false

  defp row_count_anomaly_bounded?(latest, previous) do
    previous != nil and latest != nil and
      Enum.all?(
        [
          :product_row_count,
          :price_row_count,
          :singles_price_row_count,
          :priceable_singles_count
        ],
        fn key ->
          relative_anomaly?(Map.get(latest, key), Map.get(previous, key))
        end
      )
  end

  defp materialization_complete?(latest, comparison, counts),
    do:
      latest != nil and
        comparison.latest_batch_valuation_count == counts.matched_linked_positive_prices

  defp approved_mapping_evidence?(latest, comparison),
    do:
      latest != nil and
        comparison.latest_batch_approved_valuations == comparison.latest_batch_valuation_count

  defp staged_value_metric_agreement?(comparison),
    do: comparison.latest_batch_exact_valuations == comparison.latest_batch_valuation_count

  defp overlap_value_agreement?(comparison) do
    comparison.overlap >= min_overlap() and comparison.overlap > 0 and
      comparison.overlap_value_agreement / comparison.overlap >= agreement_ratio()
  end

  defp relative_anomaly?(latest, previous)
       when is_integer(latest) and is_integer(previous) and previous > 0,
       do: abs(latest - previous) / previous <= row_anomaly_bound()

  defp relative_anomaly?(_, _), do: false

  defp coverage_config(key, default),
    do: Application.get_env(:tcg_cheap, :cardmarket_bulk_cutover, []) |> Keyword.get(key, default)

  defp relative_tolerance, do: coverage_config(:relative_value_tolerance, 0.05)
  defp row_anomaly_bound, do: coverage_config(:row_count_anomaly_bound, 0.10)

  defp coverage_gain?(bulk, tcg) when is_integer(bulk) and is_integer(tcg) do
    bulk - tcg >= coverage_config(:minimum_coverage_gain, 100) and
      (tcg == 0 or bulk / tcg >= coverage_config(:minimum_coverage_ratio, 1.10))
  end

  defp coverage_gain?(_, _), do: false
  defp min_overlap, do: coverage_config(:minimum_overlap, 100)
  defp agreement_ratio, do: coverage_config(:minimum_agreement_ratio, 0.95)

  defp source_health(actor, admin?) do
    case TcgCheap.Operations.list_source_health([@provider], actor: actor, authorize?: admin?) do
      {:ok, [health | _]} -> {:ok, health}
      {:ok, []} -> {:ok, nil}
      _ -> {:error, :source_health_query_failed}
    end
  end

  defp validate_health(nil, _), do: :ok

  defp validate_health(h, now) do
    times = [h.last_started_at, h.last_succeeded_at, h.last_failed_at, h.circuit_opened_at]

    if valid_health_times?(times, now) and valid_health_counters?(h) and
         valid_health_state?(h),
       do: :ok,
       else: {:error, :invalid_source_health_evidence}
  end

  defp valid_health_times?(times, now) do
    Enum.all?(times, fn
      nil -> true
      value -> past_utc?(value, now)
    end)
  end

  defp valid_health_counters?(h) do
    is_integer(h.consecutive_failures) and h.consecutive_failures >= 0 and
      is_integer(h.circuit_failure_streak) and h.circuit_failure_streak >= 0
  end

  defp valid_health_state?(h) do
    category? =
      is_nil(h.last_failure_category) or
        h.last_failure_category in ~w(budget rate_limit timeout transport provider_response persistence configuration local_input unknown)

    evidence_ordered? = evidence_ordered?(h)

    status? = valid_status?(h)

    status? and category? and evidence_ordered? and
      (is_nil(h.circuit_opened_at) or
         (h.circuit_failure_streak > 0 and not is_nil(h.last_failed_at) and
            DateTime.compare(h.circuit_opened_at, h.last_failed_at) != :gt))
  end

  defp valid_status?(%{last_status: nil} = h),
    do:
      is_nil(h.last_succeeded_at) and is_nil(h.last_failed_at) and is_nil(h.last_failure_category) and
        h.consecutive_failures == 0

  defp valid_status?(%{last_status: "succeeded"} = h),
    do:
      not is_nil(h.last_succeeded_at) and is_nil(h.last_failure_category) and
        h.consecutive_failures == 0 and h.circuit_failure_streak == 0 and
        is_nil(h.circuit_opened_at)

  defp valid_status?(%{last_status: status} = h)
       when status in ["retryable_failure", "failed", "cancelled"],
       do:
         not is_nil(h.last_failed_at) and not is_nil(h.last_failure_category) and
           h.consecutive_failures > 0

  defp valid_status?(_), do: false

  defp evidence_ordered?(%{last_succeeded_at: nil}), do: true
  defp evidence_ordered?(%{last_failed_at: nil}), do: true

  defp evidence_ordered?(%{last_status: "succeeded"} = h),
    do: DateTime.compare(h.last_succeeded_at, h.last_failed_at) != :lt

  defp evidence_ordered?(h), do: DateTime.compare(h.last_failed_at, h.last_succeeded_at) != :lt

  defp source_projection(nil, _policy, _now), do: nil

  defp source_projection(h, policy, now) do
    %{
      last_status: h.last_status,
      last_succeeded_at: h.last_succeeded_at,
      last_failed_at: h.last_failed_at,
      last_failure_category: h.last_failure_category,
      consecutive_failures: h.consecutive_failures,
      circuit_failure_streak: h.circuit_failure_streak,
      circuit_opened_at: h.circuit_opened_at,
      freshness:
        AcquisitionHealthPolicy.provider_state(policy, @provider, h.last_succeeded_at, now)
    }
  end
end
