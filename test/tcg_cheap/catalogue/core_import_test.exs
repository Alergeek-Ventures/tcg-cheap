defmodule TcgCheap.Catalogue.CoreImportTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.{Core, Repo}

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp attrs(overrides) do
    Map.merge(
      %{
        tcgdex_id: "core-#{System.unique_integer([:positive])}",
        name: "Card",
        set_name: "Set",
        collector_number: "1"
      },
      overrides
    )
  end

  test "rejects mapping fields that contradict pending, matched, or review" do
    invalid = [
      %{mapping_status: "pending", cardmarket_product_id: 42},
      %{mapping_status: "unmatched", mapping_review_reason: "needs review"},
      %{mapping_status: "matched", cardmarket_product_id: nil},
      %{mapping_status: "matched", cardmarket_product_id: 42, mapping_review_reason: "extra"},
      %{mapping_status: "review", mapping_review_reason: " "},
      %{mapping_status: "review", cardmarket_product_id: 42, mapping_review_reason: "reason"}
    ]

    for overrides <- invalid do
      assert_raise Ash.Error.Invalid, fn ->
        TcgCheap.TestSupport.import_card_printing!(attrs(overrides))
      end
    end

    assert Repo.aggregate(from(c in "card_printings"), :count, :id) == 0
  end

  test "rejects an official count greater than the total count" do
    assert_raise Ash.Error.Invalid, fn ->
      Core.import_card_set!(%{
        tcgdex_id: "invalid-count",
        name: "Set",
        official_count: 11,
        total_count: 10
      })
    end
  end

  test "default brief upserts cannot erase a pending image" do
    suffix = System.unique_integer([:positive])
    set = Core.import_card_set!(%{tcgdex_id: "brief-image-set-#{suffix}", name: "Set"})

    attrs = %{
      tcgdex_id: "brief-image-card-#{suffix}",
      name: "Card",
      set_name: "Set",
      collector_number: "1",
      card_set_id: set.id,
      image_url: "https://assets.example/original.webp"
    }

    assert {:ok, first} = Core.seed_card_printing_brief(attrs)
    assert {:ok, second} = Core.seed_card_printing_brief(Map.delete(attrs, :image_url))
    assert {:ok, third} = Core.seed_card_printing_brief(Map.put(attrs, :image_url, nil))
    assert first.id == second.id and second.id == third.id
    assert third.image_url == "https://assets.example/original.webp"
  end
end
