defmodule TcgCheap.TestSupport do
  @moduledoc "Low-level card printing fixtures for tests."

  alias TcgCheap.Catalogue.{CardPrinting, CardSet}
  alias TcgCheap.Pricing.Singles.SingleValuationSnapshot
  alias TcgCheap.Repo

  @historical_keys [
    :id,
    :card_printing_id,
    :value_eur,
    :source_metric,
    :fetched_at,
    :provider_updated_at,
    :cardmarket_product_id
  ]
  @historical_required_keys [
    :card_printing_id,
    :value_eur,
    :source_metric,
    :fetched_at,
    :cardmarket_product_id
  ]

  @doc "Creates a card printing through the importer-only action for low-level fixtures."
  def import_card_printing(attrs, opts \\ []) do
    attrs
    |> maybe_attach_fixture_set(opts)
    |> changeset()
    |> Ash.create(authorize?: false)
    |> maybe_scope(opts)
  end

  @doc "Creates a card printing through the importer-only action, raising on failure."
  def import_card_printing!(attrs, opts \\ []) do
    attrs
    |> maybe_attach_fixture_set(opts)
    |> changeset()
    |> Ash.create!(authorize?: false)
    |> maybe_scope!(opts)
  end

  defp changeset(attrs), do: Ash.Changeset.for_create(CardPrinting, :import, attrs)

  defp maybe_attach_fixture_set(attrs, opts) when is_list(opts) do
    cond do
      Map.has_key?(attrs, :card_set_id) ->
        attrs

      Keyword.has_key?(opts, :card_set?) ->
        maybe_attach_fixture_set(attrs, Keyword.get(opts, :card_set?))

      Keyword.get(opts, :scoped?, true) ->
        maybe_attach_fixture_set(attrs, true)

      true ->
        attrs
    end
  end

  defp maybe_attach_fixture_set(attrs, false), do: attrs

  defp maybe_attach_fixture_set(attrs, true) do
    id = "fixture-set-#{Map.get(attrs, :tcgdex_id, System.unique_integer([:positive]))}"

    set =
      Ash.create!(
        Ash.Changeset.for_create(CardSet, :import, %{
          tcgdex_id: id,
          name: "Fixture Set #{id}",
          series_id: "sv",
          series_name: "Fixture"
        }),
        authorize?: false
      )

    Map.put(attrs, :card_set_id, set.id)
  end

  def set_collection_scope!(card, attrs, _opts \\ []),
    do:
      card
      |> Ash.Changeset.for_update(:set_collection_scope, attrs)
      |> Ash.update!(authorize?: false)

  @doc "Inserts a retained historical TCGdex snapshot without invoking the bulk-only action."
  def insert_historical_single_valuation!(attrs) when is_map(attrs) do
    validate_historical_keys!(attrs)
    validate_historical_required_keys!(attrs)
    validate_historical_source_metric!(attrs.source_metric)
    validate_historical_value!(attrs.value_eur)
    validate_historical_product_id!(attrs.cardmarket_product_id)

    id = Map.get(attrs, :id, Ecto.UUID.generate())
    dumped_id = Ecto.UUID.dump!(id)
    dumped_card_printing_id = Ecto.UUID.dump!(attrs.card_printing_id)

    row =
      Map.merge(
        %{
          id: dumped_id,
          card_printing_id: dumped_card_printing_id,
          currency: "EUR",
          policy_version: "tcgdex_cardmarket_v1",
          source: "tcgdex_cardmarket",
          current?: false
        },
        Map.drop(attrs, [:id, :card_printing_id])
      )

    Repo.insert_all("single_valuation_snapshots", [row])
    Ash.get!(SingleValuationSnapshot, id, authorize?: false)
  end

  defp validate_historical_keys!(attrs) do
    case Map.keys(attrs) -- @historical_keys do
      [] ->
        :ok

      keys ->
        raise ArgumentError,
              "historical valuation fixture has unsupported attributes: #{inspect(keys)}"
    end
  end

  defp validate_historical_required_keys!(attrs) do
    Enum.each(@historical_required_keys, fn key ->
      if is_nil(Map.get(attrs, key)),
        do: raise(ArgumentError, "historical valuation fixture is missing required attributes")
    end)
  end

  defp validate_historical_source_metric!(source_metric) do
    unless is_binary(source_metric) and String.trim(source_metric) != "" do
      raise ArgumentError, "historical valuation fixture requires a non-empty source metric"
    end
  end

  defp validate_historical_value!(value) do
    unless Decimal.compare(Decimal.new(value), Decimal.new(0)) == :gt do
      raise ArgumentError, "historical valuation fixture requires a positive value"
    end
  end

  defp validate_historical_product_id!(product_id) do
    unless is_integer(product_id) and product_id > 0 do
      raise ArgumentError,
            "historical valuation fixture requires a positive Cardmarket product ID"
    end
  end

  defp maybe_scope({:ok, card}, opts) do
    if Keyword.get(opts, :scoped?, true), do: {:ok, scope!(card, opts)}, else: {:ok, card}
  end

  defp maybe_scope(result, _opts), do: result

  defp maybe_scope!(card, opts) do
    if Keyword.get(opts, :scoped?, true), do: scope!(card, opts), else: card
  end

  defp scope!(card, opts) do
    scoped_at =
      case Keyword.get(opts, :expires_on) do
        %Date{} = expires_on ->
          DateTime.new!(expires_on, ~T[00:00:00], "Etc/UTC")

        _ ->
          DateTime.utc_now()
          |> DateTime.add(System.unique_integer([:positive]), :microsecond)
          |> DateTime.truncate(:microsecond)
      end

    card
    |> Ash.Changeset.for_update(:set_collection_scope, %{
      collection_scopes: ["legacy_local"],
      collection_scope_source: "legacy",
      collection_scoped_at: scoped_at,
      collection_expires_on: Keyword.get(opts, :expires_on)
    })
    |> Ash.update!(authorize?: false)
  end
end
