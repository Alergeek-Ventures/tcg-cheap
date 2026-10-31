defmodule TcgCheap.Sealed.AgentTools.OfferList do
  @moduledoc """
  One page of current unmatched offers, current automatically matched offers
  or manual decisions (`list:` option), filtered by shop, title and product.
  """

  use Ash.Resource.Actions.Implementation

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.Json
  alias TcgCheap.Sealed.Matcher

  @impl true
  def run(input, opts, _context) do
    args = input.arguments
    now = DateTime.utc_now()

    offers =
      opts[:list]
      |> offers(now)
      |> Enum.filter(&wanted?(&1, args))
      |> Enum.sort_by(&{&1.shop, &1.title, &1.id})

    {:ok, page(opts[:list], offers, args, now)}
  end

  defp offers(:unmatched, now),
    do: now |> Sealed.current_offers() |> Enum.reject(&(&1.product_id || &1.manual?))

  defp offers(:matched, now),
    do: now |> Sealed.current_offers() |> Enum.filter(&(&1.product_id && not &1.manual?))

  defp offers(:manual, _now), do: Sealed.list_manual_offers!()

  defp wanted?(offer, args) do
    (is_nil(args[:shop]) or offer.shop == args.shop) and
      (is_nil(args[:product_id]) or offer.product_id == args.product_id) and
      (is_nil(args[:title]) or
         String.contains?(Matcher.normalize(offer.title), Matcher.normalize(args.title)))
  end

  defp page(:unmatched, offers, args, _now) do
    {kept, excluded} = Enum.split_with(offers, &(not Matcher.excluded?(&1.title)))
    listed = if args.include_excluded, do: offers, else: kept
    slice = Enum.slice(listed, args.offset, args.limit)

    index =
      if slice != [], do: Matcher.index(Sealed.list_products!(), Sealed.known_eans())

    %{
      total: length(listed),
      excluded_total: length(excluded),
      limit: args.limit,
      offset: args.offset,
      offers: Enum.map(slice, &Map.merge(Json.offer(&1), matcher(Matcher.match(&1, index))))
    }
  end

  defp page(:matched, offers, args, _now) do
    slice = offers |> Enum.slice(args.offset, args.limit) |> Ash.load!(:product, domain: Sealed)
    paged(offers, slice, args, &Json.offer/1)
  end

  defp page(:manual, offers, args, now) do
    current = now |> Sealed.current_offers() |> MapSet.new(& &1.id)
    slice = offers |> Enum.slice(args.offset, args.limit) |> Ash.load!(:product, domain: Sealed)
    paged(offers, slice, args, &Map.put(Json.offer(&1), :current, MapSet.member?(current, &1.id)))
  end

  defp paged(offers, slice, args, to_json) do
    %{
      total: length(offers),
      limit: args.limit,
      offset: args.offset,
      offers: Enum.map(slice, to_json)
    }
  end

  defp matcher({:excluded, reason}), do: %{matcher: :excluded, reason: reason}
  defp matcher({:matched, _id}), do: %{matcher: :matched}
  defp matcher(result), do: %{matcher: result}
end
