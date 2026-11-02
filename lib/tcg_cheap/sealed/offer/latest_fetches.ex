defmodule TcgCheap.Sealed.Offer.LatestFetches do
  @moduledoc """
  Per shop, the time of its latest fetch: the newest `last_seen_at` among its
  offers seen since the given time. Grouped in the database, which reads two
  columns instead of every offer.
  """

  use Ash.Resource.Actions.Implementation

  import Ecto.Query

  alias TcgCheap.Sealed.Offer

  @impl true
  def run(input, _opts, _context) do
    since = input.arguments.since

    {:ok,
     from(offer in Offer,
       where: offer.last_seen_at >= ^since,
       group_by: offer.shop,
       select: {offer.shop, max(offer.last_seen_at)}
     )
     |> TcgCheap.Repo.all()
     |> Map.new()}
  end
end
