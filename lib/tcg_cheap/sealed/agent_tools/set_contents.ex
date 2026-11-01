defmodule TcgCheap.Sealed.AgentTools.SetContents do
  @moduledoc "Sets or clears what a product holds."

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.Json

  @impl true
  def run(input, _opts, _context) do
    case Sealed.get_product(input.arguments.product_id) do
      {:ok, nil} ->
        {:error,
         InvalidArgument.exception(field: :product_id, message: "no product with this id")}

      {:ok, product} ->
        with {:ok, product} <- Sealed.set_product_contents(product, input.arguments[:contents]) do
          {:ok, product |> Json.product() |> Map.put(:contents, Json.contents(product.contents))}
        end

      {:error, error} ->
        {:error, error}
    end
  end
end
