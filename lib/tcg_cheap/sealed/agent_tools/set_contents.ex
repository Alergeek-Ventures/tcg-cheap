defmodule TcgCheap.Sealed.AgentTools.SetContents do
  @moduledoc """
  Sets or clears what a product holds. Keys the contents do not know are
  rejected rather than dropped, so a misspelt field never passes as missing.
  A card given by its TCGdex id gets its set, number, picture and Cardmarket
  product from TCGdex, and so does each card of a fixed deck or random deck variant, with its
  category; an id TCGdex does not know is rejected. An item's photo
  must be on an image host we mirror from (`TcgCheap.Catalogue.ExternalImage`).
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Catalogue.{ExternalImage, Tcgdex}
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.{Json, KnownKeys}
  alias TcgCheap.Sealed.ProductContents.DeckCard

  @contents ~w(items sources checked_on)
  @item ~w(quantity type name tcgdex_id set number cardmarket_id image photo cards variants)
  @deck_card ~w(quantity name tcgdex_id category set number cardmarket_id image)

  @impl true
  def run(input, _opts, _context) do
    with :ok <-
           KnownKeys.check(
             input.params["contents"] || input.params[:contents],
             :contents,
             @contents,
             %{
               "items" =>
                 {@item,
                  %{
                    "cards" => @deck_card,
                    "variants" => {~w(name cards), %{"cards" => @deck_card}}
                  }}
             }
           ),
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
    with {:ok, items} <- map_ok(contents.items, &with_item/1),
         do: {:ok, %{contents | items: items}}
  end

  defp with_item(item) do
    with :ok <- allowed_photo(item),
         {:ok, item} <- with_card(item),
         {:ok, item} <- with_deck_cards(item),
         do: with_variants(item)
  end

  defp with_deck_cards(%{cards: cards} = item) when is_list(cards) do
    with {:ok, cards} <- map_ok(cards, &with_card/1), do: {:ok, %{item | cards: cards}}
  end

  defp with_deck_cards(item), do: {:ok, item}

  defp with_variants(%{variants: variants} = item) when is_list(variants) do
    with {:ok, variants} <- map_ok(variants, &with_deck_cards/1),
         do: {:ok, %{item | variants: variants}}
  end

  defp with_variants(item), do: {:ok, item}

  # Maps every entry with `fun`, stopping at the first error.
  defp map_ok(entries, fun) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, done} ->
      case fun.(entry) do
        {:ok, entry} -> {:cont, {:ok, [entry | done]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      error -> error
    end
  end

  defp allowed_photo(%{photo: nil}), do: :ok

  defp allowed_photo(%{photo: photo}) do
    if ExternalImage.valid?(photo),
      do: :ok,
      else: invalid(:contents, "photo #{photo} is not on an allowed image host")
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

  defp card_details(%DeckCard{} = deck_card, card) do
    %{base_card_details(deck_card, card) | category: card["category"]}
  end

  defp card_details(item, card), do: base_card_details(item, card)

  defp base_card_details(item, card) do
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

  defp invalid(field, message),
    do: {:error, InvalidArgument.exception(field: field, message: message)}
end
