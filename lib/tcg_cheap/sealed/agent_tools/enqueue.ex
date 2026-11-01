defmodule TcgCheap.Sealed.AgentTools.Enqueue do
  @moduledoc """
  Queues a shop fetch, a catalogue import or a collection of suggested
  prices (`job:` option) as an Oban job.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Action.InvalidArgument
  alias TcgCheap.Sealed.{CatalogueImportWorker, FetchWorker, Shops, SuggestedPriceWorker}

  @impl true
  def run(input, opts, _context) do
    with {:ok, job} <- enqueue(opts[:job], input.arguments) do
      {:ok,
       %{
         job_id: job.id,
         worker: job.worker,
         args: job.args,
         state: job.state,
         already_queued: job.conflict?
       }}
    end
  end

  defp enqueue(:catalogue_import, _args), do: CatalogueImportWorker.enqueue()
  defp enqueue(:suggested_prices, _args), do: SuggestedPriceWorker.enqueue()

  defp enqueue(:shop_fetch, %{shop: shop}) do
    if shop in Shops.keys() do
      FetchWorker.enqueue(shop)
    else
      {:error,
       InvalidArgument.exception(
         field: :shop,
         message: "unknown shop; use one of #{Enum.join(Shops.keys(), ", ")}"
       )}
    end
  end
end
