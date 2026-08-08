defmodule TcgCheap.Pricing.SealedListingObservationConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.Catalogue.{Retailer, RetailerListing}
  alias TcgCheap.Core
  alias TcgCheap.Pricing.SealedListingObservation
  alias TcgCheap.Repo

  setup do
    state =
      Sandbox.unboxed_run(Repo, fn ->
        retailer =
          Core.register_retailer!(%{
            slug: "observation-concurrent-#{System.unique_integer([:positive])}",
            source_key: "observation-concurrent-#{System.unique_integer([:positive])}",
            name: "Concurrent Observation Shop",
            category: "regular_retailer"
          })

        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        %{
          retailer: retailer,
          attrs: %{
            retailer_id: retailer.id,
            source_listing_id:
              "observation-concurrent-listing-#{System.unique_integer([:positive])}",
            source_title: "Concurrent Box",
            direct_url: "https://shop.example/concurrent",
            gtin: "4006381333931",
            current_price_pln: Decimal.new("10.00"),
            stock_status: "in_stock",
            first_seen_at: now,
            last_seen_at: now,
            last_checked_at: now,
            source_payload: %{provider: "fixture"}
          }
        }
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        case Core.get_retailer_listing(state.retailer.id, state.attrs.source_listing_id) do
          {:ok, nil} ->
            :ok

          {:ok, listing} ->
            Repo.delete_all(
              from observation in SealedListingObservation,
                where: observation.retailer_listing_id == ^listing.id
            )

            Repo.delete_all(
              from listing_row in RetailerListing, where: listing_row.id == ^listing.id
            )

          {:error, _error} ->
            :ok
        end

        Repo.delete_all(from retailer in Retailer, where: retailer.id == ^state.retailer.id)
      end)
    end)

    {:ok, state: state}
  end

  test "independent concurrent ingests append one observation", %{state: state} do
    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> Sandbox.unboxed_run(Repo, fn -> Core.ingest_retailer_listing(state.attrs) end)
          end
        end)
      end

    assert_receive {:ready, first_task}, 5_000
    assert_receive {:ready, second_task}, 5_000
    send(first_task, :go)
    send(second_task, :go)

    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.all?(results, &match?({:ok, _}, &1))

    Sandbox.unboxed_run(Repo, fn ->
      listing = Core.get_retailer_listing!(state.retailer.id, state.attrs.source_listing_id)
      assert length(Core.list_sealed_listing_observation_history!(listing.id)) == 1
    end)
  end
end
