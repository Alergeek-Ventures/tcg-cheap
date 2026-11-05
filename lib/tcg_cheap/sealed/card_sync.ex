defmodule TcgCheap.Sealed.CardSync do
  @moduledoc """
  Copies the cards of English TCGdex sets that have a Cardmarket expansion
  (`TcgCheap.Sealed.TcgdexSet`) into `TcgCheap.Sealed.TcgdexCard`, for the
  lists of cards on single booster pages. TCGdex's set documents list cards
  without their rarity, so one GraphQL query per set reads every card's
  number, name, rarity and variant flags. One REST set document supplies its
  official abbreviation, printed card count and the directory of its card
  images. Sets copied before these identity fields existed are copied again
  once, including old releases.

  Every set is copied once; sets released in the last half year again once
  a day, as TCGdex fills in new sets. A set TCGdex fails to return, or
  returns with errors or incomplete cards, keeps its cards and is tried
  again. An unofficial list recorded before TCGdex had the set stays until
  TCGdex lists as many cards, as it adds a new set's cards over days, or
  until two weeks after release, when TCGdex's list wins whatever its size.

  The GraphQL schema has no prices or Cardmarket ids, so the rest of the run
  asks TCGdex's card document for each card's Cardmarket product id, which
  links it to Cardmarket and to its price (`TcgCheap.Sealed.CardPrice`, from
  Cardmarket's price guide). An id never changes, so each card is asked once;
  a card TCGdex gives none is asked again a week later. Cards never asked go
  first, newest sets first. After three failed lookups in a row the rest
  waits for the next run.

  A run stops after five minutes and leaves the rest for the next one.
  """

  alias TcgCheap.Sealed

  require Logger

  @url "https://api.tcgdex.net/v2/graphql"
  @card_url "https://api.tcgdex.net/v2/en/cards/"
  @query "query($id: ID!) { cards(filters: {id: $id}) { id localId name rarity variants { normal reverse holo firstEdition } set { id } } }"
  @recent_days 183
  @retry_after_hours 20
  @cardmarket_retry_days 7
  @max_lookups 2_000
  @max_failures_in_row 3
  @max_cards 1_000
  @pause_ms 100
  @budget_ms :timer.minutes(5)
  @unofficial_days 14

  @spec run(keyword()) ::
          {:ok,
           %{
             synced: non_neg_integer(),
             failed: non_neg_integer(),
             looked_up: non_neg_integer(),
             lookups_failed: non_neg_integer()
           }}
  def run(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    request_options = Keyword.get(opts, :request_options, [])
    deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :budget_ms, @budget_ms)

    due =
      Sealed.list_sets_due_for_cards!(
        Date.add(DateTime.to_date(now), -@recent_days),
        DateTime.add(now, -@retry_after_hours, :hour)
      )

    counts = sync_until(due, deadline, {request_options, now}, %{synced: 0, failed: 0})

    cards =
      Sealed.list_cards_due_for_cardmarket!(DateTime.add(now, -@cardmarket_retry_days, :day),
        query: [limit: @max_lookups]
      )

    lookups =
      look_up_until(cards, deadline, request_options, %{looked_up: 0, lookups_failed: 0}, 0)

    if counts.synced > 0, do: Sealed.CardRefresh.rematch_unmatched()
    {:ok, Map.merge(counts, lookups)}
  end

  defp sync_until([], _deadline, _context, counts), do: counts

  defp sync_until([set | rest], deadline, context, counts) do
    if System.monotonic_time(:millisecond) < deadline do
      key = if sync(set, context) == :ok, do: :synced, else: :failed
      sync_until(rest, deadline, context, Map.update!(counts, key, &(&1 + 1)))
    else
      counts
    end
  end

  # Failures in a row mean TCGdex is struggling (it answers 503 when busy),
  # so the rest waits for the next run.
  defp look_up_until([], _deadline, _request_options, counts, _failures), do: counts

  defp look_up_until(_cards, _deadline, _request_options, counts, @max_failures_in_row),
    do: counts

  defp look_up_until([card | rest], deadline, request_options, counts, failures) do
    cond do
      System.monotonic_time(:millisecond) >= deadline ->
        counts

      look_up(card, request_options) == :ok ->
        look_up_until(
          rest,
          deadline,
          request_options,
          Map.update!(counts, :looked_up, &(&1 + 1)),
          0
        )

      true ->
        counts = Map.update!(counts, :lookups_failed, &(&1 + 1))
        look_up_until(rest, deadline, request_options, counts, failures + 1)
    end
  end

  # A failed request leaves the card to be asked again in the next run; a
  # card TCGdex has no document for counts as one without an id.
  defp look_up(card, request_options) do
    with {:ok, cardmarket_id} <- fetch_cardmarket_id(card.tcgdex_id, request_options),
         {:ok, _card} <- Sealed.record_card_cardmarket_id(card, cardmarket_id) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("Cardmarket id of #{card.tcgdex_id} not found: #{inspect(reason)}")
        :error
    end
  end

  defp fetch_cardmarket_id(card_id, request_options) do
    Process.sleep(@pause_ms)

    options =
      Keyword.merge(
        [
          url: @card_url <> URI.encode(card_id, &URI.char_unreserved?/1),
          redirect: false,
          retry: false,
          receive_timeout: 15_000
        ],
        request_options
      )

    case Req.get(options) do
      {:ok, %{status: 200, body: %{"id" => ^card_id} = body}} ->
        {:ok, cardmarket_id(body)}

      {:ok, %{status: 200, body: body}} ->
        {:error, {:unexpected_response, inspect(body, limit: 5)}}

      {:ok, %{status: 404}} ->
        {:ok, nil}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cardmarket_id(%{"pricing" => %{"cardmarket" => %{"idProduct" => id}}})
       when is_integer(id) and id > 0,
       do: id

  defp cardmarket_id(_none), do: nil

  defp sync(set, {request_options, now}) do
    with {:ok, metadata} <- fetch_set(set.tcgdex_id, request_options),
         {:ok, cards} <- fetch_cards(set.tcgdex_id, request_options),
         cards = Enum.map(cards, &subset_rarity(&1, set)),
         :ok <- replaces_unofficial(set, cards, now),
         {:ok, _set} <- Sealed.record_tcgdex_set_cards(set, cards, metadata) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("TCGdex cards of #{set.tcgdex_id} not copied: #{inspect(reason)}")
        :error
    end
  end

  # TCGdex gives the cards of a Classic Collection subset (the 30th
  # Celebration's) no rarity; the subset is their rarity.
  defp subset_rarity(%{rarity: nil} = card, %{name: "" <> name}) do
    if String.ends_with?(name, "Classic Collection"),
      do: %{card | rarity: "Classic Collection"},
      else: card
  end

  defp subset_rarity(card, _set), do: card

  defp replaces_unofficial(%{cards_source_url: nil}, _cards, _now), do: :ok

  defp replaces_unofficial(set, cards, now) do
    unofficial = set |> Ash.load!(:cards) |> Map.fetch!(:cards) |> length()
    settled? = Date.diff(DateTime.to_date(now), set.released_on) >= @unofficial_days

    if cards != [] and (settled? or length(cards) >= unofficial),
      do: :ok,
      else: {:error, {:fewer_than_unofficial, length(cards), unofficial}}
  end

  # TCGdex filters ids by substring, so cards of other sets are dropped. A
  # response with errors or an incomplete card of the set may lack cards, so
  # it is refused rather than replacing the set's cards.
  defp fetch_cards(set_id, request_options) do
    Process.sleep(@pause_ms)

    options =
      Keyword.merge(
        [
          url: @url,
          json: %{query: @query, variables: %{id: "#{set_id}-"}},
          redirect: false,
          retry: false,
          receive_timeout: 30_000
        ],
        request_options
      )

    case Req.post(options) do
      {:ok, %{status: 200, body: %{"errors" => [_ | _] = errors}}} ->
        {:error, {:graphql_errors, errors |> inspect() |> String.slice(0, 200)}}

      {:ok, %{status: 200, body: %{"data" => %{"cards" => cards}}}}
      when is_list(cards) and length(cards) <= @max_cards ->
        cards_of_set(cards, set_id)

      {:ok, %{status: 200, body: body}} ->
        {:error, {:unexpected_response, body |> inspect() |> String.slice(0, 200)}}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_set(id, request_options) do
    Process.sleep(@pause_ms)

    options =
      Keyword.merge(
        [
          url: "https://api.tcgdex.net/v2/en/sets/" <> URI.encode(id, &URI.char_unreserved?/1),
          redirect: false,
          retry: false,
          receive_timeout: 30_000
        ],
        request_options
      )

    case Req.get(options) do
      {:ok, %{status: 200, body: %{"id" => ^id, "cardCount" => %{"official" => count}} = body}}
      when is_integer(count) and count >= 0 ->
        {:ok,
         %{
           abbreviation: get_in(body, ["abbreviation", "official"]),
           official_card_count: count,
           card_images_url: card_images_url(body["cards"])
         }}

      {:ok, %{status: status}} ->
        {:error, {:set_metadata, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The directory of the first card image TCGdex gives. Sets have no image
  # path of their own and many lack a logo, but every card image of a set lies
  # in one directory, named after the card's number.
  defp card_images_url(cards) when is_list(cards) do
    Enum.find_value(cards, fn
      %{"image" => "https://" <> _ = image, "localId" => "" <> number} ->
        if String.ends_with?(image, "/" <> number),
          do: String.replace_suffix(image, "/" <> number, "")

      _card ->
        nil
    end)
  end

  defp card_images_url(_cards), do: nil

  defp variants(flags) when is_map(flags), do: for({key, true} <- flags, do: key)
  defp variants(_flags), do: []

  defp cards_of_set(cards, set_id) do
    cards
    |> Enum.reject(&match?(%{"set" => %{"id" => "" <> id}} when id != set_id, &1))
    |> Enum.reduce_while({:ok, []}, fn card, {:ok, rows} ->
      case card(card, set_id) do
        nil -> {:halt, {:error, {:incomplete_card, card |> inspect() |> String.slice(0, 200)}}}
        row -> {:cont, {:ok, [row | rows]}}
      end
    end)
  end

  defp card(
         %{
           "id" => "" <> id,
           "localId" => "" <> number,
           "name" => "" <> name,
           "set" => %{"id" => set_id}
         } =
           card,
         set_id
       )
       when id != "" and number != "" and name != "",
       do: %{
         tcgdex_id: id,
         number: number,
         name: name,
         rarity: rarity(card["rarity"]),
         variants: variants(card["variants"])
       }

  defp card(_incomplete, _set_id), do: nil

  defp rarity("None"), do: nil
  defp rarity("" <> rarity), do: rarity
  defp rarity(_none), do: nil
end
