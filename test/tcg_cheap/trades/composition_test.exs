defmodule TcgCheap.Trades.CompositionTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Trades.Composition

  test "round-trips punctuation card IDs" do
    composition = Composition.add(%Composition{}, :left, "exu-!")
    composition = Composition.add(composition, :right, "exu-%3F")

    {parsed, meta} = Composition.from_params(Composition.to_params(composition))

    refute meta.malformed?
    assert parsed == composition
  end

  test "round trips empty and ordered compositions without prices" do
    composition = %Composition{left: [{"z", 1}, {"a", 2}], right: [{"m", 3}]}

    assert Composition.from_params(%{}) ==
             {%Composition{}, %{malformed?: false, truncated?: false}}

    assert Composition.to_params(composition) == %{"left" => "a:2,z:1", "right" => "m:3"}
    assert Composition.to_path(composition) == "/trade?left=a%3A2%2Cz%3A1&right=m%3A3"
    refute Composition.to_path(composition) =~ "price"

    assert Composition.from_params(Composition.to_params(composition)) ==
             {%Composition{left: [{"a", 2}, {"z", 1}], right: [{"m", 3}]},
              %{malformed?: false, truncated?: false}}
  end

  test "merges duplicates, caps quantities, and keeps sides independent" do
    {composition, metadata} = Composition.from_params(%{"left" => "x:70,x:40", "right" => "x:2"})
    assert metadata == %{malformed?: false, truncated?: false}
    assert composition == %Composition{left: [{"x", 99}], right: [{"x", 2}]}
  end

  test "supports UI mutations and rejects invalid inputs" do
    composition = %Composition{}
    composition = Composition.add(composition, :left, "x")
    composition = Composition.increment(composition, :left, "x")
    assert composition == %Composition{left: [{"x", 2}], right: []}
    assert Composition.put_quantity(composition, :left, "x", 5).left == [{"x", 5}]
    assert Composition.decrement(composition, :left, "x").left == [{"x", 1}]

    assert Composition.decrement(Composition.decrement(composition, :left, "x"), :left, "x").left ==
             []

    assert Composition.remove(composition, :left, "x") == %Composition{}
    assert Composition.add(composition, :wat, "x") == composition
    assert Composition.add(composition, :left, "bad/id") == composition
    assert Composition.put_quantity(composition, :left, "x", 100).left == [{"x", 2}]
    assert Composition.side_items(composition, :right) == []
  end

  test "reports malformed values and rejects oversized sides safely" do
    {composition, metadata} =
      Composition.from_params(%{
        "left" => "ok:1,bad:0,also:2:3,other:2" <> String.duplicate("x", 8_000)
      })

    assert metadata.malformed?
    assert metadata.truncated?
    assert composition.left == []

    assert Composition.from_params(%{"left" => 42}) ==
             {%Composition{}, %{malformed?: true, truncated?: false}}
  end

  test "empty sides are clean, but empty comma tokens are malformed" do
    assert Composition.from_params(%{"left" => ""}) ==
             {%Composition{}, %{malformed?: false, truncated?: false}}

    {composition, metadata} = Composition.from_params(%{"left" => "x:1,,y:1", "right" => ","})
    assert composition == %Composition{left: [{"x", 1}, {"y", 1}], right: []}
    assert metadata == %{malformed?: true, truncated?: false}
  end

  test "limits each side to fifty unique rows" do
    value = Enum.map_join(1..60, ",", &"id#{&1}:1")
    {composition, metadata} = Composition.from_params(%{"left" => value})
    assert metadata.truncated?
    assert length(composition.left) == 50
    assert composition.left == Enum.take(Enum.map(1..60, &{"id#{&1}", 1}) |> Enum.sort(), 50)
  end

  test "does not evict rows when adding a new ID at the row limit" do
    rows = Enum.map(1..50, &{"id#{&1}", 1})
    composition = %Composition{left: Enum.sort(rows)}

    assert Composition.add(composition, :left, "new") == composition

    assert Composition.add(composition, :left, "id1") == %Composition{
             left: [{"id1", 2} | Enum.drop(Enum.sort(rows), 1)]
           }
  end

  test "invalid mutation paths normalize malformed structs" do
    malformed = %Composition{left: [{"bad/id", 2}, {"ok", 1}, {"ok", 2}], right: :bad}
    assert Composition.add(malformed, :wat, "ok") == %Composition{left: [{"ok", 3}], right: []}

    assert Composition.decrement(malformed, :wat, "ok") == %Composition{
             left: [{"ok", 3}],
             right: []
           }

    assert Composition.put_quantity(malformed, :wat, "ok", 1) == %Composition{
             left: [{"ok", 3}],
             right: []
           }
  end
end
