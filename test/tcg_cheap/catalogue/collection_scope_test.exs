defmodule TcgCheap.Catalogue.CollectionScopeTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Catalogue.CardPrinting
  alias TcgCheap.Core

  defp token(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp attrs(token),
    do: %{
      tcgdex_id: token,
      name: "Scope #{token}",
      set_name: "Set #{token}",
      collector_number: "1"
    }

  test "internal lookup works while public ID, bulk, search, and recent hide unscoped rows" do
    id = token("unscoped")
    card = TcgCheap.TestSupport.import_card_printing!(attrs(id), scoped?: false)

    assert {:ok, internal_card} = Core.get_card_printing_by_tcgdex_id(id)
    assert internal_card.id == card.id
    assert {:ok, nil} = Core.get_public_card_printing_by_tcgdex_id(id)
    assert {:ok, []} = Core.list_public_card_printings_by_tcgdex_ids([id])
    assert {:ok, []} = Core.search_public_card_printings(id)
    assert {:ok, []} = Core.list_public_recently_tracked_card_printings()
  end

  test "active scope is public and expired scope is hidden" do
    active_id = token("active")
    expired_id = token("expired")

    active = TcgCheap.TestSupport.import_card_printing!(attrs(active_id))

    TcgCheap.TestSupport.import_card_printing!(attrs(expired_id),
      expires_on: Date.add(Date.utc_today(), -1)
    )

    assert {:ok, public_active} = Core.get_public_card_printing_by_tcgdex_id(active_id)
    assert public_active.id == active.id
    assert {:ok, nil} = Core.get_public_card_printing_by_tcgdex_id(expired_id)

    assert {:ok, [bulk_active]} =
             Core.list_public_card_printings_by_tcgdex_ids([active_id, expired_id])

    assert bulk_active.id == active.id

    assert {:ok, [search_active]} = Core.search_public_card_printings(active_id)
    assert search_active.id == active.id
  end

  test "scope metadata is validated" do
    card = TcgCheap.TestSupport.import_card_printing!(attrs(token("invalid")), scoped?: false)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:error, _} =
             Core.set_card_printing_collection_scope(
               card,
               %{
                 collection_scopes: ["not-a-scope"],
                 collection_scope_source: "system",
                 collection_scoped_at: now,
                 collection_expires_on: nil
               },
               authorize?: false
             )

    assert {:error, _} =
             Core.set_card_printing_collection_scope(
               card,
               %{
                 collection_scopes: ["legacy_local"],
                 collection_scope_source: "not-a-source",
                 collection_scoped_at: now,
                 collection_expires_on: nil
               },
               authorize?: false
             )

    assert {:error, _} =
             Core.set_card_printing_collection_scope(
               card,
               %{
                 collection_scopes: [],
                 collection_scope_source: nil,
                 collection_scoped_at: now,
                 collection_expires_on: nil
               },
               authorize?: false
             )
  end

  test "import upsert preserves an existing collection scope" do
    id = token("preserve")
    card = TcgCheap.TestSupport.import_card_printing!(attrs(id))

    imported =
      CardPrinting
      |> Ash.Changeset.for_create(:import, Map.put(attrs(id), :name, "Updated #{id}"))
      |> Ash.create!(authorize?: false)

    assert imported.id == card.id
    assert imported.collection_scopes == ["legacy_local"]
    assert imported.collection_scope_source == "legacy"
    assert imported.collection_scoped_at == card.collection_scoped_at
  end
end
