defmodule TcgCheap.Catalogue.CardmarketMapping do
  @moduledoc "Pure extraction and classification of Cardmarket identity evidence."

  alias TcgCheap.Catalogue.MaterialVariant
  @record_keys ~w(type subtype stamp stamps size firstEdition wPromo jumbo preRelease foil)

  @spec classify(map(), map(), map() | list()) :: map()
  def classify(card) when is_map(card) do
    classify(card, Map.get(card, "variants", %{}), Map.get(card, "variants_detailed", %{}))
  end

  def classify(card, variants, detailed) when is_map(card) do
    ids = (identity_ids(card) ++ identity_ids_in(detailed)) |> Enum.uniq()
    details = records(detailed)
    mapped_details = Enum.filter(details, &identity_bearing?/1)

    material =
      MaterialVariant.cardmarket_descriptors(
        variants,
        if(mapped_details == [], do: details, else: mapped_details)
      )

    cond do
      MaterialVariant.conflict?(material) ->
        %{status: "review", reason: MaterialVariant.reason(material), cardmarket_product_id: nil}

      length(ids) > 1 ->
        %{status: "review", reason: "multiple Cardmarket product IDs", cardmarket_product_id: nil}

      ids == [] ->
        %{status: "unmatched", reason: nil, cardmarket_product_id: nil}

      true ->
        %{status: "matched", reason: nil, cardmarket_product_id: hd(ids)}
    end
  end

  def classify(_card, variants, detailed), do: classify(%{}, variants, detailed)

  @doc "Returns only positive IDs from Cardmarket identity fields, never prices."
  def identity_ids(card) when is_map(card) do
    (pricing_identities(Map.get(card, "pricing")) ++
       third_party_identities(Map.get(card, "thirdParty")) ++
       identity_ids_in(Map.get(card, "variants_detailed")))
    |> Enum.uniq()
  end

  def identity_ids(_), do: []

  def cardmarket_product_ids(card), do: identity_ids(card)

  @doc false
  def identity_bearing?(record) when is_map(record) do
    identity_ids_in(record) != []
  end

  def identity_bearing?(_), do: false

  defp identity_ids_in(value) when is_list(value), do: Enum.flat_map(value, &identity_ids_in/1)

  defp identity_ids_in(%{} = value) do
    if record?(value) do
      direct_identity_ids(value)
    else
      Enum.flat_map(Map.values(value), &identity_ids_in/1)
    end
  end

  defp identity_ids_in(_), do: []

  defp records(value) when is_list(value), do: Enum.flat_map(value, &records/1)

  defp records(%{} = value) do
    own = if Enum.any?(Map.keys(value), &(&1 in @record_keys)), do: [value], else: []
    own ++ Enum.flat_map(Map.values(value), &records/1)
  end

  defp records(_), do: []

  defp pricing_identities(%{"cardmarket" => %{"idProduct" => id}}), do: positive(id)
  defp pricing_identities(_), do: []

  defp third_party_identities(%{"cardmarket" => id}), do: cardmarket_identity(id)
  defp third_party_identities(_), do: []

  defp cardmarket_identity(id) when is_integer(id), do: positive(id)
  defp cardmarket_identity(%{"idProduct" => id}), do: positive(id)
  defp cardmarket_identity(_), do: []

  defp direct_identity_ids(value) do
    pricing_identities(Map.get(value, "pricing")) ++
      third_party_identities(Map.get(value, "thirdParty"))
  end

  defp record?(value),
    do: Enum.any?(Map.keys(value), &(&1 in (["pricing", "thirdParty"] ++ @record_keys)))

  defp positive(id) when is_integer(id) and id > 0, do: [id]
  defp positive(_), do: []
end
