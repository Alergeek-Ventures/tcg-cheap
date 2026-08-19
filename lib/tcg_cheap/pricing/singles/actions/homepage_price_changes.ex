defmodule TcgCheap.Pricing.Singles.Actions.HomepagePriceChanges do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias TcgCheap.Pricing.Singles.HomepagePriceChange
  alias TcgCheap.Repo

  @policy "tcgdex_cardmarket_v1"

  @impl true
  def run(input, _opts, _context) do
    %{as_of: as_of, limit: limit} = input.arguments

    case query([@policy, as_of, limit]) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &to_change/1)}
      {:error, reason} -> {:error, {:homepage_price_changes_query_failed, reason}}
    end
  rescue
    exception -> {:error, {:homepage_price_changes_query_failed, exception}}
  end

  defp query(params) do
    Repo.query(
      """
      WITH daily AS (
        SELECT DISTINCT ON (s.card_printing_id, (s.fetched_at AT TIME ZONE 'UTC')::date)
          s.card_printing_id, s.value_eur, s.fetched_at, s."current?",
          (s.fetched_at AT TIME ZONE 'UTC')::date AS snapshot_date,
          s.id
        FROM single_valuation_snapshots AS s
        WHERE s.policy_version = $1
          AND s.fetched_at >= ((($2::timestamptz AT TIME ZONE 'UTC')::date - 29) AT TIME ZONE 'UTC')
          AND s.fetched_at <= $2::timestamptz
          AND EXISTS (
            SELECT 1
            FROM card_printings AS current_cp
            WHERE current_cp.id = s.card_printing_id
              AND current_cp.mapping_status = 'matched'
              AND current_cp.cardmarket_product_id > 0
               AND current_cp.cardmarket_product_id = s.cardmarket_product_id
              AND current_cp.collection_scopes <> '{}'
              AND (current_cp.collection_expires_on IS NULL OR current_cp.collection_expires_on >= CURRENT_DATE)
          )
        ORDER BY s.card_printing_id, (s.fetched_at AT TIME ZONE 'UTC')::date,
          s.fetched_at DESC, s.id DESC
      ),
      evidence AS (
        SELECT card_printing_id,
          (array_agg(value_eur ORDER BY snapshot_date ASC, fetched_at ASC, id ASC))[1] AS start_value_eur,
          (array_agg(snapshot_date ORDER BY snapshot_date ASC, fetched_at ASC, id ASC))[1] AS start_date,
          (array_agg(value_eur ORDER BY snapshot_date DESC, fetched_at DESC, id DESC))[1] AS current_value_eur,
          (array_agg(snapshot_date ORDER BY snapshot_date DESC, fetched_at DESC, id DESC))[1] AS current_date,
          (array_agg(fetched_at ORDER BY snapshot_date DESC, fetched_at DESC, id DESC))[1] AS current_fetched_at,
          (array_agg("current?" ORDER BY snapshot_date DESC, fetched_at DESC, id DESC))[1] AS newest_current
        FROM daily
        GROUP BY card_printing_id
          HAVING count(*) >= 2
            AND max(snapshot_date) - min(snapshot_date) >= 1
      )
      , qualified AS (
        SELECT cp.id, cp.tcgdex_id, cp.name, cp.set_name, cp.collector_number,
          cp.rarity, cp.image_url, e.start_value_eur, e.current_value_eur,
          round(((e.current_value_eur - e.start_value_eur) / NULLIF(e.start_value_eur, 0)) * 100, 2) AS change_percent,
          e.start_date, e.current_date, e.current_fetched_at,
          abs(((e.current_value_eur - e.start_value_eur) / NULLIF(e.start_value_eur, 0)) * 100) AS movement
        FROM evidence AS e
        JOIN card_printings AS cp ON cp.id = e.card_printing_id
        WHERE e.newest_current
            AND abs(((e.current_value_eur - e.start_value_eur) / NULLIF(e.start_value_eur, 0)) * 100) >= 2
      ), balanced AS (
        (SELECT * FROM qualified WHERE change_percent > 0
         ORDER BY movement DESC, current_fetched_at DESC, tcgdex_id ASC LIMIT ((LEAST(GREATEST($3::integer, 1), 10) + 1) / 2))
        UNION ALL
        (SELECT * FROM qualified WHERE change_percent < 0
         ORDER BY movement DESC, current_fetched_at DESC, tcgdex_id ASC LIMIT ((LEAST(GREATEST($3::integer, 1), 10) + 1) / 2))
      )
      SELECT id, tcgdex_id, name, set_name, collector_number, rarity, image_url,
        start_value_eur, current_value_eur, change_percent, start_date, balanced.current_date AS current_date, current_fetched_at
      FROM balanced
      ORDER BY movement DESC, current_fetched_at DESC, tcgdex_id ASC
      LIMIT LEAST(GREATEST($3::integer, 1), 10)
      """,
      params
    )
  end

  defp to_change([
         id,
         tcgdex_id,
         name,
         set_name,
         collector_number,
         rarity,
         image_url,
         start_value_eur,
         current_value_eur,
         change_percent,
         start_date,
         current_date,
         current_fetched_at
       ]) do
    %HomepagePriceChange{
      card_printing_id: uuid(id),
      tcgdex_id: tcgdex_id,
      name: name,
      set_name: set_name,
      collector_number: collector_number,
      rarity: rarity,
      image_url: image_url,
      start_value_eur: start_value_eur,
      current_value_eur: current_value_eur,
      change_percent: change_percent,
      start_date: start_date,
      current_date: current_date,
      current_fetched_at: utc_datetime(current_fetched_at)
    }
  end

  defp uuid(value) when is_binary(value) and byte_size(value) == 16, do: Ecto.UUID.load!(value)
  defp uuid(value) when is_binary(value), do: value

  defp utc_datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
  defp utc_datetime(value), do: value
end
