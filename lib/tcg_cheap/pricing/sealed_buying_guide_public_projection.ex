defmodule TcgCheap.Pricing.SealedBuyingGuidePublicProjection do
  @moduledoc "Defensive public projection of sealed buying-guide snapshots."

  alias TcgCheap.Core

  alias TcgCheap.Pricing.{
    SealedBuyingModel,
    SealedDailyAggregatePublic,
    SealedDailyAggregateRevision
  }

  @factors ~w(market_benchmark market_data_limited msrp lgs sold_out trend_rising trend_stable trend_falling trend_insufficient_history availability_abundant availability_balanced availability_scarce availability_trend_improving availability_trend_stable availability_trend_tightening availability_trend_insufficient_history)

  def load(product_id, aggregate_state, aggregate, %DateTime{} = now, opts \\ []) do
    readers = readers(opts)

    case read_latest(readers.latest, product_id, now) do
      {:ok, nil} ->
        :missing

      {:ok, latest} ->
        with {:ok, source, cached_source} <-
               source_for(aggregate_state, aggregate, now, product_id),
             result <- classify_latest(latest, source, product_id, now, readers.history) do
          maybe_cached(result, cached_source, readers.ready, product_id, now, readers.history)
        else
          :invalid -> :invalid
        end

      {:error, :read_error} ->
        :read_error
    end
  rescue
    _ -> :invalid
  end

  defp readers(opts) do
    %{
      latest: Keyword.get(opts, :latest_reader, &default_latest/3),
      ready: Keyword.get(opts, :ready_reader, &default_ready/3),
      history: Keyword.get(opts, :history_reader, &default_history/5)
    }
  end

  defp source_for(:ready, aggregate, now, product_id),
    do:
      if(SealedDailyAggregatePublic.ready?(aggregate, now, sealed_product_id: product_id),
        do: {:ok, aggregate, nil},
        else: :invalid
      )

  defp source_for(:limited, aggregate, now, product_id),
    do:
      if(SealedDailyAggregatePublic.limited?(aggregate, now, sealed_product_id: product_id),
        do: {:ok, aggregate, nil},
        else: :invalid
      )

  defp source_for(:limited_cached, %{limited: limited, snapshot: cached}, now, product_id) do
    if SealedDailyAggregatePublic.limited?(limited, now, sealed_product_id: product_id) and
         SealedDailyAggregatePublic.ready?(cached, now, sealed_product_id: product_id),
       do: {:ok, limited, cached},
       else: :invalid
  end

  defp source_for(_, _, _, _), do: :invalid

  defp read_latest(reader, product_id, now) do
    case reader.(product_id, SealedBuyingModel.version(), DateTime.to_date(now)) do
      {:ok, value} -> {:ok, value}
      nil -> {:ok, nil}
      _ -> {:error, :read_error}
    end
  rescue
    _ -> {:error, :read_error}
  end

  defp classify_latest(guide, source, product_id, now, history_reader) do
    case guide_valid?(guide, source, product_id, now, history_reader) do
      {:ok, :ready} ->
        if(SealedDailyAggregatePublic.current_ready?(source, now, sealed_product_id: product_id),
          do: {:ready, guide},
          else: {:stale_ready, guide}
        )

      {:ok, :limited} ->
        {:limited, guide}

      :invalid ->
        :invalid

      {:error, :read_error} ->
        :read_error
    end
  end

  defp maybe_cached({:limited, latest}, nil, _reader, _product_id, _now, _history),
    do: {:limited, latest}

  defp maybe_cached({:limited, latest}, cached, reader, product_id, now, history) do
    case reader.(product_id, SealedBuyingModel.version(), DateTime.to_date(now)) do
      {:ok, nil} ->
        {:limited, latest}

      {:ok, ready} ->
        if guide_valid?(ready, cached, product_id, now, history) == {:ok, :ready},
          do: {:cached_ready, %{latest: latest, cached: ready}},
          else: {:limited, latest}

      _ ->
        :read_error
    end
  rescue
    _ -> :read_error
  end

  defp maybe_cached(result, _cached, _reader, _product_id, _now, _history), do: result

  defp guide_valid?(guide, source, product_id, now, history_reader)
       when is_map(guide) and is_map(source) do
    with true <- guide.sealed_product_id == product_id and source.sealed_product_id == product_id,
         true <- guide.model_version == SealedBuyingModel.version() and guide.currency == "PLN",
         true <-
           guide.guide_date == source.aggregate_date and guide.source_aggregate_id == source.id,
         true <- guide.source_aggregate_calculated_at == source.calculated_at,
         true <- valid_times?(guide, source, now),
         {:ok, history} <- read_history(history_reader, source),
         {:ok, fingerprint} <- SealedDailyAggregateRevision.fingerprint(source),
         {:ok, history_fingerprint} <- SealedDailyAggregateRevision.history_fingerprint(history),
         true <-
           guide.source_aggregate_fingerprint == fingerprint and
             guide.source_history_fingerprint == history_fingerprint,
         true <- valid_common?(guide),
         kind when kind in [:ready, :limited] <- valid_status_values(guide) do
      {:ok, kind}
    else
      {:error, :read_error} -> {:error, :read_error}
      _ -> :invalid
    end
  rescue
    _ -> :invalid
  end

  defp guide_valid?(_, _, _, _, _), do: :invalid

  defp read_history(reader, source) do
    case reader.(
           source.sealed_product_id,
           source.calculation_version,
           Date.add(source.aggregate_date, -30),
           Date.add(source.aggregate_date, -1),
           []
         ) do
      {:ok, history} when is_list(history) -> {:ok, history}
      {:ok, _} -> :invalid
      _ -> {:error, :read_error}
    end
  rescue
    _ -> {:error, :read_error}
  end

  defp valid_common?(guide) do
    valid_confidence?(guide.confidence) and valid_centers?(guide) and
      valid_factors?(guide.explanation_factors) and valid_trend?(guide) and
      guide.availability in ~w(abundant balanced scarce) and
      guide.availability_trend in ~w(improving stable tightening insufficient_history)
  end

  defp valid_status_values(%{status: "ready"} = guide) do
    if guide.limited_reason == nil and
         finite_positive_ordered?(guide, [
           :great_price_max_pln,
           :fair_price_max_pln,
           :expensive_price_max_pln
         ]) and finite_positive?(guide.reference_price_pln), do: :ready, else: :invalid
  end

  defp valid_status_values(%{status: "limited"} = guide) do
    if guide.limited_reason in Enum.map(SealedBuyingModel.limited_reasons(), &Atom.to_string/1) and
         Enum.all?(
           [guide.great_price_max_pln, guide.fair_price_max_pln, guide.expensive_price_max_pln],
           &is_nil/1
         ) and (is_nil(guide.reference_price_pln) or finite_positive?(guide.reference_price_pln)),
       do: :limited,
       else: :invalid
  end

  defp valid_status_values(_), do: :invalid

  defp valid_times?(guide, source, now),
    do:
      match?(%DateTime{}, source.calculated_at) and match?(%DateTime{}, guide.calculated_at) and
        DateTime.compare(source.calculated_at, guide.calculated_at) != :gt and
        DateTime.compare(guide.calculated_at, now) != :gt and
        Date.compare(guide.guide_date, DateTime.to_date(source.calculated_at)) != :gt

  defp valid_confidence?(%Decimal{} = v),
    do:
      not Decimal.nan?(v) and not Decimal.inf?(v) and Decimal.compare(v, Decimal.new(0)) != :lt and
        Decimal.compare(v, Decimal.new(1)) != :gt

  defp valid_confidence?(_), do: false

  defp finite_positive?(%Decimal{} = v),
    do: not Decimal.nan?(v) and not Decimal.inf?(v) and Decimal.compare(v, Decimal.new(0)) == :gt

  defp finite_positive?(_), do: false

  defp finite_positive_ordered?(map, fields),
    do:
      Enum.all?(fields, &finite_positive?(Map.get(map, &1))) and
        Enum.chunk_every(Enum.map(fields, &Map.get(map, &1)), 2, 1, :discard)
        |> Enum.all?(fn [a, b] -> Decimal.compare(a, b) == :lt end)

  defp valid_centers?(guide),
    do:
      Enum.all?(
        [:regular_benchmark_pln, :msrp_pln, :lgs_median_pln, :sold_out_center_pln],
        &(is_nil(Map.get(guide, &1)) or finite_positive?(Map.get(guide, &1)))
      )

  defp valid_factors?(factors),
    do:
      is_list(factors) and length(factors) in 1..8 and
        length(factors) == length(Enum.uniq(factors)) and Enum.all?(factors, &(&1 in @factors))

  defp valid_trend?(%{trend: "insufficient_history", trend_change: nil}), do: true

  defp valid_trend?(%{trend: trend, trend_change: change})
       when trend in ~w(rising stable falling),
       do: finite_number?(change) and Decimal.compare(change, Decimal.new("-1")) == :gt

  defp valid_trend?(_), do: false
  defp finite_number?(%Decimal{} = v), do: not Decimal.nan?(v) and not Decimal.inf?(v)
  defp finite_number?(_), do: false

  defp default_latest(product_id, version, date),
    do: Core.get_latest_sealed_buying_guide_snapshot(product_id, version, date)

  defp default_ready(product_id, version, date),
    do: Core.get_latest_ready_sealed_buying_guide_snapshot(product_id, version, date)

  defp default_history(product_id, version, since, through, _opts),
    do: Core.list_sealed_daily_aggregate_history(product_id, version, since, through)
end
