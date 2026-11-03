defmodule TcgCheap.Sealed.ExpansionSync do
  @moduledoc """
  Keeps `TcgCheap.Sealed.TcgdexSet` current. Lists TCGdex's English and
  Japanese sets and resolves every new set, and once a day every unresolved
  set released in the last half year, to the Cardmarket expansion of its
  first cards: TCGdex gives a card's Cardmarket product id, and the
  Cardmarket singles catalogue gives that product's expansion. Sets TCGdex
  has no Cardmarket ids for (older Japanese sets, promos) stay unresolved.

  English sets are also reconciled against exact, unambiguous sealed booster
  names on every run. This repairs historical wrong Cardmarket product ids
  in TCGdex and finds sealed expansions even when singles use another id.
  Without a unique name match the card-derived mapping is kept. The set's
  identity, copied cards and pull rates are preserved.

  A run stops resolving after five minutes and leaves the rest for the next
  day, newest sets first, so it never holds up the catalogue import: the
  first, about a thousand TCGdex documents, spreads over a few days; later
  runs read the set lists, sealed catalogue and new sets. A set whose cards TCGdex fails
  to return is not recorded, so it is tried again.
  """

  alias TcgCheap.Pricing.CardmarketBulk.Adapter
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Matcher, Regions}

  @base "https://api.tcgdex.net/v2"
  @languages ~w(en ja)
  @recent_days 183
  @retry_after_hours 20
  @sample_cards 3
  @pause_ms 100
  @budget_ms :timer.minutes(5)
  @logo_host "https://assets.tcgdex.net/"
  @ex_era_id ~r/\Aex\d+\z/

  @spec run(keyword()) ::
          {:ok, %{checked: non_neg_integer(), remapped: non_neg_integer()}} | {:error, term()}
  def run(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    request_options = Keyword.get(opts, :request_options, [])
    known = Map.new(Sealed.list_tcgdex_sets!(), &{{&1.language, &1.tcgdex_id}, &1})

    deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :budget_ms, @budget_ms)

    with {:ok, listed} <- list_sets(request_options),
         # TCGdex lists sets oldest first.
         due = listed |> Enum.filter(&due?(Map.get(known, &1), now)) |> Enum.reverse(),
         {:ok, expansions} <- expansions(due, request_options) do
      checked = resolve_until(due, deadline, expansions, request_options)

      with {:ok, remapped} <- reconcile_sealed(request_options) do
        {:ok, %{checked: checked, remapped: remapped}}
      end
    end
  end

  defp reconcile_sealed(request_options) do
    with {:ok, catalogue} <- Adapter.fetch_sealed_products(request_options: request_options) do
      catalogue.rows |> booster_expansions() |> remap_sets()
    end
  end

  defp remap_sets(expansions) do
    changes =
      for set <- Sealed.list_english_tcgdex_sets!(),
          [id] <- [Map.get(expansions, booster_name(set))],
          id != set.cardmarket_expansion_id,
          do: {set, id}

    Enum.reduce_while(changes, {:ok, 0}, fn {set, id}, {:ok, count} ->
      attrs =
        set
        |> Map.take([:language, :tcgdex_id, :name, :logo_url, :released_on])
        |> Map.put(:cardmarket_expansion_id, id)

      case Sealed.record_tcgdex_set(attrs) do
        {:ok, _set} -> {:cont, {:ok, count + 1}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # Require the complete name of a full English booster, not a substring of
  # a deck, tin or regional variant. Ambiguous names never replace a mapping.
  defp booster_expansions(products) do
    names = Enum.group_by(products, & &1.id_expansion, & &1.name)
    regions = Regions.by_expansion(names, %{})

    products
    |> Enum.filter(fn product ->
      product.category_id == 52 and regions[product.id_expansion] == :en and
        String.ends_with?(product.name, " Booster")
    end)
    |> Enum.group_by(
      &(&1.name |> String.replace_suffix(" Booster", "") |> Matcher.normalize()),
      & &1.id_expansion
    )
    |> Map.new(fn {name, ids} -> {name, Enum.uniq(ids)} end)
  end

  # Cardmarket includes the EX series label in these booster titles; TCGdex
  # leaves it out of the set name. Apply this only to EX-era TCGdex ids.
  defp booster_name(%{name: name, tcgdex_id: id}) when is_binary(name) do
    name = if Regex.match?(@ex_era_id, id), do: "EX " <> name, else: name
    Matcher.normalize(name)
  end

  defp booster_name(_set), do: nil

  # How many due sets were checked before the deadline.
  defp resolve_until([], _deadline, _expansions, _request_options), do: 0

  defp resolve_until([set | rest], deadline, expansions, request_options) do
    if System.monotonic_time(:millisecond) < deadline do
      resolve(set, expansions, request_options)
      1 + resolve_until(rest, deadline, expansions, request_options)
    else
      0
    end
  end

  defp list_sets(request_options) do
    Enum.reduce_while(@languages, {:ok, []}, fn language, {:ok, acc} ->
      case get("#{language}/sets", request_options) do
        {:ok, sets} when is_list(sets) ->
          {:cont, {:ok, acc ++ for(%{"id" => "" <> id} <- sets, do: {language, id})}}

        {:ok, _other} ->
          {:halt, {:error, {:unexpected_set_list, language}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp due?(nil, _now), do: true

  defp due?(%{cardmarket_expansion_id: nil, released_on: %Date{} = released} = set, now) do
    Date.diff(DateTime.to_date(now), released) <= @recent_days and
      DateTime.diff(now, set.checked_at, :hour) >= @retry_after_hours
  end

  defp due?(_set, _now), do: false

  # Cardmarket product id => expansion id, only needed when a set is due.
  defp expansions([], _request_options), do: {:ok, %{}}

  defp expansions(_due, request_options) do
    with {:ok, catalogue} <- Adapter.fetch_products(request_options: request_options) do
      {:ok, Map.new(catalogue.rows, &{&1.id_product, &1.id_expansion})}
    end
  end

  # A set TCGdex fails to return, or that does not save, is left for the next run.
  defp resolve({language, id}, expansions, request_options) do
    with {:ok, %{"cards" => cards} = set} when is_list(cards) <-
           get("#{language}/sets/#{segment(id)}", request_options),
         {:ok, expansion} <- expansion(cards, language, expansions, request_options) do
      Sealed.record_tcgdex_set(%{
        language: language,
        tcgdex_id: id,
        cardmarket_expansion_id: expansion,
        name: string(set["name"]),
        logo_url: logo(set["logo"]),
        released_on: date(set["releaseDate"])
      })
    end
  end

  # The expansion of the first sampled card Cardmarket knows; :error when
  # TCGdex fails to return a card, so the set is tried again later.
  defp expansion(cards, language, expansions, request_options) do
    cards
    |> Enum.take(@sample_cards)
    |> Enum.reduce_while({:ok, nil}, fn card, acc ->
      case card_expansion(card, language, expansions, request_options) do
        {:ok, nil} -> {:cont, acc}
        {:ok, expansion} -> {:halt, {:ok, expansion}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp card_expansion(%{"id" => "" <> card}, language, expansions, request_options) do
    case get("#{language}/cards/#{segment(card)}", request_options) do
      {:ok, %{"pricing" => %{"cardmarket" => %{"idProduct" => product}}}} ->
        {:ok, Map.get(expansions, product)}

      {:ok, _card} ->
        {:ok, nil}

      {:error, _reason} ->
        :error
    end
  end

  defp card_expansion(_card, _language, _expansions, _request_options), do: {:ok, nil}

  defp get(path, request_options) do
    Process.sleep(@pause_ms)

    options =
      Keyword.merge(
        # No retries: they could outlast the budget, and a set that fails is
        # simply tried again on the next run.
        [url: "#{@base}/#{path}", redirect: false, retry: false, receive_timeout: 15_000],
        request_options
      )

    case Req.get(options) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status, path}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp segment(id), do: URI.encode(id, &URI.char_unreserved?/1)

  defp string(value) when is_binary(value), do: value
  defp string(_value), do: nil

  defp logo(@logo_host <> _ = url), do: url
  defp logo(_value), do: nil

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp date(_value), do: nil
end
