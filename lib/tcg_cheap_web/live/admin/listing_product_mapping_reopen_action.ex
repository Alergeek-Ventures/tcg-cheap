defmodule TcgCheapWeb.Admin.ListingProductMappingReopenAction do
  @moduledoc "Backpex item action for reopening terminal listing mappings."

  use BackpexWeb, :item_action
  use TcgCheapWeb, :verified_routes

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-arrow-uturn-left" class="h-5 w-5" />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Reopen"

  @impl Backpex.ItemAction
  def link(_assigns, mapping), do: ~p"/admin/catalogue/mappings/#{mapping.id}/correct"
end
