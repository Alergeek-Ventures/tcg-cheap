defmodule TcgCheap.Sealed.AgentTools.SetContents do
  @moduledoc """
  Sets or clears what a product holds. Keys the contents do not know are
  rejected rather than dropped, so a misspelt field never passes as missing.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.Json

  @contents ~w(items deck sources checked_on)
  @item ~w(quantity type name tcgdex_id image)
  @card ~w(quantity name category set number tcgdex_id image)

  @impl true
  def run(input, _opts, _context) do
    case unknown_keys(input.params["contents"] || input.params[:contents]) do
      [] ->
        set(input)

      paths ->
        {:error,
         InvalidArgument.exception(
           field: :contents,
           message: "unknown keys: #{Enum.join(paths, ", ")}"
         )}
    end
  end

  defp set(input) do
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

  defp unknown_keys(%{} = contents) do
    extra(contents, @contents, "") ++
      list_extra(contents, "items", @item) ++ list_extra(contents, "deck", @card)
  end

  defp unknown_keys(_contents), do: []

  defp list_extra(contents, key, known) do
    case value(contents, key) do
      list when is_list(list) ->
        list
        |> Enum.with_index()
        |> Enum.flat_map(fn
          {%{} = entry, index} -> extra(entry, known, "#{key}[#{index}].")
          _other -> []
        end)

      _other ->
        []
    end
  end

  defp extra(map, known, prefix),
    do: for(key <- Map.keys(map), to_string(key) not in known, do: prefix <> to_string(key))

  defp value(map, key), do: Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
end
