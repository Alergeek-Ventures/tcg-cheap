defmodule TcgCheap.Pricing.Sealed.Actions.HomepagePriceChanges do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias TcgCheap.Pricing.HomepageSealedPriceChange
  alias TcgCheap.Repo

  @version "sealed_market_daily_v1"

  @impl true
  def run(input, _opts, _context) do
    %{as_of: as_of, limit: limit} = input.arguments

    case Repo.query(
           """
           WITH latest AS (
             SELECT DISTINCT ON (a.sealed_product_id) a.*
             FROM sealed_daily_aggregates a
             WHERE a.calculation_version = $1
               AND a.aggregate_date <= ($2::timestamptz AT TIME ZONE 'UTC')::date
             ORDER BY a.sealed_product_id, a.aggregate_date DESC, a.calculated_at DESC, a.id DESC
           ), current_ready AS (
             SELECT l.*
             FROM latest l
             WHERE l.status = 'ready' AND l.source_mapping_confident = TRUE AND l.benchmark_pln IS NOT NULL
               AND l.aggregate_date >= (($2::timestamptz AT TIME ZONE 'UTC')::date - 1)
               AND l.latest_nonfuture_checked_at IS NOT NULL
               AND l.latest_nonfuture_checked_at <= l.calculated_at
               AND l.latest_nonfuture_checked_at <= $2::timestamptz
               AND l.latest_nonfuture_checked_at >= ($2::timestamptz - interval '7 days')
               AND l.calculated_at <= $2::timestamptz
           ), history AS (
             SELECT a.sealed_product_id,
               (array_agg(a.benchmark_pln ORDER BY a.aggregate_date ASC, a.calculated_at ASC, a.id ASC))[1] AS start_benchmark,
               (array_agg(a.aggregate_date ORDER BY a.aggregate_date ASC, a.calculated_at ASC, a.id ASC))[1] AS start_date,
               count(*) AS point_count,
               max(a.aggregate_date) - min(a.aggregate_date) AS span
             FROM sealed_daily_aggregates a
             JOIN current_ready c ON c.sealed_product_id = a.sealed_product_id
             WHERE a.calculation_version = $1 AND a.status = 'ready'
               AND a.source_mapping_confident = TRUE
               AND a.benchmark_pln IS NOT NULL
               AND a.aggregate_date BETWEEN (($2::timestamptz AT TIME ZONE 'UTC')::date - 29)
                 AND ($2::timestamptz AT TIME ZONE 'UTC')::date
               AND a.calculated_at <= $2::timestamptz
               AND (a.latest_nonfuture_checked_at IS NULL OR a.latest_nonfuture_checked_at <= a.calculated_at)
             GROUP BY a.sealed_product_id
             HAVING count(*) >= 2 AND max(a.aggregate_date) - min(a.aggregate_date) >= 1
           ), qualified AS (
             SELECT p.id, p.slug, p.name, p.product_type, p.series_name, p.set_name,
               p.release_date, p.distribution_status, h.start_benchmark,
               c.benchmark_pln AS current_benchmark, h.start_date, c.aggregate_date AS current_date,
               c.latest_nonfuture_checked_at, c.calculated_at,
               round(((c.benchmark_pln - h.start_benchmark) / NULLIF(h.start_benchmark, 0)) * 100, 2) AS change_percent,
               abs(((c.benchmark_pln - h.start_benchmark) / NULLIF(h.start_benchmark, 0)) * 100) AS movement
             FROM current_ready c
             JOIN history h ON h.sealed_product_id = c.sealed_product_id
             JOIN sealed_products p ON p.id = c.sealed_product_id
             WHERE p.publication_status = 'approved' AND p.release_date <= ($2::timestamptz AT TIME ZONE 'UTC')::date
                AND p.market = 'PL' AND p.language = 'en' AND p.officially_distributed
                AND p.distribution_status IN ('current', 'discontinued')
                AND btrim(p.description) <> '' AND cardinality(p.contents) > 0
                AND btrim(p.official_url) <> '' AND btrim(p.details_source) <> ''
                AND btrim(p.details_source_url) <> ''
                AND (
                  (btrim(p.image_url) <> '' AND btrim(p.image_source) <> ''
                    AND btrim(p.image_source_url) <> '')
                  OR EXISTS (
                    SELECT 1
                    FROM listing_product_mappings m
                    JOIN retailer_listings rl ON rl.id = m.retailer_listing_id
                    JOIN retailers r ON r.id = rl.retailer_id
                    WHERE m.confirmed_product_id = p.id AND m.status = 'matched'
                      AND rl.status = 'active' AND r.status = 'active'
                      AND btrim(rl.image_url) <> ''
                  )
                )
                AND (p.product_type NOT IN (
                  'booster_pack', 'sleeved_booster', 'booster_bundle', 'booster_box',
                  'elite_trainer_box', 'tin', 'collection_box', 'trainer_toolkit'
                ) OR (p.pack_count IS NOT NULL AND p.pack_count > 0
                  AND p.cards_per_pack IS NOT NULL AND p.cards_per_pack > 0))
                AND h.start_benchmark > 0
               AND abs(((c.benchmark_pln - h.start_benchmark) / NULLIF(h.start_benchmark, 0)) * 100) >= 2
           ), balanced AS (
             (SELECT * FROM qualified WHERE change_percent > 0 ORDER BY movement DESC, current_date DESC, id ASC LIMIT ((LEAST(GREATEST($3::integer, 1), 10) + 1) / 2))
             UNION ALL
             (SELECT * FROM qualified WHERE change_percent < 0 ORDER BY movement DESC, current_date DESC, id ASC LIMIT ((LEAST(GREATEST($3::integer, 1), 10) + 1) / 2))
           )
           SELECT id, slug, name, product_type, series_name, set_name, release_date, distribution_status,
             start_benchmark, current_benchmark, change_percent, start_date, current_date,
             latest_nonfuture_checked_at, calculated_at
           FROM balanced ORDER BY movement DESC, current_date DESC, id ASC LIMIT LEAST(GREATEST($3::integer, 1), 10)
           """,
           [@version, as_of, limit]
         ) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &to_change/1)}
      {:error, reason} -> {:error, {:homepage_sealed_price_changes_query_failed, reason}}
    end
  rescue
    exception -> {:error, {:homepage_sealed_price_changes_query_failed, exception}}
  end

  defp to_change([
         id,
         slug,
         name,
         product_type,
         series,
         set_name,
         release,
         distribution,
         start_value,
         current_value,
         change,
         start_date,
         current_date,
         checked,
         calculated
       ]) do
    %HomepageSealedPriceChange{
      sealed_product_id: uuid(id),
      slug: slug,
      name: name,
      product_type: product_type,
      series_name: series,
      set_name: set_name,
      release_date: release,
      distribution_status: distribution,
      start_benchmark_pln: start_value,
      current_benchmark_pln: current_value,
      change_percent: change,
      start_date: start_date,
      current_date: current_date,
      current_checked_at: utc_datetime(checked),
      current_calculated_at: utc_datetime(calculated)
    }
  end

  defp uuid(value) when is_binary(value) and byte_size(value) == 16, do: Ecto.UUID.load!(value)
  defp uuid(value), do: value
  defp utc_datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
  defp utc_datetime(value), do: value
end
