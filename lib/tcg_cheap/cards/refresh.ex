defmodule TcgCheap.Cards.Refresh do
  @moduledoc """
  Singles are stored and matched after the sealed transaction commits, under
  their own advisory lock. Batches share one catalogue index; no singles are
  ever read by the sealed recompute. Manual writes acquire this lock before
  reading the offer, so an automatic update cannot overwrite a decision.
  Decisions share the five-minute transaction budget with fetches and rematches.

  Each entry point re-matches only the non-manual offers its trigger can have
  changed:

    * `run/3` re-matches the offers of the fetch it just stored (`last_seen_at`
      equal to the fetch time). The catalogue and the matcher do not change
      during a fetch, and offers the shop no longer lists are not shown, so
      older rows keep their identity until one of the entry points below runs.
    * `rematch_unmatched/0` re-matches every offer without a card, after new
      cards are synced.
    * `rematch_all/0` re-matches every offer, after matcher changes.
  """
  alias TcgCheap.Cards
  alias TcgCheap.Cards.{Matcher, Offer}
  alias TcgCheap.Repo
  alias TcgCheap.Sealed

  require Ash.Query

  def index do
    Cards.list_english_sets!(load: [:cards])
    |> Enum.filter(&(not is_nil(&1.cardmarket_expansion_id) and not is_nil(&1.cards_checked_at)))
    |> Matcher.index()
  end

  def run(%{singles_categories: nil, singles_markers: nil}, _offers, _now),
    do: {:ok, %{singles: 0}}

  def run(shop, offers, now) do
    Repo.transaction(
      fn ->
        lock()

        offers
        |> Enum.map(
          &(Map.take(&1, [
              :shop_product_id,
              :title,
              :category,
              :url,
              :image_url,
              :price,
              :shop_price,
              :currency,
              :market_prices,
              :in_stock
            ])
            |> Map.merge(Map.take(Matcher.parse(&1), [:language, :condition, :grading]))
            |> Map.merge(%{shop: shop.key, last_seen_at: now}))
        )
        |> Enum.chunk_every(500)
        |> Enum.each(fn inputs ->
          %Ash.BulkResult{status: :success} =
            Ash.bulk_create!(inputs, Offer, :upsert,
              domain: Cards,
              return_errors?: true,
              stop_on_error?: true
            )
        end)

        Sealed.record_shop_fetch!(%{shop: shop.key, kind: :single, fetched_at: now})
        rematch(Ash.Query.filter(Offer, shop == ^shop.key and last_seen_at == ^now), index())
        %{singles: length(offers)}
      end,
      timeout: :timer.minutes(5)
    )
  end

  @doc "After syncing new cards, retry only non-manual offers without an identity."
  def rematch_unmatched do
    Repo.transaction(
      fn ->
        lock()
        rematch(Ash.Query.filter(Offer, is_nil(card_id)), index())
      end,
      timeout: :timer.minutes(5)
    )
  end

  @doc "Re-audit all automatic identities after matcher changes; manual decisions survive."
  def rematch_all do
    Repo.transaction(
      fn ->
        lock()
        rematch(Offer, index())
      end,
      timeout: :timer.minutes(5)
    )
  end

  defp rematch(query, index) do
    query
    |> Ash.Query.filter(manual? == false)
    |> Ash.read!(domain: Cards)
    |> Enum.map(fn offer ->
      offer
      |> Map.take([:shop, :shop_product_id, :title, :url, :price, :in_stock, :last_seen_at])
      |> Map.merge(attributes(offer, index))
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn inputs ->
      %Ash.BulkResult{status: :success} =
        Ash.bulk_create!(inputs, Offer, :rematch_batch,
          domain: Cards,
          return_errors?: true,
          stop_on_error?: true
        )
    end)

    :ok
  end

  def attributes(offer, index) do
    parsed = Matcher.explain(offer, index)
    result = parsed.result

    {id, note} =
      case result do
        {:matched, id, _variant} -> {id, "matched"}
        {:excluded, {:language, lang}} -> {nil, "excluded:language:" <> lang}
        {:excluded, reason} -> {nil, "excluded:" <> to_string(reason)}
        {:unmatched, reason} -> {nil, to_string(reason)}
        {:ambiguous, _ids} -> {nil, "ambiguous"}
      end

    parsed
    |> Map.take([:variant, :language, :condition, :grading])
    |> Map.merge(%{card_id: id, match_note: note, match_set_ids: Enum.map(parsed.sets, & &1.id)})
  end

  @doc "A decision changes only this offer; no materialized card prices need recomputing."
  def decide(id, decision, args) do
    Repo.transaction(
      fn ->
        lock()
        offer = Cards.get_offer!(id)

        result =
          case decision do
            :assign ->
              Cards.assign_offer_manually(offer, Map.take(args, [:card_id, :variant]),
                return_notifications?: true
              )

            :exclude ->
              Cards.exclude_offer_manually(
                offer,
                %{
                  match_note: args[:note] || "manual_exclusion"
                },
                return_notifications?: true
              )

            :clear ->
              clear(offer)
          end

        case result do
          {:ok, offer, _notifications} -> offer
          {:error, error} -> Repo.rollback(error)
        end
      end,
      timeout: :timer.minutes(5)
    )
  end

  defp clear(offer) do
    with {:ok, cleared, _notifications} <-
           Cards.clear_manual_offer(offer, return_notifications?: true) do
      Cards.match_offer(cleared, attributes(cleared, index()), return_notifications?: true)
    end
  end

  defp lock, do: Repo.query!("SELECT pg_advisory_xact_lock(hashtext('tcg_cheap:card_recompute'))")
end
