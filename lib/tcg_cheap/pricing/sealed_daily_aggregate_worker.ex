defmodule TcgCheap.Pricing.SealedDailyAggregateWorker do
  @moduledoc "Daily local-only sealed-market aggregate worker."
  use Oban.Worker,
    queue: :sealed_aggregates,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [],
      states: [:available, :scheduled, :executing, :retryable, :suspended],
      fields: [:worker, :args]
    ]

  alias TcgCheap.Core
  alias TcgCheap.Pricing.SealedDailyAggregateCalculator

  @impl true
  def perform(%Oban.Job{args: args}) do
    with :ok <- validate_args(args),
         {:ok, as_of} <- clock(),
         {:ok, products} <- Core.list_public_sealed_products(),
         :ok <- process(products, as_of) do
      :ok
    else
      {:cancel, reason} -> {:cancel, reason}
      {:retry, reason} -> {:error, reason}
      {:error, %Ash.Error.Invalid{}} -> {:cancel, :persistence_invalid}
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(_), do: {:cancel, :malformed_job_args}

  defp validate_args(%{} = args) when map_size(args) == 0, do: :ok
  defp validate_args(_), do: {:cancel, :malformed_job_args}

  defp clock do
    case Application.get_env(:tcg_cheap, :sealed_daily_aggregate_clock, &DateTime.utc_now/0) do
      clock when is_function(clock, 0) -> safely_clock(clock)
      _ -> {:cancel, :invalid_clock_configuration}
    end
  end

  defp safely_clock(clock) do
    case clock.() do
      %DateTime{} = value -> {:ok, value}
      _ -> {:cancel, :invalid_clock}
    end
  rescue
    _ -> {:cancel, :invalid_clock}
  catch
    _, _ -> {:cancel, :invalid_clock}
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity,Credo.Check.Refactor.Nesting
  defp process(products, as_of) when is_list(products) do
    Enum.reduce_while(products, :ok, fn product, :ok ->
      case product_id(product) do
        {:ok, id} -> process_product(id, as_of)
        {:error, reason} -> {:cancel, reason}
      end
      |> case do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
        {:cancel, reason} -> {:halt, {:cancel, reason}}
      end
    end)
  end

  defp process(_products, _as_of), do: {:cancel, :malformed_products}

  defp process_product(product_id, as_of) do
    case Core.list_public_listing_mappings_for_product(product_id) do
      {:ok, []} ->
        :ok

      {:ok, mappings} ->
        with {:ok, offers} <- mapping_offers(mappings),
             {:ok, attrs} <- SealedDailyAggregateCalculator.calculate(offers, as_of) do
          persist(product_id, attrs)
        else
          {:error, reason} -> {:cancel, reason}
        end

      {:error, _} ->
        {:error, :mapping_read_failed}
    end
  end

  defp product_id(%{id: id}) when is_binary(id), do: {:ok, id}
  defp product_id(_), do: {:error, :malformed_product}

  defp mapping_offers(mappings) when is_list(mappings) do
    Enum.reduce_while(mappings, {:ok, %{current: [], sold_out: []}}, fn mapping, {:ok, acc} ->
      case mapping_offer(mapping) do
        {:ok, status, offer} ->
          {:cont, {:ok, Map.update!(acc, status, &[offer | &1])}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, %{current: current, sold_out: sold_out}} ->
        {:ok, %{current: Enum.reverse(current), sold_out: Enum.reverse(sold_out)}}

      error ->
        error
    end
  end

  defp mapping_offers(_), do: {:error, :malformed_mappings}

  defp mapping_offer(%{
         status: "matched",
         retailer_listing:
           %{stock_status: status, retailer: %{id: id, category: category} = retailer} = listing
       })
       when status in ["in_stock", "sold_out"] and is_binary(id) and
              category in ["regular_retailer", "lgs"] do
    {:ok, status_key(status), %{listing: listing, retailer: retailer}}
  end

  defp mapping_offer(_), do: {:error, :malformed_mapping}

  defp status_key("in_stock"), do: :current
  defp status_key("sold_out"), do: :sold_out

  defp persist(product_id, attrs) do
    case Core.record_sealed_daily_aggregate(Map.put(attrs, :sealed_product_id, product_id)) do
      {:ok, _} -> :ok
      {:error, %Ash.Error.Invalid{}} -> {:cancel, :persistence_invalid}
      {:error, _} -> {:error, :persistence_failed}
    end
  end
end
