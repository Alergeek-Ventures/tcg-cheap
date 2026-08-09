defmodule TcgCheap.Pricing.SealedBuyingGuideInput do
  @moduledoc "Reconstructs guide inputs exclusively from immutable aggregate evidence."

  alias TcgCheap.Pricing.SealedDailyAggregateCalculator

  @categories ["regular_retailer", "lgs"]
  @statuses ["in_stock", "sold_out"]
  @projection_fields [
    :aggregate_date,
    :calculation_version,
    :currency,
    :status,
    :limited_reason,
    :benchmark_pln,
    :typical_low_pln,
    :typical_high_pln,
    :fresh_regular_retailer_count,
    :fresh_lgs_count,
    :recent_sold_out_0_14_day_count,
    :sold_out_15_30_day_count,
    :stale_or_future_current_offer_count,
    :unique_source_retailer_count,
    :latest_nonfuture_checked_at,
    :calculated_at
  ]

  @spec build(map(), map(), [map()]) :: {:ok, map()} | {:error, atom()}
  def build(product, aggregate, history)
      when is_map(product) and is_map(aggregate) and is_list(history) do
    with :ok <- valid_product(product),
         :ok <- valid_aggregate(product, aggregate),
         {:ok, evidence} <-
           validate_evidence(Map.get(aggregate, :source_evidence), aggregate.calculated_at),
         {:ok, offers} <- offers(evidence),
         {:ok, projection} <-
           SealedDailyAggregateCalculator.calculate(offers, aggregate.calculated_at),
         :ok <- projection_matches?(aggregate, projection) do
      {:ok,
       %{
         current_aggregate: aggregate,
         history: history,
         msrp_pln: Map.get(aggregate, :source_msrp_pln),
         lgs_price_evidence: lgs_rows(evidence, aggregate.calculated_at),
         sold_out_price_evidence: sold_out_rows(evidence, aggregate.calculated_at),
         mapping_confident?: aggregate.source_mapping_confident
       }}
    end
  end

  def build(_, _, _), do: {:error, :malformed_input_boundary}

  defp valid_product(%{id: id, publication_status: "approved"}) when is_binary(id), do: :ok
  defp valid_product(_), do: {:error, :invalid_product}

  defp valid_aggregate(
         %{id: id},
         %{sealed_product_id: id, calculated_at: %DateTime{}, source_mapping_confident: value}
       )
       when is_boolean(value), do: :ok

  defp valid_aggregate(%{id: id}, %{sealed_product_id: id}), do: {:error, :invalid_aggregate}
  defp valid_aggregate(%{id: _}, %{sealed_product_id: _}), do: {:error, :cross_product_aggregate}
  defp valid_aggregate(_, _), do: {:error, :invalid_aggregate}

  defp validate_evidence(evidence, calculated_at)
       when is_list(evidence) and is_struct(calculated_at, DateTime) do
    with :ok <- unique_evidence(evidence),
         {:ok, values} <-
           Enum.reduce_while(evidence, {:ok, []}, fn row, acc ->
             validate_row(row, calculated_at, acc)
           end) do
      {:ok, Enum.reverse(values)}
    end
  end

  defp validate_evidence(_, _), do: {:error, :malformed_source_evidence}

  defp unique_evidence(rows) do
    mapping_ids = Enum.map(rows, &Map.get(&1, :mapping_id))
    listing_ids = Enum.map(rows, &Map.get(&1, :listing_id))

    if length(mapping_ids) == length(Enum.uniq(mapping_ids)) and
         length(listing_ids) == length(Enum.uniq(listing_ids)) and
         Enum.all?(mapping_ids ++ listing_ids, &is_binary/1),
       do: :ok,
       else: {:error, :duplicate_source_evidence}
  end

  defp validate_row(row, calculated_at, {:ok, acc}) do
    if valid_row?(row, calculated_at),
      do: {:cont, {:ok, [row | acc]}},
      else: {:halt, {:error, :malformed_source_evidence}}
  end

  defp valid_row?(row, calculated_at) when is_map(row) do
    valid_identity?(row) and valid_classification?(row) and valid_times?(row, calculated_at) and
      finite_confidence?(Map.get(row, :confidence)) and
      valid_price?(Map.get(row, :price_pln), Map.get(row, :stock_status))
  end

  defp valid_row?(_, _), do: false

  defp valid_identity?(row),
    do:
      is_binary(Map.get(row, :mapping_id)) and is_binary(Map.get(row, :listing_id)) and
        is_binary(Map.get(row, :retailer_id))

  defp valid_classification?(row),
    do:
      Map.get(row, :retailer_category) in @categories and Map.get(row, :stock_status) in @statuses

  defp valid_times?(row, calculated_at) do
    approved_at = Map.get(row, :approved_at)

    match?(%DateTime{}, approved_at) and match?(%DateTime{}, Map.get(row, :checked_at)) and
      DateTime.compare(approved_at, calculated_at) != :gt
  end

  defp finite_confidence?(%Decimal{} = value),
    do:
      not Decimal.nan?(value) and not Decimal.inf?(value) and
        Decimal.compare(value, Decimal.new(0)) == :gt and
        Decimal.compare(value, Decimal.new(1)) != :gt

  defp finite_confidence?(_), do: false

  defp valid_price?(nil, "sold_out"), do: true

  defp valid_price?(%Decimal{} = value, _),
    do:
      not Decimal.nan?(value) and not Decimal.inf?(value) and
        Decimal.compare(value, Decimal.new(0)) == :gt

  defp valid_price?(_, _), do: false

  defp offers(rows) do
    {:ok,
     Enum.group_by(rows, & &1.stock_status)
     |> Map.get("in_stock", [])
     |> Enum.map(&offer/1)
     |> then(fn current ->
       %{
         current: current,
         sold_out: rows |> Enum.filter(&(&1.stock_status == "sold_out")) |> Enum.map(&offer/1)
       }
     end)}
  end

  defp offer(row) do
    %{
      listing: %{
        id: row.listing_id,
        stock_status: row.stock_status,
        current_price_pln: row.price_pln,
        last_checked_at: row.checked_at
      },
      retailer: %{id: row.retailer_id, category: row.retailer_category}
    }
  end

  defp projection_matches?(aggregate, projection) do
    if Enum.all?(@projection_fields, fn field ->
         equal?(Map.get(aggregate, field), Map.get(projection, field))
       end), do: :ok, else: {:error, :source_evidence_mismatch}
  end

  defp equal?(a, b) when is_struct(a, Decimal) and is_struct(b, Decimal), do: Decimal.equal?(a, b)
  defp equal?(a, b), do: a == b

  defp lgs_rows(rows, calculated_at) do
    rows
    |> Enum.filter(
      &(&1.retailer_category == "lgs" and &1.stock_status == "in_stock" and
          fresh?(&1, calculated_at))
    )
    |> Enum.group_by(& &1.retailer_id)
    |> Enum.map(fn {id, values} ->
      best = cheapest(values)
      %{retailer_id: id, price_pln: best.price_pln, checked_at: best.checked_at}
    end)
    |> Enum.sort_by(& &1.retailer_id)
  end

  defp sold_out_rows(rows, calculated_at),
    do:
      Enum.filter(
        rows,
        &(&1.stock_status == "sold_out" and
            DateTime.diff(calculated_at, &1.checked_at, :second) in 0..(30 * 86_400))
      )
      |> Enum.map(
        &%{retailer_id: &1.retailer_id, price_pln: &1.price_pln, checked_at: &1.checked_at}
      )
      |> Enum.sort_by(&{&1.retailer_id, &1.checked_at})

  defp fresh?(row, at), do: DateTime.diff(at, row.checked_at, :second) in 0..(7 * 86_400)

  defp cheapest([first | rest]) do
    Enum.reduce(rest, first, &cheaper/2)
  end

  defp cheaper(candidate, best) do
    case Decimal.compare(candidate.price_pln, best.price_pln) do
      :lt -> candidate
      :gt -> best
      :eq -> if(tie_key(candidate) < tie_key(best), do: candidate, else: best)
    end
  end

  defp tie_key(row), do: {row.checked_at, row.listing_id, row.mapping_id}
end
