defmodule TcgCheap.Pricing.Singles.ValuationPolicy do
  @moduledoc "Fail-closed selector for the Singles valuation source."

  @tcgdex "tcgdex_cardmarket_v1"
  @bulk "cardmarket_bulk_v1"

  alias TcgCheap.Pricing.Singles.SingleValuationSnapshot
  alias TcgCheap.Pricing.Singles.ValuationPolicyCache

  def tcgdex_policy, do: @tcgdex
  def bulk_policy, do: @bulk
  def tcgdex_policy_version, do: @tcgdex
  def bulk_policy_version, do: @bulk
  def default_policy, do: @tcgdex
  def policies, do: [@tcgdex, @bulk]

  @doc "Returns the requested runtime policy, falling back on malformed input."
  def requested_policy do
    case Application.get_env(:tcg_cheap, :public_singles_valuation_policy, @tcgdex) do
      policy when policy in [@tcgdex, @bulk] -> policy
      _ -> @tcgdex
    end
  rescue
    _ -> @tcgdex
  end

  def selection, do: selection([])

  def selection(opts) when is_list(opts) do
    case {requested_policy(), opts} do
      {@tcgdex, _} ->
        @tcgdex

      {@bulk, []} ->
        ValuationPolicyCache.selection()

      {@bulk, [{:readiness, readiness}]} ->
        if ready?(readiness), do: @bulk, else: @tcgdex

      _ ->
        @tcgdex
    end
  rescue
    _ -> @tcgdex
  end

  def selection(_), do: @tcgdex
  def active_policy, do: selection()
  def bulk_active?, do: active_policy() == @bulk

  @doc "Returns a card's exact current valuation for the selected policy, or nil."
  def current_valuation(card, selected_policy) when is_map(card) do
    with true <- selected_policy in policies(),
         product_id when is_integer(product_id) and product_id > 0 <-
           Map.get(card, :cardmarket_product_id),
         %SingleValuationSnapshot{} = valuation <- relationship(card, selected_policy),
         true <- Map.get(valuation, :policy_version) == selected_policy,
         true <- Map.get(valuation, :current?) == true,
         valuation_product_id when is_integer(valuation_product_id) and valuation_product_id > 0 <-
           Map.get(valuation, :cardmarket_product_id),
         true <- valuation_product_id == product_id do
      valuation
    else
      _ -> nil
    end
  end

  def current_valuation(_, _), do: nil

  defp relationship(card, @tcgdex), do: Map.get(card, :tcgdex_cardmarket_v1_current_valuation)
  defp relationship(card, @bulk), do: Map.get(card, :cardmarket_bulk_v1_current_valuation)

  defp ready?(%{ready?: value}) when is_boolean(value), do: value
  defp ready?(_), do: false
end
