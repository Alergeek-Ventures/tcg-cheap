defmodule TcgCheap.Catalogue.Preparations.Search do
  @moduledoc """
  Builds the local deterministic exact-printing search query.

  Ranking precedence is exact TCGdex ID, exact card name, exact collector
  number, exact set name, then prefixes in card-name, collector-number,
  set-name, and TCGdex-ID order. Remaining matches are ordered by descending
  trigram similarity for card name, set name, collector number, and TCGdex ID;
  Standard legality then breaks otherwise equivalent relevance. Finally,
  ascending name, set name, collector number, and TCGdex ID provide stable
  tie-breaks. Mapping status is intentionally absent from both filtering and
  ranking because it is not publication state.
  """

  use Ash.Resource.Preparation

  import Ash.Expr
  import Ash.Query

  alias Ash.Error.Query.InvalidArgument
  alias TcgCheap.Catalogue.SearchText

  @impl true
  def prepare(query, _opts, _context) do
    normalized = SearchText.normalize(Ash.Query.get_argument(query, :query))

    if invalid_query?(normalized) do
      invalid_query(query, normalized)
    else
      candidate = candidate_filter(normalized)

      query
      |> Ash.Query.filter(expr(^candidate))
      |> sort(ranking(normalized))
      |> Ash.Query.limit(Ash.Query.get_argument(query, :limit))
      |> load([:card_set, :tcgdex_cardmarket_v1_current_valuation])
    end
  end

  defp invalid_query?(query), do: length(String.graphemes(query)) < 2

  defp invalid_query(query, normalized) do
    Ash.Query.add_error(
      query,
      InvalidArgument.exception(
        field: :query,
        message: "must contain at least 2 characters after normalization",
        value: normalized
      )
    )
  end

  defp candidate_filter(normalized) do
    pattern = "%" <> escape_like(normalized) <> "%"

    expr(
      ilike(search_name, ^pattern) or
        ilike(search_set_name, ^pattern) or
        ilike(search_collector_number, ^pattern) or
        ilike(search_tcgdex_id, ^pattern) or
        fragment("? % ?", search_name, ^normalized) or
        fragment("? % ?", search_set_name, ^normalized) or
        fragment("? % ?", search_collector_number, ^normalized) or
        fragment("? % ?", search_tcgdex_id, ^normalized)
    )
  end

  defp ranking(normalized) do
    prefix = escape_like(normalized) <> "%"

    [
      {calc(
         fragment(
           "CASE WHEN ? = ? THEN 0 WHEN ? = ? THEN 1 WHEN ? = ? THEN 2 WHEN ? = ? THEN 3 WHEN ? LIKE ? THEN 4 WHEN ? LIKE ? THEN 5 WHEN ? LIKE ? THEN 6 WHEN ? LIKE ? THEN 7 ELSE 8 END",
           search_tcgdex_id,
           ^normalized,
           search_name,
           ^normalized,
           search_collector_number,
           ^normalized,
           search_set_name,
           ^normalized,
           search_name,
           ^prefix,
           search_collector_number,
           ^prefix,
           search_set_name,
           ^prefix,
           search_tcgdex_id,
           ^prefix
         )
       ), :asc},
      {calc(fragment("similarity(?, ?)", search_name, ^normalized)), :desc},
      {calc(fragment("similarity(?, ?)", search_set_name, ^normalized)), :desc},
      {calc(fragment("similarity(?, ?)", search_collector_number, ^normalized)), :desc},
      {calc(fragment("similarity(?, ?)", search_tcgdex_id, ^normalized)), :desc},
      {calc(fragment("CASE WHEN ? = TRUE THEN 0 ELSE 1 END", standard_legal)), :asc},
      name: :asc,
      set_name: :asc,
      collector_number: :asc,
      tcgdex_id: :asc
    ]
  end

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
