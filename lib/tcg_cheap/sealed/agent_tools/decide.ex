defmodule TcgCheap.Sealed.AgentTools.Decide do
  @moduledoc """
  A manual matching decision (`decision:` `:assign`, `:exclude` or `:clear`),
  recomputed into prices in the same transaction, like the admin desk.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.Json
  alias TcgCheap.Sealed.Refresh

  @impl true
  def run(input, opts, _context) do
    args = input.arguments

    with {:ok, offer} <- fetch(&Sealed.get_offer/1, args.offer_id, :offer_id, "no offer"),
         {:ok, write} <- write(opts[:decision], offer, args),
         {:ok, offer} <- Refresh.with_recompute(write) do
      {:ok, offer.id |> Sealed.get_offer!(load: [:product]) |> Json.offer()}
    end
  end

  defp write(:assign, offer, args) do
    with {:ok, product} <-
           fetch(&Sealed.get_product/1, args.product_id, :product_id, "no product") do
      {:ok,
       fn -> Sealed.assign_offer_manually(offer, product.id, return_notifications?: true) end}
    end
  end

  defp write(:exclude, offer, _args),
    do: {:ok, fn -> Sealed.exclude_offer_manually(offer, return_notifications?: true) end}

  defp write(:clear, offer, _args),
    do: {:ok, fn -> Sealed.clear_manual_offer(offer, return_notifications?: true) end}

  defp fetch(get, id, field, message) do
    case get.(id) do
      {:ok, nil} ->
        {:error, InvalidArgument.exception(field: field, message: "#{message} with this id")}

      result ->
        result
    end
  end
end
