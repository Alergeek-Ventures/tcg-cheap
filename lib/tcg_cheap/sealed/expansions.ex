defmodule TcgCheap.Sealed.Expansions do
  @moduledoc """
  The expansions' names and the newest sets, read for every page of the
  site. They change with catalogue syncs and shop fetches, not with a search
  or a page, so they are shared (`TcgCheap.Sealed.Cache`).
  """

  alias TcgCheap.Cards
  alias TcgCheap.Sealed.{Cache, ProductFacets}

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
  The English sets with products in stock, newest first, as the products
  list's set column leads with them (`ProductFacets.read/1`): the sets every
  page's footer links. Shared for a few minutes.
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

  @doc """
  The English sets with products in stock, latest release first (the
  TCGdex set's `released_on`; sets without one last), with their logo, as
  the home page announces them. Shared for a few minutes.
  """
  @spec latest(pos_integer()) :: [
          %{
            id: integer(),
            name: String.t(),
            logo_url: String.t() | nil,
            released_on: Date.t() | nil
          }
        ]
  def latest(count) do
    :latest_expansions
    |> Cache.fetch(fn ->
      expansions =
        %{query: "", kind: nil, edition: :en, expansion: nil}
        |> ProductFacets.read()
        |> Map.fetch!(:expansions)

      released =
        Cards.list_sets!(
          query: [
            filter: [cardmarket_expansion_id: [in: Enum.map(expansions, & &1.id)]],
            select: [:cardmarket_expansion_id, :language, :name, :released_on]
          ]
        )
        |> Cards.Set.by_expansion()

      expansions
      |> Enum.map(fn expansion ->
        expansion
        |> Map.take([:id, :name, :logo_url])
        |> Map.put(:released_on, get_in(released, [expansion.id, Access.key(:released_on)]))
      end)
      # The list's own order follows its newest product; news follow the release day.
      |> Enum.sort_by(&(&1.released_on || ~D[0000-01-01]), {:desc, Date})
    end)
    |> Enum.take(count)
  end

  defp read_names do
    catalogue =
      Cards.list_sets!(query: [filter: [language: "en"]])
      |> Cards.Set.by_expansion()
      |> Map.new(fn {id, set} -> {id, set.name} end)

    sealed =
      ProductFacets.read(%{query: "", kind: nil, edition: nil, expansion: nil}).expansions
      |> Map.new(&{&1.id, &1.name})

    Map.merge(catalogue, sealed)
  end
end
