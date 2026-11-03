defmodule TcgCheap.Sealed.Offer.LatestFetches do
  @moduledoc """
  Per shop, the time of its latest fetch: the newest `last_seen_at` among its
  offers seen since the given time. Grouped in the database, which reads two
  columns instead of every offer. Successful empty fetches
  also count, using an independent shop/kind marker for each offer resource.
  """

  use Ash.Resource.Actions.Implementation

  import Ecto.Query

  alias TcgCheap.Sealed.Offer

  @impl true
  def run(input, opts, _context) do
    since = input.arguments.since
    resource = Keyword.get(opts, :resource, Offer)

    latest =
      from(offer in resource,
        where: offer.last_seen_at >= ^since,
        group_by: offer.shop,
        select: {offer.shop, max(offer.last_seen_at)}
      )
      |> TcgCheap.Repo.all()
      |> Map.new()

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
