defmodule TcgCheap.Pricing.SealedMarketHistory do
  @moduledoc "Pure preparation of a thirty-day sealed-market history plot."

  @days 30
  @plot_height Decimal.new(100)
  @plot_padding 10

  alias TcgCheap.Pricing.SealedDailyAggregatePublic

  @spec build(list(), Ecto.UUID.t(), DateTime.t()) :: map()
  def build(snapshots, expected_product_id, %DateTime{} = now)
      when is_list(snapshots) and is_binary(expected_product_id) do
    if valid_product_id?(expected_product_id) do
      build_valid(snapshots, expected_product_id, now)
    else
      empty(DateTime.to_date(DateTime.shift_zone!(now, "Etc/UTC")))
    end
  end

  def build(_snapshots, _expected_product_id, %DateTime{} = now),
    do: empty(DateTime.to_date(DateTime.shift_zone!(now, "Etc/UTC")))

  defp build_valid(snapshots, expected_product_id, now) do
    today = DateTime.to_date(DateTime.shift_zone!(now, "Etc/UTC"))
    origin = Date.add(today, -(@days - 1))

    points =
      snapshots
      |> Enum.flat_map(&valid_point(&1, expected_product_id, origin, today, now))
      |> Enum.group_by(& &1.date)
      |> Map.values()
      |> Enum.map(&latest/1)
      |> Enum.map(&Map.delete(&1, :id))
      |> Enum.sort_by(& &1.date, Date)

    plot_points = plot_points(points, origin)
    chunks = contiguous_chunks(plot_points)

    %{
      origin: origin,
      points: points,
      benchmark_paths: Enum.map(chunks, &line_path(&1, :benchmark_y)),
      range_paths: Enum.map(chunks, &range_path/1),
      plot_points: plot_points
    }
  end

  defp valid_product_id?(product_id), do: match?({:ok, _}, Ecto.UUID.cast(product_id))

  defp empty(today) do
    %{
      origin: Date.add(today, -(@days - 1)),
      points: [],
      benchmark_paths: [],
      range_paths: [],
      plot_points: []
    }
  end

  defp valid_point(snapshot, expected_product_id, origin, today, now) when is_map(snapshot) do
    date = Map.get(snapshot, :aggregate_date)

    with true <-
           SealedDailyAggregatePublic.ready?(snapshot, now,
             sealed_product_id: expected_product_id
           ),
         true <-
           match?(%Date{}, date) and Date.compare(date, origin) != :lt and
             Date.compare(date, today) != :gt do
      [
        %{
          date: date,
          benchmark_pln: Map.fetch!(snapshot, :benchmark_pln),
          typical_low_pln: Map.fetch!(snapshot, :typical_low_pln),
          typical_high_pln: Map.fetch!(snapshot, :typical_high_pln),
          calculated_at: Map.fetch!(snapshot, :calculated_at),
          id: Map.get(snapshot, :id)
        }
      ]
    else
      _ -> []
    end
  rescue
    _ -> []
  end

  defp valid_point(_, _, _, _, _), do: []

  defp latest([first | rest]), do: Enum.reduce(rest, first, &newer/2)

  defp newer(candidate, current) do
    case DateTime.compare(candidate.calculated_at, current.calculated_at) do
      :gt -> candidate
      :lt -> current
      :eq -> if id_compare(candidate.id, current.id) == :gt, do: candidate, else: current
    end
  end

  defp id_compare(nil, nil), do: :eq
  defp id_compare(nil, _), do: :lt
  defp id_compare(_, nil), do: :gt

  defp id_compare(left, right) do
    cond do
      left < right -> :lt
      left > right -> :gt
      true -> :eq
    end
  end

  defp plot_points([], _origin), do: []

  defp plot_points(points, origin) do
    {min, max} = extent(points)

    Enum.map(points, fn point ->
      %{
        date: point.date,
        x: Date.diff(point.date, origin) * 10 + 5,
        benchmark_y: y_for(point.benchmark_pln, min, max),
        low_y: y_for(point.typical_low_pln, min, max),
        high_y: y_for(point.typical_high_pln, min, max)
      }
    end)
  end

  defp extent(points) do
    Enum.reduce(points, {hd(points).typical_low_pln, hd(points).typical_high_pln}, fn point,
                                                                                      {min, max} ->
      min =
        if Decimal.compare(point.typical_low_pln, min) == :lt,
          do: point.typical_low_pln,
          else: min

      max =
        if Decimal.compare(point.typical_high_pln, max) == :gt,
          do: point.typical_high_pln,
          else: max

      {min, max}
    end)
  end

  defp y_for(value, min, max) do
    case Decimal.compare(min, max) do
      :eq ->
        60

      _ ->
        Decimal.sub(max, value)
        |> Decimal.mult(@plot_height)
        |> Decimal.div(Decimal.sub(max, min))
        |> Decimal.add(Decimal.new(@plot_padding))
        |> Decimal.round(0)
        |> Decimal.to_integer()
    end
  end

  defp contiguous_chunks(points), do: Enum.chunk_while(points, [], &chunk/2, &finish_chunk/1)

  defp chunk(point, []), do: {:cont, [point]}

  defp chunk(point, [last | _] = acc),
    do:
      if(Date.diff(point.date, last.date) == 1,
        do: {:cont, [point | acc]},
        else: {:cont, Enum.reverse(acc), [point]}
      )

  defp finish_chunk([]), do: {:cont, []}
  defp finish_chunk(acc), do: {:cont, Enum.reverse(acc), []}

  defp line_path(points, key),
    do:
      Enum.with_index(points)
      |> Enum.map_join(" ", fn {point, index} ->
        "#{if(index == 0, do: "M", else: "L")} #{point.x},#{Map.fetch!(point, key)}"
      end)

  defp range_path(points) do
    highs = Enum.map_join(points, " ", &"#{&1.x},#{&1.high_y}")
    lows = points |> Enum.reverse() |> Enum.map_join(" ", &"#{&1.x},#{&1.low_y}")
    "M #{highs} L #{lows} Z"
  end
end
