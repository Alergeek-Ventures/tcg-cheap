defmodule TcgCheap.Sealed.ProductFacets do
  @moduledoc """
  What the language, kind and expansion filters of the product list offer
  under the other filters (`TcgCheap.Sealed.ProductList`).
  """

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{ExpansionLogo, Kinds, ProductList, Regions}

  @doc """
  Product counts per language edition and per kind (the chosen kind stays,
  with none), and the named expansions (English ones first, then the other
  language editions in turn; within each, those with a product in stock
  first, then newest first) with their logo when one is
  mirrored: the English TCGdex logo, else the one set for the expansion.
  """
  @spec read(ProductList.filters()) :: %{
          regions: [{atom(), pos_integer()}],
          kinds: [{atom(), non_neg_integer()}],
          expansions: [
            %{
              id: integer(),
              name: String.t(),
              region: atom(),
              logo_url: String.t() | nil,
              count: non_neg_integer()
            }
          ]
        }
  def read(filters) do
    # One grouped read for all three: each count leaves out its own filter.
    groups = Sealed.count_product_facets!(filters.query)

    regions =
      groups
      |> on_shelf(filters.kind)
      |> matching(cardmarket_expansion_id: filters.expansion)
      |> sum_by(& &1.region)

    kinds =
      groups
      |> matching(region: filters.region, cardmarket_expansion_id: filters.expansion)
      |> sum_by(& &1.kind)

    %{
      regions: for(region <- Regions.all(), count = regions[region], do: {region, count}),
      kinds:
        for(
          kind <- Kinds.all(),
          count = kinds[kind] || (filters.kind && kind in Kinds.members(filters.kind) && 0),
          do: {kind, count}
        ),
      expansions:
        groups
        |> on_shelf(filters.kind)
        |> matching(region: filters.region)
        |> expansions(filters)
    }
  end

  defp on_shelf(groups, nil), do: groups
  defp on_shelf(groups, kind), do: Enum.filter(groups, &(&1.kind in Kinds.members(kind)))

  defp matching(groups, filters) do
    Enum.filter(groups, fn group ->
      Enum.all?(filters, fn {field, value} ->
        is_nil(value) or Map.fetch!(group, field) == value
      end)
    end)
  end

  # Products per key, summed over the groups.
  defp sum_by(groups, key) do
    Enum.reduce(
      groups,
      %{},
      &Map.update(&2, key.(&1), &1.count, fn count -> count + &1.count end)
    )
  end

  defp expansions(groups, filters) do
    logos = ExpansionLogo.mirrored_urls()

    expansions =
      groups
      |> named_expansions(logos)
      |> Enum.sort_by(&(&1.newest || ~D[1990-01-01]), {:desc, Date})
      |> Enum.sort_by(&(!&1.available?))
      |> Enum.sort_by(&Enum.find_index(Regions.all(), fn region -> region == &1.region end))
      |> Enum.map(&Map.drop(&1, [:available?, :newest]))

    expansions ++ chosen_elsewhere(filters.expansion, expansions, logos)
  end

  # The chosen expansion stays listed, with no products, when the other
  # filters leave none of it.
  defp chosen_elsewhere(nil, _expansions, _logos), do: []

  defp chosen_elsewhere(id, expansions, logos) do
    if Enum.any?(expansions, &(&1.id == id)) do
      []
    else
      Sealed.count_product_facets!()
      |> Enum.filter(&(&1.cardmarket_expansion_id == id))
      |> named_expansions(logos)
      |> Enum.map(&(&1 |> Map.drop([:available?, :newest]) |> Map.put(:count, 0)))
    end
  end

  defp named_expansions(groups, logos) do
    groups
    |> Enum.filter(&(&1.cardmarket_expansion_id && &1.set_name))
    |> Enum.group_by(& &1.cardmarket_expansion_id)
    |> Enum.map(fn {id, groups} ->
      %{
        id: id,
        name: most_common(groups, & &1.set_name),
        region: most_common(groups, & &1.region),
        logo_url: Map.get(logos, id),
        count: Enum.sum_by(groups, & &1.count),
        available?: Enum.any?(groups, & &1.available?),
        newest:
          groups
          |> Enum.map(& &1.newest)
          |> Enum.reject(&is_nil/1)
          |> Enum.max(Date, fn -> nil end)
      }
    end)
  end

  defp most_common(groups, field),
    do: groups |> sum_by(field) |> Enum.max_by(&elem(&1, 1)) |> elem(0)
end
