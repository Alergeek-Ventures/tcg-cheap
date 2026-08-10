defmodule TcgCheapWeb.Admin.CardPrintingMappingCorrectionAction do
  @moduledoc "Backpex item action for correcting Cardmarket mappings."

  use BackpexWeb, :item_action
  use TcgCheapWeb, :verified_routes

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-pencil-square" class="h-5 w-5" />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Correct mapping"

  @impl Backpex.ItemAction
  def link(_assigns, card_printing),
    do: ~p"/admin/catalogue/cards/#{card_printing.id}/correct"
end
