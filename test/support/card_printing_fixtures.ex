defmodule TcgCheap.TestSupport do
  @moduledoc "Low-level card printing fixtures for tests."

  alias TcgCheap.Catalogue.CardPrinting

  @doc "Creates a card printing through the importer-only action for low-level fixtures."
  def import_card_printing(attrs, opts \\ []) do
    attrs
    |> changeset()
    |> Ash.create(authorize?: false)
    |> maybe_scope(opts)
  end

  @doc "Creates a card printing through the importer-only action, raising on failure."
  def import_card_printing!(attrs, opts \\ []) do
    attrs
    |> changeset()
    |> Ash.create!(authorize?: false)
    |> maybe_scope!(opts)
  end

  defp changeset(attrs), do: Ash.Changeset.for_create(CardPrinting, :import, attrs)

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
