defmodule TcgCheap.Catalogue.CuratedPlayablePolicyTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.CuratedPlayablePolicy

  test "is the fixed seven-printing NAIC manifest" do
    entries = CuratedPlayablePolicy.entries()
    assert length(entries) == 7

    assert Enum.all?(
             entries,
             &(Map.keys(&1) |> Enum.sort() == [
                 :category,
                 :collector_number,
                 :name,
                 :regulation_mark,
                 :set_id,
                 :tcgdex_id,
                 :trainer_type
               ])
           )

    assert entries |> Enum.map(& &1.tcgdex_id) |> Enum.uniq() |> length() == 7
    assert CuratedPlayablePolicy.evidence_version() == "2026-08-19-naic"
    assert CuratedPlayablePolicy.evidence_date() == ~D[2026-08-19]
    assert CuratedPlayablePolicy.expires_on() == ~D[2026-11-17]
    assert CuratedPlayablePolicy.entry("not-a-printing") == nil

    assert Enum.map(
             entries,
             &Map.take(&1, [
               :tcgdex_id,
               :name,
               :set_id,
               :category,
               :trainer_type,
               :regulation_mark
             ])
           ) == [
             %{
               tcgdex_id: "me01-131",
               name: "Ultra Ball",
               set_id: "me01",
               category: "Trainer",
               trainer_type: "Item",
               regulation_mark: "I"
             },
             %{
               tcgdex_id: "sv05-144",
               name: "Buddy-Buddy Poffin",
               set_id: "sv05",
               category: "Trainer",
               trainer_type: "Item",
               regulation_mark: "H"
             },
             %{
               tcgdex_id: "sv05-157",
               name: "Prime Catcher",
               set_id: "sv05",
               category: "Trainer",
               trainer_type: "Item",
               regulation_mark: "H"
             },
             %{
               tcgdex_id: "sv06-165",
               name: "Unfair Stamp",
               set_id: "sv06",
               category: "Trainer",
               trainer_type: "Item",
               regulation_mark: "H"
             },
             %{
               tcgdex_id: "sv07-133",
               name: "Crispin",
               set_id: "sv07",
               category: "Trainer",
               trainer_type: "Supporter",
               regulation_mark: "H"
             },
             %{
               tcgdex_id: "me01-114",
               name: "Boss's Orders",
               set_id: "me01",
               category: "Trainer",
               trainer_type: "Supporter",
               regulation_mark: "I"
             },
             %{
               tcgdex_id: "me01-119",
               name: "Lillie's Determination",
               set_id: "me01",
               category: "Trainer",
               trainer_type: "Supporter",
               regulation_mark: "I"
             }
           ]
  end

  test "validity is inclusive and bounded" do
    refute CuratedPlayablePolicy.valid_on?(~D[2026-08-18])
    assert CuratedPlayablePolicy.valid_on?(~D[2026-08-19])
    assert CuratedPlayablePolicy.valid_on?(~D[2026-11-17])
    refute CuratedPlayablePolicy.valid_on?(~D[2026-11-18])
  end
end
