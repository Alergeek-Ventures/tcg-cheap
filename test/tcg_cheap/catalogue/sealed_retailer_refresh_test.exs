defmodule TcgCheap.Catalogue.SealedRetailerRefreshTestAdapter do
  alias TcgCheap.Catalogue.SealedRetailerAdapter
  def source_key, do: "stub-#{Process.get(:refresh_source_key, "default")}"

  def fetch_listings(_retailer, _) do
    case Process.get(:refresh_listings, []) do
      :raise ->
        raise "adapter failed"

      :throw ->
        throw(:adapter_failed)

      :exit ->
        exit(:adapter_failed)

      {:disable, expected} ->
        TcgCheap.Core.disable_retailer!(expected)
        {:ok, [listing("raced")]}

      value ->
        {:ok, value}
    end
  end

  def listing(id, price \\ "10.00", stock \\ "in_stock") do
    now = ~U[2026-08-09 12:00:00Z]

    %SealedRetailerAdapter.Listing{
      source_listing_id: id,
      source_title: "Booster #{id}",
      direct_url: "https://example.test/#{id}",
      current_price_pln: Decimal.new(price),
      currency: "PLN",
      stock_status: stock,
      first_seen_at: now,
      last_seen_at: now,
      last_checked_at: now,
      source_payload: %{"fixture" => true}
    }
  end
end

defmodule TcgCheap.Catalogue.SealedRetailerRefreshTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Catalogue.{SealedRetailerRefresh, SealedRetailerRefreshTestAdapter}
  alias TcgCheap.Core

  defp retailer do
    key = "stub-#{System.unique_integer([:positive])}"
    Process.put(:refresh_source_key, String.replace_prefix(key, "stub-", ""))

    Core.register_retailer!(%{
      slug: "refresh-#{System.unique_integer([:positive])}",
      source_key: key,
      name: "Refresh Shop",
      category: "regular_retailer",
      homepage_url: "https://example.test"
    })
  end

  test "validates the complete batch before writing and preserves absent listings" do
    retailer = retailer()
    valid = SealedRetailerRefreshTestAdapter.listing("one")
    Process.put(:refresh_listings, [valid, valid])

    assert {:error, :duplicate_source_listing_id} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    assert {:ok, []} = Core.list_active_retailer_listings(retailer.id)

    Process.put(:refresh_listings, [valid])

    assert {:ok, %{persisted: 1}} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    Process.put(:refresh_listings, [])

    assert {:ok, %{persisted: 0}} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    assert {:ok, [listing]} = Core.list_active_retailer_listings(retailer.id)
    assert listing.stock_status == "in_stock"
  end

  test "rejects a later invalid row before writing an earlier valid row" do
    retailer = retailer()
    valid = SealedRetailerRefreshTestAdapter.listing("valid")
    invalid = %{valid | source_listing_id: "invalid", source_title: String.duplicate("x", 501)}
    Process.put(:refresh_listings, [valid, invalid])

    assert {:error, :malformed_listing} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    assert {:ok, []} = Core.list_active_retailer_listings(retailer.id)
  end

  test "rejects malformed rows and disabled or mismatched retailers" do
    retailer = retailer()
    Process.put(:refresh_listings, [%{bad: true}])

    assert {:error, :malformed_listing} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    assert {:ok, []} = Core.list_active_retailer_listings(retailer.id)
    disabled = Core.disable_retailer!(retailer)

    assert {:error, :retailer_not_active_or_mismatched} =
             SealedRetailerRefresh.refresh(
               disabled.id,
               disabled.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    other = retailer()

    assert {:error, :retailer_not_active_or_mismatched} =
             SealedRetailerRefresh.refresh(
               other.id,
               disabled.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )
  end

  test "turns adapter callback failures into stable permanent errors" do
    retailer = retailer()
    Process.put(:refresh_listings, :raise)

    assert {:error, :adapter_exception} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    Process.put(:refresh_listings, :throw)

    assert {:error, :adapter_throw} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    Process.put(:refresh_listings, :exit)

    assert {:error, :adapter_exit} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    assert {:ok, []} = Core.list_active_retailer_listings(retailer.id)
  end

  test "does not ingest when the retailer is disabled during fetch" do
    retailer = retailer()
    Process.put(:refresh_listings, {:disable, retailer})

    assert {:error, :retailer_not_active_or_mismatched} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    assert {:ok, []} = Core.list_active_retailer_listings(retailer.id)
  end

  test "reruns do not append unchanged observations but changes do" do
    retailer = retailer()
    first = SealedRetailerRefreshTestAdapter.listing("changed")
    Process.put(:refresh_listings, [first])

    assert {:ok, _} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    assert {:ok, [stored]} = Core.list_active_retailer_listings(retailer.id)
    assert {:ok, history} = Core.list_sealed_listing_observation_history(stored.id)
    assert length(history) == 1

    Process.put(:refresh_listings, [first])

    assert {:ok, _} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    assert {:ok, history} = Core.list_sealed_listing_observation_history(stored.id)
    assert length(history) == 1

    changed = %{
      first
      | current_price_pln: Decimal.new("11.00"),
        stock_status: "sold_out",
        last_checked_at: ~U[2026-08-09 13:00:00Z],
        last_seen_at: ~U[2026-08-09 13:00:00Z]
    }

    Process.put(:refresh_listings, [changed])

    assert {:ok, _} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    assert {:ok, history} = Core.list_sealed_listing_observation_history(stored.id)
    assert length(history) == 2
  end

  test "rolls back earlier rows when a later observation conflicts" do
    retailer = retailer()
    existing = SealedRetailerRefreshTestAdapter.listing("existing")
    Process.put(:refresh_listings, [existing])

    assert {:ok, _result} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    new_listing = SealedRetailerRefreshTestAdapter.listing("new")
    conflicting = %{existing | current_price_pln: Decimal.new("99.00")}
    Process.put(:refresh_listings, [new_listing, conflicting])

    assert {:error, :persistence_invalid} =
             SealedRetailerRefresh.refresh(
               retailer.id,
               retailer.source_key,
               SealedRetailerRefreshTestAdapter,
               []
             )

    assert {:ok, [persisted]} = Core.list_active_retailer_listings(retailer.id)
    assert persisted.source_listing_id == "existing"
    assert persisted.current_price_pln == Decimal.new("10.00")
    assert {:ok, [_observation]} = Core.list_sealed_listing_observation_history(persisted.id)
  end
end
