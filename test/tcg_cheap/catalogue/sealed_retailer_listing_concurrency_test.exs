defmodule TcgCheap.Catalogue.SealedRetailerListingConcurrencyTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Core

  test "row lock allows only one review transition" do
    shop =
      Core.register_retailer!(%{
        slug: "concurrency-shop-#{System.unique_integer([:positive])}",
        source_key: "concurrency-#{System.unique_integer([:positive])}",
        name: "Concurrency Shop",
        category: "lgs"
      })

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    listing =
      Core.ingest_retailer_listing!(%{
        retailer_id: shop.id,
        source_listing_id: "concurrency-listing-#{System.unique_integer([:positive])}",
        source_title: "Title",
        direct_url: "https://shop.example/item",
        current_price_pln: Decimal.new("1"),
        stock_status: "in_stock",
        first_seen_at: now,
        last_seen_at: now,
        last_checked_at: now
      })

    mapping = Core.create_pending_listing_mapping!(%{retailer_listing_id: listing.id})

    results =
      1..2
      |> Task.async_stream(fn _ -> Core.reject_listing_mapping(mapping, %{reason: "review"}) end,
        max_concurrency: 2,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Core.get_listing_mapping!(listing.id).status == "rejected"
  end
end
