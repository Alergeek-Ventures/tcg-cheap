defmodule TcgCheapWeb.GuideComponents do
  @moduledoc "Shared pieces of the Polish buying-guide pages."

  use TcgCheapWeb, :html

  alias TcgCheap.Catalogue.ExternalImage
  alias TcgCheap.Sealed.{Kinds, Shops}
  alias TcgCheapWeb.Polish

  @doc "The public masthead: wordmark and the two product areas."
  attr :current, :atom, default: nil, values: [nil, :buying, :trading]
  attr :id, :string, default: "site-header"

  def site_header(assigns) do
    ~H"""
    <header id={@id} class="site-header">
      <.link id="site-wordmark" class="site-wordmark" navigate={~p"/"}>
        <.fluent_icon name={:gift_card_add} />TCG CHEAP
      </.link>
      <.site_nav current={@current} />
    </header>
    """
  end

  @doc "Navigation between the buying guide and trades."
  attr :current, :atom, default: nil, values: [nil, :buying, :trading]

  def site_nav(assigns) do
    ~H"""
    <nav id="site-nav" class="site-nav" aria-label="Główna nawigacja">
      <.link
        id="site-nav-buying"
        navigate={~p"/"}
        aria-current={if(@current == :buying, do: "page")}
      >Zakupy</.link>
      <.link
        id="site-nav-trading"
        navigate={~p"/trade"}
        aria-current={if(@current == :trading, do: "page")}
      >Wymiany</.link>
    </nav>
    """
  end

  @doc "The verdict as a labelled badge; shape and text carry the meaning, not color alone."
  attr :status, :atom, required: true
  attr :id, :string, default: nil
  attr :class, :any, default: nil

  def verdict_badge(assigns) do
    ~H"""
    <span id={@id} class={["verdict-badge", "verdict-#{@status}", @class]}>
      <span class="verdict-mark" aria-hidden="true">{verdict_mark(@status)}</span>{verdict_label(
        @status
      )}
    </span>
    """
  end

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
      <svg :if={!@url} viewBox="0 0 64 48" role="img" aria-label="Brak zdjęcia">
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
    assigns = assign(assigns, :chart, chart(assigns))

    ~H"""
    <figure id={@id} class="price-chart">
      <%= if @chart.empty? do %>
        <p id={"#{@id}-empty"} class="guide-note">
          Nie mamy jeszcze historii cen tego produktu.
        </p>
      <% else %>
        <ul class="price-chart-legend">
          <li :for={line <- @chart.lines} :if={line.points != []} class={"legend-#{line.class}"}>
            {line.label}
          </li>
          <li :if={@chart.typical_y} class="legend-typical">Typowa cena</li>
        </ul>
        <div class="price-chart-frame">
          <div class="price-chart-scale" aria-hidden="true">
            <span>{Polish.zloty(@chart.max)}</span>
            <span>{Polish.zloty(@chart.min)}</span>
          </div>
          <svg
            viewBox={"0 0 #{@chart.width} #{@chart.height}"}
            preserveAspectRatio="none"
            role="img"
            aria-labelledby={"#{@id}-summary"}
          >
            <line class="price-chart-grid" x1="0" x2={@chart.width} y1="1" y2="1" />
            <line
              class="price-chart-grid"
              x1="0"
              x2={@chart.width}
              y1={@chart.height - 1}
              y2={@chart.height - 1}
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
        </div>
        <div class="price-chart-axis" aria-hidden="true">
          <span>{Polish.short_date(@from)}</span>
          <span>{Polish.short_date(@to)}</span>
        </div>
        <figcaption id={"#{@id}-summary"}>
          <span :for={line <- @chart.lines} :if={line.points != []} id={"#{@id}-summary-#{line.key}"}>
            {line.label} od {Polish.date(line.first_date)} do {Polish.date(line.last_date)}: od {Polish.price(
              line.min_price
            )} do {Polish.price(line.max_price)}.
          </span>
          <span :if={@typical}>
            Linia przerywana to typowa cena ({Polish.zloty(@typical)}).
          </span>
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

    all_prices = Enum.flat_map(series, &Enum.map(&1.points, fn {_date, price} -> price end))

    if all_prices == [] do
      %{empty?: true}
    else
      prices = all_prices ++ List.wrap(typical)
      low = prices |> Enum.min(Decimal) |> Decimal.to_float()
      high = prices |> Enum.max(Decimal) |> Decimal.to_float()
      pad = max((high - low) * 0.15, max(high * 0.02, 1.0))
      {low, high} = {max(low - pad, 0.0), high + pad}
      days = max(Date.diff(to, from), 1)

      x = fn date -> Float.round(Date.diff(date, from) / days * @width, 2) end

      y = fn price ->
        Float.round((high - Decimal.to_float(price)) / (high - low) * @height, 2)
      end

      %{
        empty?: false,
        width: @width,
        height: @height,
        min: Decimal.from_float(low),
        max: Decimal.from_float(high),
        typical_y: typical && y.(typical),
        lines: Enum.map(series, &line(&1, x, y))
      }
    end
  end

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

  @doc "The shops list and the shipping caveat shown under every buying-guide page."
  attr :id, :string, default: "guide-footnote"

  def guide_footnote(assigns) do
    assigns = assign(assigns, :shops, Enum.map(Shops.all(), & &1.name))

    ~H"""
    <footer id={@id} class="guide-footnote">
      <p>
        Ceny bez kosztów wysyłki. Sprawdzamy sklepy raz dziennie: {Enum.join(@shops, ", ")}.
        Katalog i ceny referencyjne pochodzą z Cardmarket (aktualizowane codziennie, przeliczane po kursie NBP).
        Ocena opiera się wyłącznie na cenach, po których można kupić produkt – nigdy na cenie katalogowej.
      </p>
    </footer>
    """
  end

  @doc ~S'"Booster Box · Pitch Black"'
  @spec product_meta(TcgCheap.Sealed.Product.t()) :: String.t()
  def product_meta(product) do
    [Kinds.label(product.kind), product.set_name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @spec shop_name(map()) :: String.t()
  def shop_name(%{shop: shop}), do: Shops.name(shop)

  @doc "The Polish label of a verdict."
  @spec verdict_label(atom()) :: String.t()
  def verdict_label(:good), do: "Dobra cena"
  def verdict_label(:normal), do: "Normalna cena"
  def verdict_label(:expensive), do: "Drogo"
  def verdict_label(:insufficient_data), do: "Za mało danych"
  def verdict_label(:out_of_stock), do: "Brak w sklepach"

  defp verdict_mark(:good), do: "↓"
  defp verdict_mark(:normal), do: "="
  defp verdict_mark(:expensive), do: "↑"
  defp verdict_mark(:insufficient_data), do: "?"
  defp verdict_mark(:out_of_stock), do: "–"
end
