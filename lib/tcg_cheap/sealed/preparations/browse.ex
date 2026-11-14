defmodule TcgCheap.Sealed.Preparations.Browse do
  @moduledoc """
  Filters products by every word of the query (against the normalized search
  text, through its ParadeDB index) and an optional kind (or shelf of kinds),
  language edition and Cardmarket expansion, and orders them: available in
  the market first (a Polish shop, unless the `stock` argument gives another
  market's products), then those available as a pre-order, then the best
  matches of a search, then the newest Cardmarket additions.
  """

  use Ash.Resource.Preparation

  import Ash.Expr

  require Ash.Query
  require Ash.Sort

  alias TcgCheap.Repo
  alias TcgCheap.Sealed.{Kinds, Matcher}

  @max_words 8
  # Shorter words are prefixes still being typed; one edit would match
  # almost anything ("clay" would find "play" and "class").
  @min_typo_length 4

  @impl true
  def prepare(query, _opts, _context) do
    words =
      (Ash.Query.get_argument(query, :query) || "")
      |> Matcher.normalize()
      |> String.split(" ", trim: true)
      |> Enum.take(@max_words)
      |> pack_counts()

    query
    |> filter_words(words, typos(words))
    |> filter_kind(Ash.Query.get_argument(query, :kind))
    |> filter_by(:region, Ash.Query.get_argument(query, :region))
    |> filter_by(:cardmarket_expansion_id, Ash.Query.get_argument(query, :expansion))
    |> Ash.Query.sort(
      stock_order(Ash.Query.get_argument(query, :stock)) ++
        relevance(words) ++
        [{:cardmarket_added_on, :desc_nils_last}, {:name, :asc}, {:id, :asc}]
    )
  end

  # Every word starts a word of the search text (words are `[a-z0-9]+` after
  # `Matcher.normalize/1`, so they are safe in a regex); a whole word scores
  # above a prefix. A typo is found within one edit ("meoth" finds Meowth).
  defp filter_words(query, words, typos) do
    Enum.reduce(words, query, fn word, query ->
      Ash.Query.filter(query, ^word_filter(word, word in typos))
    end)
  end

  defp word_filter(word, true),
    do: expr(fragment("? &&& ?::text::pdb.fuzzy(1, t)", search_text, ^word))

  defp word_filter(word, false) do
    if String.contains?(word, " ") do
      expr(fragment("? ### ?::text", search_text, ^word))
    else
      expr(
        fragment(
          "(? @@@ pdb.regex(?::text) OR ? &&& ?::text::pdb.boost(2))",
          search_text,
          ^prefix(word),
          search_text,
          ^word
        )
      )
    end
  end

  defp prefix(word), do: word <> ".*"

  # A word found inside no word of any product is a typo. A word some product
  # holds is meant as typed, even when the other filters or the prefix match
  # leave none of those products: "clay" in English is not "play", and "zard"
  # (in Charizard) is not "card".
  defp typos(words) do
    case Enum.filter(words, &typo_candidate?/1) do
      [] ->
        []

      candidates ->
        held =
          candidates
          |> Enum.with_index(1)
          |> Enum.map_join(", ", fn {_word, index} ->
            "EXISTS (SELECT 1 FROM sealed_products WHERE search_text @@@ pdb.regex($#{index}::text))"
          end)

        %{rows: [found]} = Repo.query!("SELECT " <> held, Enum.map(candidates, &".*#{&1}.*"))
        for {word, false} <- Enum.zip(candidates, found), do: word
    end
  end

  defp typo_candidate?(word),
    do: String.length(word) >= @min_typo_length and Regex.match?(~r/\A[a-z]+\z/, word)

  # Poland's availability is stored on each product; another market's comes
  # as the ids of its products in stock and on pre-order.
  defp stock_order(nil) do
    [
      {:available, :desc},
      {Ash.Sort.expr_sort(is_nil(lowest_preorder_price), :boolean), :asc}
    ]
  end

  defp stock_order(%{in_stock: in_stock, preorder: preorder}) do
    [
      {Ash.Sort.expr_sort(id in ^in_stock, :boolean), :desc},
      {Ash.Sort.expr_sort(id in ^preorder, :boolean), :desc}
    ]
  end

  defp relevance([]), do: []
  defp relevance(_words), do: [{Ash.Sort.expr_sort(fragment("pdb.score(?)", id), :float), :desc}]

  # "3 pack" is one phrase: a bare "3" would also find "30th" and "36", and
  # "3p" or "3pak" is how shops and buyers shorten it.
  defp pack_counts([count, "pack" | rest]) do
    if Regex.match?(~r/\A\d+\z/, count),
      do: [count <> " pack" | pack_counts(rest)],
      else: [count | pack_counts(["pack" | rest])]
  end

  defp pack_counts([word | rest]) do
    case Regex.run(~r/\A(\d+)(?:p|pk|pak|packs?)\z/, word) do
      [_, count] -> [count <> " pack" | pack_counts(rest)]
      nil -> [word | pack_counts(rest)]
    end
  end

  defp pack_counts([]), do: []

  defp filter_kind(query, nil), do: query
  defp filter_kind(query, kind), do: Ash.Query.filter(query, kind in ^Kinds.members(kind))

  defp filter_by(query, _field, nil), do: query
  defp filter_by(query, field, value), do: Ash.Query.filter(query, ^ref(field) == ^value)
end
