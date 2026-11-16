defmodule TcgCheap.Cards do
  @moduledoc """
  Single cards: the card sets TCGdex lists (and the unofficial ones recorded by
  hand), their cards with Cardmarket ids and prices, and the shops' singles
  matched to those cards.

  A single is *current* when it was seen in its shop's latest card fetch and
  that fetch happened within the last 3 days. A shop's card fetch counts
  independently of its sealed fetch, so a shop that sells only singles has
  current singles too.
  """

  use Ash.Domain, otp_app: :tcg_cheap, extensions: [AshAi]

  alias TcgCheap.Cards.AgentTools

  @current_for_seconds 3 * 86_400

  tools do
    tool(:list_unmatched_card_offers, AgentTools, :list_unmatched_card_offers,
      annotations: [read_only_hint: true]
    )

    tool(:list_matched_card_offers, AgentTools, :list_matched_card_offers,
      annotations: [read_only_hint: true]
    )

    tool(:list_card_decisions, AgentTools, :list_card_decisions,
      annotations: [read_only_hint: true]
    )

    tool(:explain_card_match, AgentTools, :explain_card_match,
      annotations: [read_only_hint: true]
    )

    tool(:search_cards, AgentTools, :search_cards, annotations: [read_only_hint: true])

    tool(:assign_card_offer, AgentTools, :assign_card_offer,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:exclude_card_offer, AgentTools, :exclude_card_offer,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:clear_card_decision, AgentTools, :clear_card_decision,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:set_pull_rates, AgentTools, :set_pull_rates,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )

    tool(:record_unofficial_set_cards, AgentTools, :record_unofficial_set_cards,
      annotations: [read_only_hint: false, destructive_hint: false, idempotent_hint: true]
    )
  end

  resources do
    resource TcgCheap.Cards.Set do
      define :list_sets, action: :read
      define :record_set, action: :record
      define :list_english_sets, action: :english

      define :list_english_sets_of_expansion,
        action: :english_of_expansion,
        args: [:expansion_id]

      define :list_sets_due_for_cards,
        action: :cards_due,
        args: [:released_since, :checked_before]

      define :set_pull_rates, action: :set_pull_rates, args: [:pull_rates]
      define :record_set_cards, action: :record_cards, args: [:cards]
      define :record_unofficial_set_cards, action: :record_unofficial_cards
    end

    resource TcgCheap.Cards.Card do
      define :list_cards, action: :read
      define :list_cards_due_for_cardmarket, action: :cardmarket_due, args: [:checked_before]
      define :record_card_cardmarket_id, action: :record_cardmarket_id, args: [:cardmarket_id]
    end

    resource TcgCheap.Cards.Offer do
      define :list_offers, action: :read
      define :get_offer, action: :read, get_by: [:id]
      define :match_offer, action: :match
      define :assign_offer_manually, action: :assign_manually
      define :exclude_offer_manually, action: :exclude_manually
      define :clear_manual_offer, action: :clear_manual
      define :latest_fetches, action: :latest_fetches, args: [:since]
    end

    resource TcgCheap.Cards.Price
    resource TcgCheap.Cards.DailyPrice
    resource AgentTools
  end

  @doc "Current singles, using each shop's latest card fetch within three days."
  def current_offers(now \\ DateTime.utc_now()) do
    since = DateTime.add(now, -@current_for_seconds, :second)
    latest = latest_fetches!(since)

    require Ash.Query
    require Ash.Expr
    query = TcgCheap.Cards.Offer |> Ash.Query.filter(is_nil(language) or language == "en")

    filter =
      Enum.reduce(latest, false, fn {shop, time}, acc ->
        Ash.Expr.expr(^acc or (shop == ^shop and last_seen_at == ^time))
      end)

    query |> Ash.Query.filter(^filter) |> Ash.read!(domain: __MODULE__)
  end
end
