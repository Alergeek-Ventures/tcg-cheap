defmodule TcgCheap.Sealed.Expansions do
  @moduledoc """
  The expansions' names and the newest sets, read for every page of the
  site. They change with catalogue syncs and shop fetches, not with a search
  or a page, so they are shared (`TcgCheap.Sealed.Cache`).
  """

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Cache, ProductFacets, TcgdexSet}

  # How soon after the expansion names were read an unknown expansion id may
  # read them again: ids come from URLs, so crawlers ask for ones that do not
  # exist, and each replaced entry makes the VM scan every process.
  @names_refresh_gap_ms :timer.minutes(1)

  @doc """
  Every expansion's name by Cardmarket expansion id: the English TCGdex
  sets' and the sealed products' (which win). A catalogue sync can add an
  expansion while the names are cached: when one of `required_ids` is not
  among them they are read again, unless that was done a minute ago.
  """
  @spec names([integer()]) :: %{integer() => String.t()}
  def names(required_ids \\ []) do
    Cache.fetch_covering(
      :expansion_names,
      &read_names/0,
      fn names -> Enum.all?(required_ids, &Map.has_key?(names, &1)) end,
      @names_refresh_gap_ms
    )
  end

  @doc """
  The English sets with products in stock, newest first, as the home page's
  set list leads with them (`ProductFacets.read/1`): the sets every page's
  footer links. Shared for a few minutes.
  """
  @spec newest(pos_integer()) :: [%{id: integer(), name: String.t()}]
  def newest(count) do
    :newest_expansions
    |> Cache.fetch(fn ->
      %{query: "", kind: nil, edition: :en, expansion: nil}
      |> ProductFacets.read()
      |> Map.fetch!(:expansions)
      |> Enum.map(&Map.take(&1, [:id, :name]))
    end)
    |> Enum.take(count)
  end

  defp read_names do
    catalogue =
      Sealed.list_tcgdex_sets!(query: [filter: [language: "en"]])
      |> TcgdexSet.by_expansion()
      |> Map.new(fn {id, set} -> {id, set.name} end)

    sealed =
      ProductFacets.read(%{query: "", kind: nil, edition: nil, expansion: nil}).expansions
      |> Map.new(&{&1.id, &1.name})

    Map.merge(catalogue, sealed)
  end
end
