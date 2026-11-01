defmodule TcgCheap.Sealed.AgentTools.SetContents do
  @moduledoc """
  Sets or clears what a product holds. Keys the contents do not know are
  rejected rather than dropped, so a misspelt field never passes as missing.
  A card given by its TCGdex id gets its set, number, picture and Cardmarket
  product from TCGdex; an id TCGdex does not know is rejected.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Catalogue.Tcgdex
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.Json

  @contents ~w(items sources checked_on)
  @item ~w(quantity type name tcgdex_id set number cardmarket_id image)

  @impl true
  def run(input, _opts, _context) do
    with :ok <- known_keys(input.params["contents"] || input.params[:contents]),
         {:ok, product} <- product(input.arguments.product_id),
         {:ok, contents} <- with_cards(input.arguments[:contents]),
         {:ok, product} <- Sealed.set_product_contents(product, contents) do
      {:ok, product |> Json.product() |> Map.put(:contents, Json.contents(product.contents))}
    end
  end

  defp product(id) do
    case Sealed.get_product(id) do
      {:ok, nil} -> invalid(:product_id, "no product with this id")
      other -> other
    end
  end

  defp with_cards(nil), do: {:ok, nil}

  defp with_cards(contents) do
    contents.items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, items} ->
      case with_card(item) do
        {:ok, item} -> {:cont, {:ok, [item | items]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, %{contents | items: Enum.reverse(items)}}
      error -> error
    end
  end

  defp with_card(%{tcgdex_id: nil} = item), do: {:ok, item}

  # A name the agent gives must be TCGdex's name of that card, so a wrong id
  # never shows another card.
  defp with_card(%{tcgdex_id: id} = item) do
    case Tcgdex.fetch_card(id) do
      {:ok, %{"name" => name, "localId" => number} = card}
      when is_binary(name) and is_binary(number) ->
        if item.name == nil or same_name?(item.name, name),
          do: {:ok, card_details(item, card)},
          else: invalid(:contents, "#{id} is #{name} in TCGdex, not #{item.name}")

      {:ok, _incomplete} ->
        invalid(:contents, "TCGdex gave no name or number for #{id}")

      {:error, reason} ->
        invalid(:contents, "TCGdex has no card #{id} (#{inspect(reason)})")
    end
  end

  defp card_details(item, card) do
    %{
      item
      | name: card["name"],
        set: get_in(card, ["set", "name"]),
        number: card["localId"],
        image: card["image"],
        cardmarket_id: get_in(card, ["pricing", "cardmarket", "idProduct"])
    }
  end

  defp same_name?(given, name), do: normalize(given) == normalize(name)

  defp normalize(name),
    do: name |> String.normalize(:nfd) |> String.replace(~r/\p{Mn}/u, "") |> String.downcase()

  defp known_keys(contents) do
    case unknown_keys(contents) do
      [] -> :ok
      paths -> invalid(:contents, "unknown keys: #{Enum.join(paths, ", ")}")
    end
  end

  defp unknown_keys(%{} = contents),
    do: extra(contents, @contents, "") ++ list_extra(contents, "items", @item)

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

  defp invalid(field, message),
    do: {:error, InvalidArgument.exception(field: field, message: message)}
end
