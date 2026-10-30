defmodule TcgCheapWeb.GuideComponents do
  @moduledoc "Shared pieces of the Polish buying-guide pages."

  use TcgCheapWeb, :html

  alias TcgCheap.Catalogue.ExternalImage
  alias TcgCheap.Sealed.{Catalogue, Shops}
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

  @doc "Product packaging image, or an honest placeholder."
  attr :url, :string, default: nil
  attr :alt, :string, required: true
  attr :class, :any, default: nil
  attr :loading, :string, default: "lazy"

  def product_image(assigns) do
    assigns = assign(assigns, :url, if(ExternalImage.valid?(assigns.url), do: assigns.url))

    ~H"""
    <div class={["product-image", @class]}>
      <img
        :if={@url}
        src={@url}
        alt={@alt}
        loading={@loading}
        decoding="async"
        referrerpolicy="no-referrer"
      />
      <svg :if={!@url} viewBox="0 0 64 48" role="img" aria-label="Brak zdjęcia">
        <rect x="8" y="10" width="48" height="30" />
        <path d="M8 18h48M24 10v8M40 10v8" />
      </svg>
    </div>
    """
  end

  @doc "A server-rendered chart of the daily lowest price; days without stock are gaps."
  attr :id, :string, required: true
  attr :history, :list, required: true
  attr :from, Date, required: true
  attr :to, Date, required: true
  attr :typical, :any, default: nil

  def price_chart(assigns) do
    assigns = assign(assigns, :chart, chart(assigns))

    ~H"""
    <figure id={@id} class="price-chart">
      <%= if @chart.points == [] do %>
        <p id={"#{@id}-empty"} class="guide-note">
          Nie mamy jeszcze historii cen tego produktu.
        </p>
      <% else %>
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
            <polyline :for={segment <- @chart.segments} class="price-chart-line" points={segment} />
            <line
              :for={{x, y} <- @chart.singles}
              class="price-chart-dot"
              x1={x}
              x2={x}
              y1={y}
              y2={y}
            />
          </svg>
        </div>
        <div class="price-chart-axis" aria-hidden="true">
          <span>{Polish.short_date(@from)}</span>
          <span>{Polish.short_date(@to)}</span>
        </div>
        <figcaption id={"#{@id}-summary"}>
          Najniższa cena od {Polish.date(@chart.first_date)} do {Polish.date(@chart.last_date)}: od {Polish.price(
            @chart.min_price
          )} do {Polish.price(@chart.max_price)}.
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

  defp chart(%{history: history, from: from, to: to, typical: typical}) do
    points =
      for %{date: date, lowest_price: %Decimal{} = price} <- history,
          Date.compare(date, from) != :lt and Date.compare(date, to) != :gt,
          do: {date, price}

    case points do
      [] ->
        %{points: []}

      _ ->
        prices = Enum.map(points, &elem(&1, 1)) ++ List.wrap(typical)
        min_price = points |> Enum.map(&elem(&1, 1)) |> Enum.min(Decimal)
        max_price = points |> Enum.map(&elem(&1, 1)) |> Enum.max(Decimal)
        low = prices |> Enum.min(Decimal) |> Decimal.to_float()
        high = prices |> Enum.max(Decimal) |> Decimal.to_float()
        pad = max((high - low) * 0.15, max(high * 0.02, 1.0))
        {low, high} = {max(low - pad, 0.0), high + pad}
        days = max(Date.diff(to, from), 1)

        x = fn date -> Float.round(Date.diff(date, from) / days * @width, 2) end

        y = fn price ->
          Float.round((high - Decimal.to_float(price)) / (high - low) * @height, 2)
        end

        coordinates = Enum.map(points, fn {date, price} -> {date, x.(date), y.(price)} end)
        runs = consecutive_runs(coordinates)

        %{
          points: points,
          width: @width,
          height: @height,
          min: Decimal.from_float(low),
          max: Decimal.from_float(high),
          min_price: min_price,
          max_price: max_price,
          first_date: points |> List.first() |> elem(0),
          last_date: points |> List.last() |> elem(0),
          typical_y: typical && y.(typical),
          segments:
            for(
              run <- runs,
              length(run) > 1,
              do: Enum.map_join(run, " ", &"#{elem(&1, 1)},#{elem(&1, 2)}")
            ),
          singles: for([{_d, px, py}] <- runs, do: {px, py})
        }
    end
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
        Ocena opiera się wyłącznie na cenach, po których można dziś kupić produkt – nie na cenie katalogowej.
      </p>
    </footer>
    """
  end

  @doc ~S'"Booster Box · Pitch Black"'
  @spec product_meta(TcgCheap.Sealed.Product.t()) :: String.t()
  def product_meta(product) do
    [Catalogue.kind_label(product.kind), product.set_name]
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
