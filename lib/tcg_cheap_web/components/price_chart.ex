defmodule TcgCheapWeb.PriceChart do
  @moduledoc "The server-rendered chart of a product's daily prices."

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheapWeb.Format

  # Fewer days than this would draw a line or two at the edge of an empty frame.
  @min_chart_days 7

  @doc """
  A server-rendered chart of daily prices in PLN; days without a value are
  gaps. Each series is `%{key, label, class, points: [{date, price}]}`.
  """
  attr :id, :string, required: true
  attr :series, :list, required: true
  attr :from, Date, required: true
  attr :to, Date, required: true
  attr :typical, :any, default: nil

  def price_chart(assigns) do
    assigns = assigns |> assign(:chart, chart(assigns)) |> assign(:min_days, @min_chart_days)

    ~H"""
    <figure id={@id} class="price-chart">
      <%= cond do %>
        <% @chart.empty? -> %>
          <p id={"#{@id}-empty"} class="guide-note">
            {gettext("Nie mamy jeszcze historii cen tego produktu.")}
          </p>
        <% @chart.few_days -> %>
          <p id={"#{@id}-few-days"} class="guide-note">
            {gettext(
              "Mamy ceny z %{days} (od %{date}). Wykres pokażemy, gdy będzie ich co najmniej %{minimum}.",
              days: Format.days(elem(@chart.few_days, 0)),
              date: Format.date(elem(@chart.few_days, 1)),
              minimum: @min_days
            )}
          </p>
        <% true -> %>
          <ul class="price-chart-legend" aria-hidden="true">
            <li :for={line <- @chart.lines} :if={line.points != []} class={"legend-#{line.class}"}>
              {line.label}
            </li>
            <li :if={@chart.typical_y} class="legend-typical">{gettext("Zwykle najtaniej")}</li>
          </ul>
          <div class="price-chart-frame">
            <div class="price-chart-scale" aria-hidden="true">
              <span :for={tick <- @chart.y_ticks} style={"--at: #{tick.at}%"}>{tick.label}</span>
            </div>
            <div class="price-chart-plot">
              <svg
                viewBox={"0 0 #{@chart.width} #{@chart.height}"}
                preserveAspectRatio="none"
                role="img"
                aria-labelledby={"#{@id}-summary"}
              >
                <line
                  :for={tick <- @chart.y_ticks}
                  class="price-chart-grid"
                  x1="0"
                  x2={@chart.width}
                  y1={tick.y}
                  y2={tick.y}
                />
                <line
                  :for={tick <- @chart.x_ticks}
                  class="price-chart-grid price-chart-grid-month"
                  x1={tick.x}
                  x2={tick.x}
                  y1="0"
                  y2={@chart.height}
                />
                <line
                  :if={@chart.typical_y}
                  class="price-chart-typical"
                  x1="0"
                  x2={@chart.width}
                  y1={@chart.typical_y}
                  y2={@chart.typical_y}
                />
                <%= for line <- @chart.lines do %>
                  <polyline
                    :for={segment <- line.segments}
                    class={["price-chart-line", "price-chart-#{line.class}"]}
                    points={segment}
                  />
                  <line
                    :for={{x, y} <- line.singles}
                    class={["price-chart-dot", "price-chart-#{line.class}"]}
                    x1={x}
                    x2={x}
                    y1={y}
                    y2={y}
                  />
                <% end %>
              </svg>
              <span
                :if={@chart.typical_y}
                class="price-chart-typical-label"
                style={"--at: #{@chart.typical_at}%"}
                aria-hidden="true"
              >
                {gettext("zwykle %{price}", price: Format.limit_price(@typical))}
              </span>
            </div>
            <div class="price-chart-axis" aria-hidden="true">
              <span :for={tick <- @chart.x_ticks} class={tick.edge} style={"--at: #{tick.at}%"}>
                {tick.label}
              </span>
            </div>
          </div>
          <figcaption id={"#{@id}-summary"} class="sr-only">
            <span
              :for={line <- @chart.lines}
              :if={line.points != []}
              id={"#{@id}-summary-#{line.key}"}
            >
              {line.label}: {Format.price(line.min_price)}–{Format.price(line.max_price)} ({Format.short_date(
                line.first_date
              )} – {Format.short_date(line.last_date)}).
            </span>
            <span :if={@typical}>{gettext("Linia przerywana: zwykle najtaniej %{price}.",
              price: Format.limit_price(@typical)
            )}</span>
          </figcaption>
      <% end %>
    </figure>
    """
  end

  @width 600
  @height 200

  defp chart(%{series: series, from: from, to: to, typical: typical}) do
    series =
      Enum.map(series, fn line ->
        points =
          for {date, %Decimal{} = price} <- line.points,
              Date.compare(date, from) != :lt and Date.compare(date, to) != :gt,
              do: {date, price}

        Map.put(line, :points, points)
      end)

    points = Enum.flat_map(series, & &1.points)
    all_prices = Enum.map(points, &elem(&1, 1))
    dates = points |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    cond do
      all_prices == [] ->
        %{empty?: true, few_days: nil}

      length(dates) < @min_chart_days ->
        %{empty?: false, few_days: {length(dates), Enum.min(dates, Date)}}

      true ->
        plot(series, all_prices, from, to, typical)
    end
  end

  defp plot(series, all_prices, from, to, typical) do
    {low, high, step} = price_scale(all_prices ++ List.wrap(typical))
    days = max(Date.diff(to, from), 1)

    x = fn date -> Float.round(Date.diff(date, from) / days * @width, 2) end
    y = fn price -> Float.round((high - to_float(price)) / (high - low) * @height, 2) end

    %{
      empty?: false,
      few_days: nil,
      width: @width,
      height: @height,
      y_ticks: y_ticks(low, high, step, y),
      x_ticks: x_ticks(from, to, x),
      typical_y: typical && y.(typical),
      typical_at: typical && percent(y.(typical), @height),
      lines: Enum.map(series, &line(&1, x, y))
    }
  end

  # A round złoty scale with three to five gridlines that contains every price.
  defp price_scale(prices) do
    low = prices |> Enum.min(Decimal) |> Decimal.to_float()
    high = prices |> Enum.max(Decimal) |> Decimal.to_float()
    span = max(high - low, max(high * 0.1, 4.0))
    step = nice_step(span / 3)
    low = max(Float.floor(low / step) * step, 0.0)
    high = Float.ceil(high / step) * step
    high = if high - low < step * 2, do: low + step * 2, else: high

    {low, high, step}
  end

  defp nice_step(raw) do
    magnitude = :math.pow(10, Float.floor(:math.log10(raw)))
    step = Enum.find([1, 2, 5, 10], &(&1 * magnitude >= raw)) * magnitude
    max(step, 1.0)
  end

  defp y_ticks(low, high, step, y) do
    count = round((high - low) / step)

    for index <- 0..count do
      price = Decimal.from_float(low + index * step)
      y_value = y.(price)
      %{y: y_value, at: percent(y_value, @height), label: Format.whole_price(price)}
    end
  end

  # The first day of each month inside the window.
  defp x_ticks(from, to, x) do
    from
    |> Date.add(1)
    |> Date.range(to)
    |> Enum.filter(&(&1.day == 1))
    |> Enum.map(fn date ->
      x_value = x.(date)
      at = percent(x_value, @width)

      %{
        x: x_value,
        at: at,
        label: Format.short_date(date),
        edge: edge_class(at)
      }
    end)
  end

  # Labels near either end are aligned inwards so they never stick out of the chart.
  defp edge_class(at) when at < 8, do: "edge-start"
  defp edge_class(at) when at > 92, do: "edge-end"
  defp edge_class(_at), do: nil

  defp percent(value, total), do: Float.round(value / total * 100, 2)

  defp to_float(%Decimal{} = price), do: Decimal.to_float(price)

  defp line(%{points: []} = line, _x, _y), do: Map.merge(line, %{segments: [], singles: []})

  defp line(%{points: points} = line, x, y) do
    runs =
      points
      |> Enum.map(fn {date, price} -> {date, x.(date), y.(price)} end)
      |> consecutive_runs()

    prices = Enum.map(points, &elem(&1, 1))

    Map.merge(line, %{
      min_price: Enum.min(prices, Decimal),
      max_price: Enum.max(prices, Decimal),
      first_date: points |> List.first() |> elem(0),
      last_date: points |> List.last() |> elem(0),
      segments:
        for(
          run <- runs,
          length(run) > 1,
          do: Enum.map_join(run, " ", &"#{elem(&1, 1)},#{elem(&1, 2)}")
        ),
      singles: for([{_d, px, py}] <- runs, do: {px, py})
    })
  end

  # Splits points into runs of consecutive days, so missing days become gaps.
  defp consecutive_runs(coordinates) do
    coordinates
    |> Enum.chunk_while(
      [],
      fn
        point, [] ->
          {:cont, [point]}

        {date, _, _} = point, [{previous, _, _} | _] = run ->
          if Date.diff(date, previous) == 1,
            do: {:cont, [point | run]},
            else: {:cont, Enum.reverse(run), [point]}
      end,
      fn
        [] -> {:cont, []}
        run -> {:cont, Enum.reverse(run), []}
      end
    )
  end
end
