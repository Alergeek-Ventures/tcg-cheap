defmodule TcgCheap.Sealed.AgentTools.SuggestedPrices do
  @moduledoc "Lists REBEL suggested price items or decides one manually (`action:` option)."

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.Json
  alias TcgCheap.Sealed.{Matcher, Refresh}

  @impl true
  def run(input, opts, _context), do: run(opts[:action], input.arguments)

  defp run(:list, args) do
    items =
      Sealed.list_suggested_prices!()
      |> Enum.filter(&wanted?(&1, args))
      |> Enum.sort_by(&{&1.title, &1.id})

    slice = items |> Enum.slice(args.offset, args.limit) |> Ash.load!(:product, domain: Sealed)

    {:ok,
     %{
       total: length(items),
       limit: args.limit,
       offset: args.offset,
       items: Enum.map(slice, &Json.suggested_price/1)
     }}
  end

  defp run(:decide, args) do
    with {:ok, item} <-
           fetch(&Sealed.get_suggested_price/1, args.suggested_price_id, :suggested_price_id),
         {:ok, product_id} <- product_id(args[:product_id]),
         {:ok, item} <-
           Refresh.with_recompute(fn ->
             Sealed.decide_suggested_price(item, product_id, return_notifications?: true)
           end) do
      {:ok, item |> Ash.load!(:product, domain: Sealed) |> Json.suggested_price()}
    end
  end

  defp wanted?(item, args) do
    (not args.unmatched or (is_nil(item.product_id) and not item.manual?)) and
      (is_nil(args[:title]) or
         String.contains?(Matcher.normalize(item.title), Matcher.normalize(args.title)))
  end

  defp product_id(nil), do: {:ok, nil}

  defp product_id(id) do
    with {:ok, product} <- fetch(&Sealed.get_product/1, id, :product_id), do: {:ok, product.id}
  end

  defp fetch(get, id, field) do
    case get.(id) do
      {:ok, nil} ->
        {:error, InvalidArgument.exception(field: field, message: "nothing with this id")}

      result ->
        result
    end
  end
end
