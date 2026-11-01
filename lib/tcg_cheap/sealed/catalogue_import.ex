defmodule TcgCheap.Sealed.CatalogueImport do
  @moduledoc """
  Imports the Cardmarket sealed catalogue: the non-singles product list and
  the sealed rows of the price guide, downloaded through the hardened
  `TcgCheap.Pricing.CardmarketBulk.Adapter`.

  Products are upserted by Cardmarket id (products that disappear from the
  file are kept), today's Cardmarket trend is recorded per product, and
  offers are re-matched against the updated catalogue. Everything is written
  in one transaction; a failed download writes nothing.

  First `TcgCheap.Sealed.ExpansionSync` brings the TCGdex sets up to date
  for set names and language editions; when TCGdex fails, the sets already
  known are used.
  """

  alias TcgCheap.Pricing.CardmarketBulk.Adapter
  alias TcgCheap.Repo
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Catalogue, ExpansionSync, Product, Refresh, TcgdexSet}

  require Logger

  @chunk 500

  @spec run(keyword()) :: {:ok, %{products: non_neg_integer()}} | {:error, term()}
  def run(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    adapter_opts = [request_options: Keyword.get(opts, :request_options, [])]

    sync_expansions(adapter_opts)

    with {:ok, products} <- Adapter.fetch_sealed_products(adapter_opts),
         {:ok, prices} <- Adapter.fetch_sealed_prices(adapter_opts) do
      rows =
        Catalogue.rows(
          products.rows,
          prices.rows,
          DateTime.to_date(prices.created_at),
          TcgdexSet.by_expansion(Sealed.list_tcgdex_sets!())
        )

      Repo.transaction(
        fn ->
          ids = upsert_products(rows)
          record_trends(rows, ids, DateTime.to_date(now))
          Refresh.recompute(now)
          %{products: length(rows)}
        end,
        timeout: Refresh.transaction_timeout()
      )
    end
  end

  # Never in the way of the import: a failed or crashed sync is only logged.
  defp sync_expansions(adapter_opts) do
    case ExpansionSync.run(adapter_opts) do
      {:ok, %{checked: count}} -> Logger.info("TCGdex sets checked: #{count}")
      {:error, reason} -> Logger.warning("TCGdex set sync failed: #{inspect(reason)}")
    end
  rescue
    exception -> Logger.warning("TCGdex set sync crashed: #{Exception.message(exception)}")
  end

  defp upsert_products(rows) do
    rows
    |> Enum.chunk_every(@chunk)
    |> Enum.flat_map(fn chunk ->
      %Ash.BulkResult{status: :success, records: records} =
        Ash.bulk_create!(chunk, Product, :import,
          domain: Sealed,
          return_records?: true,
          return_errors?: true,
          stop_on_error?: true
        )

      Enum.map(records, &{&1.cardmarket_id, &1.id})
    end)
    |> Map.new()
  end

  defp record_trends(rows, ids, today) do
    rows
    |> Enum.filter(& &1.cardmarket_trend)
    |> Enum.map(
      &%{
        product_id: Map.fetch!(ids, &1.cardmarket_id),
        date: today,
        cardmarket_trend: &1.cardmarket_trend
      }
    )
    |> Enum.chunk_every(@chunk)
    |> Enum.each(&Refresh.bulk_record(&1, :record_cardmarket_trend))
  end
end
