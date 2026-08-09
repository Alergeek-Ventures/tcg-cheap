defmodule TcgCheap.Catalogue.PublicSealedProductProjection do
  @moduledoc "Pure projection of already-filtered public sealed-product offers."

  @sold_out_window_seconds 30 * 24 * 60 * 60

  def project(mappings) when is_list(mappings), do: project(mappings, DateTime.utc_now())

  def project(mappings, %DateTime{} = as_of) when is_list(mappings) do
    mappings
    |> Enum.map(&offer/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.group_by(fn %{retailer: retailer} -> retailer.id end)
    |> Enum.flat_map(&select_retailer(&1, as_of))
    |> sort_offers()
    |> split_offers()
  end

  defp offer(%{retailer_listing: %{retailer: retailer} = listing} = mapping) do
    %{mapping: mapping, listing: listing, retailer: retailer}
  end

  defp offer(_), do: nil

  defp select_retailer({_retailer_id, offers}, as_of) do
    current = Enum.filter(offers, &(&1.listing.stock_status == "in_stock"))
    sold_out = Enum.filter(offers, &recent_sold_out?(&1, as_of))

    Enum.reject([cheapest_if_present(current), most_recent_if_present(sold_out)], &is_nil/1)
  end

  defp cheapest_if_present([]), do: nil
  defp cheapest_if_present(offers), do: cheapest(offers)

  defp most_recent_if_present([]), do: nil
  defp most_recent_if_present(offers), do: most_recent(offers)

  defp recent_sold_out?(offer, as_of) do
    age = DateTime.diff(as_of, offer.listing.last_checked_at, :second)
    offer.listing.stock_status == "sold_out" and age >= 0 and age <= @sold_out_window_seconds
  end

  defp cheapest([first | rest]) do
    Enum.reduce(rest, first, &lower_price/2)
  end

  defp most_recent([first | rest]) do
    Enum.reduce(rest, first, &newer_check/2)
  end

  defp lower_price(offer, best) do
    case Decimal.compare(offer.listing.current_price_pln, best.listing.current_price_pln) do
      :lt -> offer
      :eq -> lower_listing_id(offer, best)
      :gt -> best
    end
  end

  defp newer_check(offer, best) do
    case DateTime.compare(offer.listing.last_checked_at, best.listing.last_checked_at) do
      :gt -> offer
      :eq -> higher_listing_id(offer, best)
      :lt -> best
    end
  end

  defp lower_listing_id(offer, best) when offer.listing.id < best.listing.id, do: offer
  defp lower_listing_id(_offer, best), do: best

  defp higher_listing_id(offer, best) when offer.listing.id > best.listing.id, do: offer
  defp higher_listing_id(_offer, best), do: best

  defp sort_offers(offers) do
    Enum.sort(offers, fn left, right ->
      case {left.listing.stock_status, right.listing.stock_status} do
        {"in_stock", "in_stock"} ->
          price = Decimal.compare(left.listing.current_price_pln, right.listing.current_price_pln)
          price == :lt or (price == :eq and current_tie_key(left) < current_tie_key(right))

        {"sold_out", "sold_out"} ->
          sold_out_before?(left, right)

        {"in_stock", _} ->
          true

        _ ->
          false
      end
    end)
  end

  defp current_tie_key(%{listing: listing, retailer: retailer}),
    do: {retailer.name, retailer.slug, listing.source_listing_id, listing.id}

  defp sold_out_tie_key(%{listing: listing, retailer: retailer}),
    do: {retailer.name, retailer.slug, listing.source_listing_id, listing.id}

  defp sold_out_before?(left, right) do
    case DateTime.compare(left.listing.last_checked_at, right.listing.last_checked_at) do
      :gt -> true
      :lt -> false
      :eq -> sold_out_tie_key(left) < sold_out_tie_key(right)
    end
  end

  defp split_offers(offers) do
    %{
      current: Enum.filter(offers, &(&1.listing.stock_status == "in_stock")),
      sold_out: Enum.filter(offers, &(&1.listing.stock_status == "sold_out"))
    }
  end
end
