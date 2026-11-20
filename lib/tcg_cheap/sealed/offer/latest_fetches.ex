defmodule TcgCheap.Sealed.Offer.LatestFetches do
  @moduledoc """
  Per shop, the time of its latest fetch: the newest `last_seen_at` among its
  offers seen since the given time. Successful empty fetches also count, using
  an independent shop/kind marker for each offer resource.
  """

  use Ash.Resource.Actions.Implementation

  import Ecto.Query

  alias AshPostgres.DataLayer.Info
  alias TcgCheap.Sealed.Offer

  # Pages read this on every render. Grouping by shop reads every offer seen
  # since `since`; Postgres has no loose index scan, so this walks the
  # resource's (shop, last_seen_at) index backwards instead, one lookup per
  # shop: the last entry before the previous shop is the next shop's newest
  # offer. A shop's newest time since `since` is its newest time if that is
  # recent enough.
  @latest_sql """
  WITH RECURSIVE latest(shop, seen_at) AS (
    (SELECT shop, last_seen_at FROM :table ORDER BY shop DESC, last_seen_at DESC LIMIT 1)
    UNION ALL
    SELECT next.shop, next.last_seen_at
      FROM latest,
           LATERAL (SELECT o.shop, o.last_seen_at FROM :table o
                     WHERE o.shop < latest.shop
                     ORDER BY o.shop DESC, o.last_seen_at DESC LIMIT 1) AS next
  )
  SELECT shop, seen_at FROM latest WHERE seen_at >= $1
  """

  @impl true
  def run(input, opts, _context) do
    since = input.arguments.since
    resource = Keyword.get(opts, :resource, Offer)
    sql = String.replace(@latest_sql, ":table", Info.table(resource))

    %{rows: rows} = TcgCheap.Repo.query!(sql, [since])

    latest =
      Map.new(rows, fn [shop, seen_at] -> {shop, DateTime.from_naive!(seen_at, "Etc/UTC")} end)

    {:ok, with_empty_fetches(latest, resource, since)}
  end

  defp with_empty_fetches(latest, resource, since) do
    kind = if resource == Offer, do: :sealed, else: :single

    from(fetch in TcgCheap.Sealed.ShopFetch,
      where: fetch.fetched_at >= ^since and fetch.kind == ^kind,
      select: {fetch.shop, fetch.fetched_at}
    )
    |> TcgCheap.Repo.all()
    |> Map.new()
    |> then(
      &Map.merge(latest, &1, fn _shop, from_offer, fetched ->
        Enum.max([from_offer, fetched], DateTime)
      end)
    )
  end
end
