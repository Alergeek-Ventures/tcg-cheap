defmodule TcgCheap.Sealed.AgentTools.SetEans do
  @moduledoc "Sets verified product barcodes and refreshes matching and prices."

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.Json
  alias TcgCheap.Sealed.Refresh

  @impl true
  def run(input, _opts, _context) do
    with {:ok, product} when not is_nil(product) <- Sealed.get_product(input.arguments.product_id),
         {:ok, product} <-
           Refresh.with_recompute(fn ->
             Sealed.set_product_eans(product, input.arguments.eans, return_notifications?: true)
           end) do
      {:ok, Json.product(product)}
    else
      {:ok, nil} ->
        {:error,
         InvalidArgument.exception(field: :product_id, message: "no product with this id")}

      {:error, error} ->
        {:error, error}
    end
  end
end
