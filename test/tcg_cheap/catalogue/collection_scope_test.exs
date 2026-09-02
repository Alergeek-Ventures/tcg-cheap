defmodule TcgCheap.Catalogue.CollectionScopeTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Catalogue.{CardPrinting, Importer}
  alias TcgCheap.Core

  defp token(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp attrs(token),
    do: %{
      tcgdex_id: token,
      name: "Scope #{token}",
      set_name: "Set #{token}",
      collector_number: "1",
      card_set_id:
        Core.import_card_set!(%{
          tcgdex_id: "set-#{token}",
          name: "Set #{token}",
          series_id: "sv",
          series_name: "Scarlet & Violet"
        }).id
    }

  defp set_scope(card, attrs),
    do:
      card
      |> Ash.Changeset.for_update(:set_collection_scope, attrs)
      |> Ash.update(authorize?: false)

  defp add_scope(card, scopes, expiry, scoped_at),
    do:
      Core.add_card_printing_collection_scopes(card, scopes, expiry, scoped_at, authorize?: false)

  test "public ID, bulk, search, and recent include locally imported rows regardless of scope" do
    id = token("unscoped")

    card =
      TcgCheap.TestSupport.import_card_printing!(
        Map.put(attrs(id), :last_synced_at, DateTime.utc_now()),
        scoped?: false
      )

    assert {:ok, internal_card} = Core.get_card_printing_by_tcgdex_id(id)
    assert internal_card.id == card.id
    assert {:ok, public_card} = Core.get_public_card_printing_by_tcgdex_id(id)
    assert public_card.id == card.id
    assert {:ok, [bulk_card]} = Core.list_public_card_printings_by_tcgdex_ids([id])
    assert bulk_card.id == card.id
    assert {:ok, [search_card]} = Core.search_public_card_printings(id)
    assert search_card.id == card.id
    assert {:ok, recent} = Core.list_public_recently_tracked_card_printings()
    assert Enum.any?(recent, &(&1.id == card.id))
  end

  test "expired locally imported rows remain public while scope metadata remains separate" do
    active_id = token("active")
    expired_id = token("expired")
    boundary_id = token("boundary")

    active = TcgCheap.TestSupport.import_card_printing!(attrs(active_id))

    TcgCheap.TestSupport.import_card_printing!(attrs(expired_id),
      expires_on: Date.add(Date.utc_today(), -1)
    )

    TcgCheap.TestSupport.import_card_printing!(attrs(boundary_id), expires_on: Date.utc_today())

    assert {:ok, public_active} = Core.get_public_card_printing_by_tcgdex_id(active_id)
    assert public_active.id == active.id
    assert {:ok, public_expired} = Core.get_public_card_printing_by_tcgdex_id(expired_id)
    assert public_expired.id != nil
    assert {:ok, boundary} = Core.get_public_card_printing_by_tcgdex_id(boundary_id)
    assert boundary.tcgdex_id == boundary_id

    assert {:ok, bulk_cards} =
             Core.list_public_card_printings_by_tcgdex_ids([active_id, expired_id])

    assert Enum.sort(Enum.map(bulk_cards, & &1.tcgdex_id)) == Enum.sort([active_id, expired_id])
    assert {:ok, [bulk_expired]} = Core.list_public_card_printings_by_tcgdex_ids([expired_id])
    assert bulk_expired.tcgdex_id == expired_id

    assert {:ok, [search_active]} = Core.search_public_card_printings(active_id)
    assert search_active.id == active.id
    assert {:ok, [search_expired]} = Core.search_public_card_printings(expired_id)
    assert search_expired.id == public_expired.id
  end

  test "detail candidates use lexical keysets, validate limits, and exclude fully imported rows" do
    set =
      Core.import_card_set!(%{
        tcgdex_id: token("candidate-set"),
        name: "Set",
        series_id: "sv"
      })

    a =
      TcgCheap.TestSupport.import_card_printing!(
        %{
          tcgdex_id: "a-#{token("candidate")}",
          name: "A",
          set_name: "Set",
          collector_number: "1",
          card_set_id: set.id
        },
        scoped?: false
      )

    b =
      TcgCheap.TestSupport.import_card_printing!(
        %{
          tcgdex_id: "b-#{token("candidate")}",
          name: "B",
          set_name: "Set",
          collector_number: "2",
          card_set_id: set.id
        },
        scoped?: false
      )

    c =
      TcgCheap.TestSupport.import_card_printing!(
        %{
          tcgdex_id: "c-#{token("candidate")}",
          name: "C",
          set_name: "Set",
          collector_number: "3",
          card_set_id: set.id
        },
        scoped?: false
      )

    synced = ~U[2026-03-01 00:00:00Z]

    assert {:ok, _} =
             Importer.import_fetched_card(
               %{
                 "id" => c.tcgdex_id,
                 "name" => "C",
                 "localId" => "3",
                 "set" => %{"id" => set.tcgdex_id}
               },
               %{"id" => set.tcgdex_id, "name" => set.name},
               c.tcgdex_id,
               expected_set_id: set.tcgdex_id,
               synced_at: synced
             )

    assert {:ok, [first]} = Core.list_detail_enrichment_candidates(nil, 1, authorize?: false)
    assert first.tcgdex_id == a.tcgdex_id

    assert {:ok, [second]} =
             Core.list_detail_enrichment_candidates(a.tcgdex_id, 1, authorize?: false)

    assert second.tcgdex_id == b.tcgdex_id
    assert {:error, _} = Core.list_detail_enrichment_candidates(nil, 0, authorize?: false)
    assert {:error, _} = Core.list_detail_enrichment_candidates(nil, 1_001, authorize?: false)
  end

  test "scope metadata is validated" do
    card = TcgCheap.TestSupport.import_card_printing!(attrs(token("invalid")), scoped?: false)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:error, _} =
             set_scope(
               card,
               %{
                 collection_scopes: ["not-a-scope"],
                 collection_scope_source: "system",
                 collection_scoped_at: now,
                 collection_expires_on: nil
               }
             )

    assert {:error, _} =
             set_scope(
               card,
               %{
                 collection_scopes: ["legacy_local"],
                 collection_scope_source: "not-a-source",
                 collection_scoped_at: now,
                 collection_expires_on: nil
               }
             )

    assert {:error, _} =
             set_scope(
               card,
               %{
                 collection_scopes: [],
                 collection_scope_source: nil,
                 collection_scoped_at: now,
                 collection_expires_on: nil
               }
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

  test "automated additions merge finite expiries, preserve metadata, and make pitch/legacy permanent" do
    id = token("merge")
    card = TcgCheap.TestSupport.import_card_printing!(attrs(id), scoped?: false)
    first_at = ~U[2025-01-01 00:00:00Z]
    later_at = ~U[2025-02-01 00:00:00Z]

    assert {:ok, _} = add_scope(card, ["curated_playable"], ~D[2026-11-17], later_at)
    current = Core.get_card_printing_by_tcgdex_id!(id)
    assert current.collection_expires_on == ~D[2026-11-17]
    assert {:ok, _} = add_scope(current, ["rolling_ir_sir"], ~D[2027-01-01], first_at)
    current = Core.get_card_printing_by_tcgdex_id!(id)
    assert current.collection_scopes == ["curated_playable", "rolling_ir_sir"]
    assert current.collection_expires_on == ~D[2027-01-01]
    assert DateTime.compare(current.collection_scoped_at, first_at) == :eq
    assert {:ok, _} = add_scope(current, ["pitch_black_full"], nil, later_at)
    assert Core.get_card_printing_by_tcgdex_id!(id).collection_expires_on == nil
  end

  test "administrator and legacy provenance are retained" do
    id = token("provenance")
    card = TcgCheap.TestSupport.import_card_printing!(attrs(id), scoped?: false)

    assert {:ok, card} =
             set_scope(
               card,
               %{
                 collection_scopes: ["legacy_local"],
                 collection_scope_source: "legacy",
                 collection_scoped_at: ~U[2025-01-01 00:00:00Z],
                 collection_expires_on: nil
               }
             )

    assert {:ok, _} =
             add_scope(
               card,
               ["curated_playable"],
               ~D[2026-11-17],
               ~U[2026-02-01 00:00:00Z]
             )

    updated = Core.get_card_printing_by_tcgdex_id!(id)
    assert updated.collection_scope_source == "legacy"
    assert updated.collection_expires_on == nil
  end

  test "domain scope additions reject invalid, empty, and expired incoming scopes" do
    id = token("rejected")
    card = TcgCheap.TestSupport.import_card_printing!(attrs(id), scoped?: false)
    scoped_at = ~U[2025-01-01 00:00:00Z]

    assert {:error, _} = add_scope(card, ["not-a-scope"], ~D[2026-01-01], scoped_at)
    assert {:error, _} = add_scope(card, [], ~D[2026-01-01], scoped_at)
    assert {:error, _} = add_scope(card, ["curated_playable"], ~D[2024-12-31], scoped_at)

    rejected = Core.get_card_printing_by_tcgdex_id!(id)
    assert rejected.collection_scopes == []
    assert is_nil(rejected.collection_scope_source)
    assert is_nil(rejected.collection_scoped_at)
    assert is_nil(rejected.collection_expires_on)
  end

  test "rejects an expired addition without changing an existing finite scope" do
    id = token("expired-addition")
    card = TcgCheap.TestSupport.import_card_printing!(attrs(id), scoped?: false)
    valid_scoped_at = ~U[2025-01-01 00:00:00Z]

    assert {:ok, _} = add_scope(card, ["curated_playable"], ~D[2027-01-01], valid_scoped_at)

    current = Core.get_card_printing_by_tcgdex_id!(id)

    assert {:error, _} =
             add_scope(current, ["rolling_ir_sir"], ~D[2025-12-31], ~U[2026-01-01 00:00:00Z])

    unchanged = Core.get_card_printing_by_tcgdex_id!(id)
    assert unchanged.collection_scopes == ["curated_playable"]
    assert unchanged.collection_expires_on == ~D[2027-01-01]
    assert DateTime.compare(unchanged.collection_scoped_at, valid_scoped_at) == :eq
  end
end
