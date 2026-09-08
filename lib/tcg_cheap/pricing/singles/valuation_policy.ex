defmodule TcgCheap.Pricing.Singles.ValuationPolicy do
  @moduledoc "Deterministic public selector for the Cardmarket bulk Singles source."

  @tcgdex "tcgdex_cardmarket_v1"
  @bulk "cardmarket_bulk_v1"

  alias TcgCheap.Pricing.Singles.SingleValuationSnapshot

  def tcgdex_policy, do: @tcgdex
  def bulk_policy, do: @bulk
  def tcgdex_policy_version, do: @tcgdex
  def bulk_policy_version, do: @bulk
  def default_policy, do: @bulk
  def policies, do: [@bulk, @tcgdex]

  @doc "Returns the only selectable public policy. Historical TCGdex is never selected."
  def requested_policy, do: @bulk

  def selection, do: selection([])

  def selection(opts) when is_list(opts), do: @bulk

  def selection(_), do: @bulk
  def active_policy, do: selection()
  def bulk_active?, do: active_policy() == @bulk

  @doc "Returns a card's exact current valuation for the selected policy, or nil."
  def current_valuation(card, selected_policy) when is_map(card) do
    with true <- selected_policy == @bulk,
         product_id when is_integer(product_id) and product_id > 0 <-
           Map.get(card, :cardmarket_product_id),
         %SingleValuationSnapshot{} = valuation <- relationship(card),
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

  defp relationship(card), do: Map.get(card, :cardmarket_bulk_v1_current_valuation)
end
