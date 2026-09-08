defmodule TcgCheap.Pricing.Singles.ValuationPolicy do
  @moduledoc "Fixed public selector for Cardmarket bulk Singles valuations."

  @bulk "cardmarket_bulk_v1"

  alias TcgCheap.Pricing.Singles.SingleValuationSnapshot

  def policy_version, do: @bulk

  def current_valuation(card) when is_map(card) do
    with product_id when is_integer(product_id) and product_id > 0 <-
           Map.get(card, :cardmarket_product_id),
         %SingleValuationSnapshot{} = valuation <- relationship(card),
         true <- exact_current_bulk_valuation?(valuation, product_id) do
      valuation
    else
      _ -> nil
    end
  end

  def current_valuation(_), do: nil

  defp relationship(card), do: Map.get(card, :cardmarket_bulk_v1_current_valuation)

  defp exact_current_bulk_valuation?(valuation, product_id) do
    Map.get(valuation, :policy_version) == @bulk and
      Map.get(valuation, :current?) == true and
      is_integer(Map.get(valuation, :cardmarket_product_id)) and
      Map.get(valuation, :cardmarket_product_id) > 0 and
      Map.get(valuation, :cardmarket_product_id) == product_id
  end
end
