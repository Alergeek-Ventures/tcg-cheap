defmodule TcgCheap.Catalogue.Preparations.SearchPublicSealedProducts do
  @moduledoc "Builds the bounded local public sealed-product search query."
  use Ash.Resource.Preparation

  import Ash.Expr
  import Ash.Query

  alias Ash.Error.Query.InvalidArgument
  alias TcgCheap.Catalogue.Preparations.PublicSealedProduct
  alias TcgCheap.Catalogue.SearchText

  @impl true
  def prepare(query, _opts, context) do
    normalized = SearchText.normalize(Ash.Query.get_argument(query, :query))

    if length(String.graphemes(normalized)) < 2 do
      Ash.Query.add_error(
        query,
        InvalidArgument.exception(
          field: :query,
          message: "must contain at least 2 characters after normalization",
          value: normalized
        )
      )
    else
      pattern = "%" <> escape_like(normalized) <> "%"

      query
      |> PublicSealedProduct.prepare([], context)
      |> Ash.Query.filter(expr(^matching_name_or_alias(pattern)))
      |> sort(ranking(normalized))
      |> Ash.Query.limit(Ash.Query.get_argument(query, :limit))
    end
  end

  defp matching_name_or_alias(pattern) do
    expr(
      ilike(search_name, ^pattern) or
        exists(
          approved_name_aliases,
          ilike(normalized_value, ^pattern)
        )
    )
  end

  defp ranking(normalized) do
    prefix = escape_like(normalized) <> "%"

    [
      {ranking_bucket(normalized, prefix), :asc},
      {calc(fragment("similarity(?, ?)", search_name, ^normalized)), :desc},
      name: :asc,
      slug: :asc
    ]
  end

  defp ranking_bucket(normalized, prefix) do
    exact_alias = approved_alias_equals(normalized)
    prefix_alias = approved_alias_starts_with(prefix)

    calc(
      cond do
        search_name == ^normalized ->
          0

        ^exact_alias ->
          1

        ilike(search_name, ^prefix) ->
          2

        ^prefix_alias ->
          3

        ilike(search_name, ^("%" <> escape_like(normalized) <> "%")) ->
          4

        true ->
          5
      end,
      type: :integer
    )
  end

  defp approved_alias_equals(normalized) do
    expr(
      exists(
        approved_name_aliases,
        normalized_value == ^normalized
      )
    )
  end

  defp approved_alias_starts_with(prefix) do
    expr(
      exists(
        approved_name_aliases,
        ilike(normalized_value, ^prefix)
      )
    )
  end

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
