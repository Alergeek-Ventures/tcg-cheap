defmodule TcgCheap.Sealed.Preparations.Browse do
  @moduledoc """
  Filters products by every word of the query (against the normalized search
  text) and an optional kind, language edition and Cardmarket expansion, and
  orders them: available in a Polish shop first, then the newest Cardmarket
  additions.
  """

  use Ash.Resource.Preparation

  require Ash.Query

  alias TcgCheap.Sealed.Matcher

  @max_words 8

  @impl true
  def prepare(query, _opts, _context) do
    words =
      (Ash.Query.get_argument(query, :query) || "")
      |> Matcher.normalize()
      |> String.split(" ", trim: true)
      |> Enum.take(@max_words)

    query
    |> filter_words(words)
    |> filter_by(:kind, Ash.Query.get_argument(query, :kind))
    |> filter_by(:region, Ash.Query.get_argument(query, :region))
    |> filter_by(:cardmarket_expansion_id, Ash.Query.get_argument(query, :expansion))
    |> Ash.Query.sort(
      available: :desc,
      cardmarket_added_on: :desc_nils_last,
      name: :asc,
      id: :asc
    )
  end

  defp filter_words(query, words) do
    Enum.reduce(words, query, fn word, query ->
      Ash.Query.filter(query, contains(search_text, ^(" " <> word)))
    end)
  end

  defp filter_by(query, _field, nil), do: query
  defp filter_by(query, field, value), do: Ash.Query.filter(query, ^ref(field) == ^value)
end
