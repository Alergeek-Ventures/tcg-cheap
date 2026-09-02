defmodule TcgCheap.TestSupport do
  @moduledoc "Low-level card printing fixtures for tests."

  alias TcgCheap.Catalogue.{CardPrinting, CardSet}

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
