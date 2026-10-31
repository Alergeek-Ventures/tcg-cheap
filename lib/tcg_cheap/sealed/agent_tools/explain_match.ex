defmodule TcgCheap.Sealed.AgentTools.ExplainMatch do
  @moduledoc """
  Explains automatic matching for a stored offer or a raw title with the
  same index `TcgCheap.Sealed.Refresh` matches with (see `Matcher.explain/3`).
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.AgentTools.Json
  alias TcgCheap.Sealed.{Ean, Matcher}

  @impl true
  def run(input, _opts, _context) do
    with {:ok, subject, offer} <- subject(input.arguments) do
      products = Sealed.list_products!()
      index = Matcher.index(products, Sealed.known_eans())
      explanation = Matcher.explain(subject, index, input.arguments.candidates)
      {:ok, present(explanation, subject, offer, Map.new(products, &{&1.id, &1}))}
    end
  end

  defp subject(args) do
    case {args[:offer_id], args[:title]} do
      {id, nil} when is_binary(id) ->
        case Sealed.get_offer(id, load: [:product]) do
          {:ok, offer} -> {:ok, %{title: offer.title, ean: offer.ean}, offer}
          _ -> invalid(:offer_id, "no offer with this id")
        end

      {nil, title} when is_binary(title) ->
        {:ok, %{title: title, ean: Ean.normalize(args[:ean])}, nil}

      _ ->
        invalid(:title, "give either offer_id or title")
    end
  end

  defp invalid(field, message),
    do: {:error, InvalidArgument.exception(field: field, message: message)}

  defp present(explanation, subject, offer, products) do
    product = &Json.product(Map.get(products, &1))
    {result, matched} = result(explanation.result)
    winners = winners(explanation)

    %{
      offer: offer && Json.offer(offer),
      title: subject.title,
      ean: subject.ean,
      result: result,
      matched_product: matched && product.(matched),
      summary: summary(explanation, offer, products),
      normalized: explanation.normalized,
      exclusion: explanation.exclusion,
      ean_product: explanation.ean_product_id && product.(explanation.ean_product_id),
      tokens: explanation.tokens,
      qualifiers: explanation.qualifiers,
      max_unexplained: explanation.max_unexplained,
      candidates:
        Enum.map(explanation.candidates, fn candidate ->
          %{
            product: product.(candidate.id),
            qualifies: candidate.qualifies?,
            why: why(candidate, explanation, winners),
            product_tokens: candidate.tokens,
            missing_tokens: candidate.missing,
            missing_qualifiers: candidate.missing_qualifiers,
            unexplained_tokens: candidate.unexplained
          }
        end)
    }
  end

  defp result({:matched, id}), do: {:matched, id}
  defp result({:excluded, _reason}), do: {:excluded, nil}
  defp result(other), do: {other, nil}

  # The qualifying candidates of the greatest size, i.e. the title match.
  defp winners(%{candidates: candidates}) do
    qualifying = Enum.filter(candidates, & &1.qualifies?)
    top = qualifying |> Enum.map(&length(&1.tokens)) |> Enum.max(fn -> 0 end)
    qualifying |> Enum.filter(&(length(&1.tokens) == top)) |> MapSet.new(& &1.id)
  end

  defp summary(%{result: {:excluded, reason}}, _offer, _products),
    do:
      "Excluded outright because the title contains \"#{reason}\"; it never matches automatically."

  defp summary(%{result: {:matched, id}, ean_product_id: id}, offer, products),
    do:
      "Matched by known EAN to #{name(products, id)} (product barcodes or a manual offer assignment)." <>
        manual_note(offer)

  defp summary(%{result: {:matched, id}}, offer, products),
    do:
      "Matched by title to #{name(products, id)}, the most specific qualifying product." <>
        manual_note(offer)

  defp summary(%{result: :ambiguous}, offer, _products),
    do:
      "Ambiguous: several equally specific products qualify, so it stays unmatched." <>
        manual_note(offer)

  defp summary(%{result: :unmatched}, offer, _products),
    do: "Unmatched: no product name qualifies (see the candidates)." <> manual_note(offer)

  defp manual_note(%{manual?: true}),
    do: " This offer has a manual decision, which automatic matching never changes."

  defp manual_note(_offer), do: ""

  defp name(products, id), do: products |> Map.fetch!(id) |> Map.fetch!(:name)

  defp why(%{qualifies?: true, id: id}, %{result: result}, winners) do
    cond do
      match?({:excluded, _}, result) -> "would qualify, but the title is excluded"
      result == {:matched, id} -> "qualifies and wins"
      match?({:matched, _}, result) -> "qualifies, but the EAN or a more specific product wins"
      MapSet.member?(winners, id) -> "qualifies, but ties with an equally specific product"
      true -> "qualifies, but a more specific product wins"
    end
  end

  defp why(candidate, explanation, _winners) do
    [
      candidate.missing != [] &&
        "name tokens missing from the title: #{Enum.join(candidate.missing, ", ")}",
      candidate.missing_qualifiers != [] &&
        "title qualifiers missing from the name: #{Enum.join(candidate.missing_qualifiers, ", ")}",
      length(candidate.unexplained) > explanation.max_unexplained &&
        "#{length(candidate.unexplained)} title tokens not in the name (at most #{explanation.max_unexplained}): " <>
          Enum.join(candidate.unexplained, ", ")
    ]
    |> Enum.filter(& &1)
    |> Enum.join("; ")
  end
end
