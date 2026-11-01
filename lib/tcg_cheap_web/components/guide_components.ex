defmodule TcgCheapWeb.GuideComponents do
  @moduledoc "Shared pieces of the Polish buying-guide pages."

  use TcgCheapWeb, :html

  alias TcgCheap.Catalogue.ExternalImage
  alias TcgCheap.Sealed.{Kinds, Regions, Shops}
  alias TcgCheapWeb.Polish

  @doc "The public masthead: the wordmark, linking to the buying guide, and optional controls."
  attr :id, :string, default: "site-header"
  slot :inner_block

  def site_header(assigns) do
    ~H"""
    <header id={@id} class="site-header">
      <.link id="site-wordmark" class="site-wordmark" navigate={~p"/"}>
        <img src={~p"/images/tcg-cheap.webp"} alt="TCG Cheap" width="135" height="32" />
      </.link>
      {render_slot(@inner_block)}
    </header>
    """
  end

  @doc "The verdict as a labelled badge; shape and text carry the meaning, not color alone."
  attr :verdict, :map, required: true
  attr :id, :string, default: nil
  attr :class, :any, default: nil

  def verdict_badge(assigns) do
    ~H"""
    <span id={@id} class={["verdict-badge", "verdict-#{@verdict.status}", @class]}>
      <.verdict_icon :if={@verdict.status != :cardmarket} status={@verdict.status} />{verdict_label(
        @verdict
      )}
    </span>
    """
  end

  @doc "The drawn mark of a verdict: down for good, equals for normal, up for expensive."
  attr :status, :atom, required: true

  def verdict_icon(assigns) do
    assigns = assign(assigns, :paths, verdict_paths(assigns.status))

    ~H"""
    <svg class="verdict-mark" viewBox="0 0 16 16" aria-hidden="true" focusable="false">
      <path :for={d <- @paths} d={d} />
    </svg>
    """
  end

  defp verdict_paths(:good), do: ["M8 2.5v11", "M3.5 9 8 13.5 12.5 9"]
  defp verdict_paths(:normal), do: ["M3 5.75h10", "M3 10.25h10"]
  defp verdict_paths(:expensive), do: ["M8 13.5v-11", "M3.5 7 8 2.5 12.5 7"]

  defp verdict_paths(:insufficient_data),
    do: ["M5.75 5.75a2.25 2.25 0 1 1 3.4 1.95c-.7.4-1.15.9-1.15 1.7v.6", "M8 12.75v.25"]

  defp verdict_paths(:out_of_stock), do: ["M3 8h10"]

  @doc "Product packaging image (from a matched shop offer), or a placeholder drawn for its kind."
  attr :url, :string, default: nil
  attr :kind, :atom, default: nil
  attr :alt, :string, required: true
  attr :class, :any, default: nil
  attr :loading, :string, default: "lazy"

  def product_image(assigns) do
    assigns =
      assigns
      |> assign(:url, if(ExternalImage.valid?(assigns.url), do: assigns.url))
      |> assign(:shape, placeholder_shape(assigns.kind))

    ~H"""
    <div class={["product-image", !@url && "product-image-placeholder", @class]}>
      <img
        :if={@url}
        src={@url}
        alt={@alt}
        loading={@loading}
        decoding="async"
        referrerpolicy="no-referrer"
      />
      <svg :if={!@url && @alt == ""} viewBox="0 0 64 48" aria-hidden="true" focusable="false">
        <path :for={d <- @shape} d={d} />
      </svg>
      <svg :if={!@url && @alt != ""} viewBox="0 0 64 48" role="img" aria-label="Brak zdjęcia">
        <path :for={d <- @shape} d={d} />
      </svg>
    </div>
    """
  end

  # Line drawings of the packaging, so a list without photos still reads by shape.
  defp placeholder_shape(:booster),
    do: ["M24 6h16l2 4-2 4v20l2 4-2 4H24l-2-4 2-4V14l-2-4z", "M24 14h16M24 34h16"]

  defp placeholder_shape(:blister),
    do: ["M14 6h36v36H14z", "M20 14h10v22H20zM34 14h10v22H34z", "M28 9h8"]

  defp placeholder_shape(:tin),
    do: ["M16 12c0-4 32-4 32 0v24c0 4-32 4-32 0z", "M16 12c0 4 32 4 32 0"]

  defp placeholder_shape(:deck), do: ["M18 8h24v32H18z", "M22 12h16v24H22z"]

  defp placeholder_shape(:card_set),
    do: ["M14 10h20v28H14z", "M22 8h20v28H22z", "M30 6h20v28H30z"]

  defp placeholder_shape(:case), do: ["M8 12h48v28H8z", "M8 20h48M24 12v28M40 12v28"]
  defp placeholder_shape(:booster_box), do: ["M10 16h44v24H10z", "M10 16l6-8h44l-6 8M54 40l6-8V8"]
  defp placeholder_shape(_kind), do: ["M8 10h48v30H8z", "M8 18h48M24 10v8M40 10v8"]

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
            Nie mamy jeszcze historii cen tego produktu.
          </p>
        <% @chart.few_days -> %>
          <p id={"#{@id}-few-days"} class="guide-note">
            Mamy ceny z {Polish.plural(elem(@chart.few_days, 0), "dnia", "dni", "dni")} (od {Polish.date(
              elem(@chart.few_days, 1)
            )}). Wykres pokażemy, gdy będzie ich co najmniej {@min_days}.
          </p>
        <% true -> %>
          <ul class="price-chart-legend" aria-hidden="true">
            <li :for={line <- @chart.lines} :if={line.points != []} class={"legend-#{line.class}"}>
              {line.label}
            </li>
            <li :if={@chart.typical_y} class="legend-typical">Typowa cena</li>
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
                typowa {Polish.zloty(@typical)}
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
              {line.label}: {Polish.price(line.min_price)}–{Polish.price(line.max_price)} ({Polish.short_date(
                line.first_date
              )} – {Polish.short_date(line.last_date)}).
            </span>
            <span :if={@typical}>Linia przerywana: typowa cena {Polish.zloty(@typical)}.</span>
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
      %{y: y_value, at: percent(y_value, @height), label: Polish.zloty(price)}
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
        label: Polish.short_date(date),
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

  @doc """
  Kind, the set where the name does not already say it, and the language
  edition unless English: "Kolekcja · Pitch Black", "Booster · Japońska".
  """
  @spec product_meta(TcgCheap.Sealed.Product.t()) :: String.t()
  def product_meta(%{set_name: set} = product) do
    set =
      if set && !String.contains?(String.downcase(product.name), String.downcase(set)), do: set

    region = if product.region != :en, do: Regions.label(product.region)

    [Kinds.label(product.kind), set, region]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @spec shop_name(map()) :: String.t()
  def shop_name(%{shop: shop}), do: Shops.name(shop)

  @doc "The shop's logo chip, when it has a logo."
  attr :shop, :string, required: true

  def shop_logo(assigns) do
    ~H"""
    <img
      :if={Shops.logo?(@shop)}
      src={~p"/images/shops/#{@shop <> ".webp"}"}
      alt=""
      width="96"
      height="32"
      loading="lazy"
      class="shop-logo"
    />
    """
  end

  @doc ~S'The Polish label of a verdict: "Dobra cena", "+14% vs Cardmarket", …'
  @spec verdict_label(map()) :: String.t()
  def verdict_label(%{status: :cardmarket, cheapest: %{price: price}, typical: typical}) do
    percent =
      price
      |> Decimal.sub(typical)
      |> Decimal.div(typical)
      |> Decimal.mult(100)
      |> Decimal.round(0)
      |> Decimal.to_integer()

    sign =
      cond do
        percent > 0 -> "+"
        percent < 0 -> "−"
        true -> "±"
      end

    "#{sign}#{abs(percent)}% vs Cardmarket"
  end

  def verdict_label(%{status: :good}), do: "Dobra cena"
  def verdict_label(%{status: :normal}), do: "Normalna cena"
  def verdict_label(%{status: :expensive}), do: "Drogo"
  def verdict_label(%{status: :insufficient_data}), do: "Za mało danych"
  def verdict_label(%{status: :out_of_stock}), do: "Brak w sklepach"
end
