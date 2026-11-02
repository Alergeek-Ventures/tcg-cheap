defmodule TcgCheapWeb.GuideComponents do
  @moduledoc "Shared pieces of the public buying-guide pages."

  use TcgCheapWeb, :html
  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.{Kinds, Regions, Shops}
  alias TcgCheapWeb.Polish

  @doc "The public masthead: the wordmark, linking to the buying guide, and optional controls."
  attr :id, :string, default: "site-header"
  attr :locale, :string, default: nil
  attr :return_to, :string, default: "/"
  slot :inner_block

  def site_header(assigns) do
    ~H"""
    <header id={@id} class="site-header">
      <.link id="site-wordmark" class="site-wordmark" navigate={~p"/"}>
        <img src={~p"/images/tcg-cheap.webp"} alt="TCG Cheap" width="135" height="32" />
      </.link>
      <nav
        :if={@locale}
        id="guide-language"
        class="guide-language"
        aria-label={gettext("Język strony")}
      >
        <a
          :for={{locale, name, flag} <- languages()}
          id={"language-#{locale}"}
          href={~p"/lang/#{locale}?#{[return_to: @return_to]}"}
          lang={locale}
          hreflang={locale}
          aria-label={"#{String.upcase(locale)} – #{name}"}
          aria-current={if(locale == @locale, do: "true")}
          data-track="language_changed"
          data-track-to={locale}
        >
          <img src={flag} alt="" width="21" height="14" />{String.upcase(locale)}
        </a>
      </nav>
      {render_slot(@inner_block)}
    </header>
    """
  end

  @doc "The public footer: who built the guide."
  def site_footer(assigns) do
    ~H"""
    <footer id="site-footer" class="site-footer">
      <p>
        built with
        <svg class="site-footer-ball" viewBox="0 0 16 16" role="img" aria-label="Poké Ball">
          <circle cx="8" cy="8" r="7" fill="#fff" />
          <path d="M1 8a7 7 0 0 1 14 0z" fill="#d23c2a" />
          <circle cx="8" cy="8" r="7" fill="none" stroke="currentColor" stroke-width="1.2" />
          <path d="M1 8h14" stroke="currentColor" stroke-width="1.2" />
          <circle cx="8" cy="8" r="2.4" fill="#fff" stroke="currentColor" stroke-width="1" />
        </svg>
        by <a href="https://alergeek.ventures" title="Alergeek
          Ventures">Alergeek Ventures</a>
      </p>
    </footer>
    """
  end

  @doc "The cookie notice; analytics.js shows it until the visitor closes it or rejects cookies."
  def cookie_notice(assigns) do
    ~H"""
    <aside id="cookie-notice" class="cookie-notice" aria-label={gettext("Cookies")} hidden>
      <p>{gettext("Używamy cookies do statystyk odwiedzin i formularza zgłoszeń.")}</p>
      <div class="cookie-notice-actions">
        <button id="cookie-notice-reject" type="button">{gettext("Odrzuć")}</button>
        <button id="cookie-notice-accept" type="button">{gettext("Zamknij")}</button>
      </div>
    </aside>
    """
  end

  @doc """
  The report form. analytics.js shows it and sends each report as a new
  PostHog support ticket; rejecting cookies hides it.
  """
  def report_form(assigns) do
    ~H"""
    <div
      id="report"
      class="report"
      data-sending={gettext("Wysyłam…")}
      data-sent={gettext("Dzięki! Zgłoszenie dotarło.")}
      data-failed={gettext("Nie udało się wysłać. Spróbuj jeszcze raz.")}
      hidden
    >
      <button id="report-toggle" type="button" popovertarget="report-panel">
        {gettext("Zgłoś problem")}
      </button>
      <form id="report-panel" popover aria-labelledby="report-title">
        <h2 id="report-title">{gettext("Zgłoś problem")}</h2>
        <p>{gettext("Zła cena, brakujący produkt albo coś nie działa? Napisz, sprawdzimy.")}</p>
        <label for="report-message">{gettext("Co się stało?")}</label>
        <textarea id="report-message" name="message" required autofocus></textarea>
        <label for="report-email">{gettext("E-mail, jeśli chcesz odpowiedź")}</label>
        <input id="report-email" name="email" type="email" autocomplete="email" />
        <div class="report-actions">
          <p id="report-status" role="status"></p>
          <button
            id="report-cancel"
            type="button"
            popovertarget="report-panel"
            popovertargetaction="hide"
          >
            {gettext("Anuluj")}
          </button>
          <button id="report-submit" type="submit">{gettext("Wyślij")}</button>
        </div>
      </form>
    </div>
    """
  end

  defp languages do
    [
      {"pl", "Polski", ~p"/images/flags/pl.svg"},
      {"en", "English", ~p"/images/flags/en.svg"}
    ]
  end

  @doc """
  The verdict as a labelled badge; shape and text carry the meaning, not color
  alone. Fewer than 3 shops is one state, "Za mało sklepów", whether or not
  Cardmarket has a price: Cardmarket is context on the product page, never a
  verdict next to real ones.
  """
  attr :verdict, :map, required: true
  attr :id, :string, default: nil
  attr :class, :any, default: nil

  def verdict_badge(assigns) do
    assigns = assign(assigns, :status, badge_status(assigns.verdict.status))

    ~H"""
    <span id={@id} class={["verdict-badge", "verdict-#{@status}", @class]}>
      <.verdict_icon status={@status} />{verdict_label(@verdict)}
    </span>
    """
  end

  defp badge_status(:cardmarket), do: :insufficient_data
  defp badge_status(status), do: status

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

  @doc "The SVG paths (16×16, stroked) of a verdict's drawn mark."
  @spec verdict_paths(atom()) :: [String.t()]
  def verdict_paths(:good), do: ["M8 2.5v11", "M3.5 9 8 13.5 12.5 9"]
  def verdict_paths(:normal), do: ["M3 5.75h10", "M3 10.25h10"]
  def verdict_paths(:expensive), do: ["M8 13.5v-11", "M3.5 7 8 2.5 12.5 7"]

  def verdict_paths(status) when status in [:cardmarket, :insufficient_data],
    do: ["M5.75 5.75a2.25 2.25 0 1 1 3.4 1.95c-.7.4-1.15.9-1.15 1.7v.6", "M8 12.75v.25"]

  def verdict_paths(:out_of_stock), do: ["M3 8h10"]
  # A clock: a pre-order, shipped on the premiere.
  def verdict_paths(:preorder),
    do: ["M8 2.5a5.5 5.5 0 1 1 0 11a5.5 5.5 0 1 1 0-11", "M8 5v3.25l2 1.5"]

  @doc """
  Product packaging image from our storage, else a placeholder drawn for its kind.

  With a `blur` (the photo's tiny inline preview), the preview shows blurred
  right away and the photo fades in over it once it has loaded (see the
  `data-progressive` script in the root layout).
  """
  attr :small_photo, :string, default: nil, doc: "the `small` variant (192 px), once stored"
  attr :photo, :string, default: nil
  attr :page_photo, :string, default: nil
  attr :blur, :string, default: nil
  attr :sizes, :string, default: nil
  attr :kind, :atom, default: nil
  attr :alt, :string, required: true
  attr :class, :any, default: nil
  attr :loading, :string, default: "lazy"
  attr :fetchpriority, :string, default: nil

  def product_image(assigns) do
    assigns =
      assigns
      |> assign(:url, assigns.photo)
      |> assign(:srcset, srcset(assigns))
      |> assign(:shape, placeholder_shape(assigns.kind))

    ~H"""
    <div class={["product-image", !@url && "product-image-placeholder", @class]}>
      <img :if={@url && @blur} src={@blur} alt="" aria-hidden="true" class="product-image-blur" />
      <img
        :if={@url}
        data-progressive={@blur && true}
        src={@url}
        srcset={@srcset}
        sizes={@srcset && @sizes}
        alt={@alt}
        loading={@loading}
        fetchpriority={@fetchpriority}
        decoding="async"
        referrerpolicy="no-referrer"
      />
      <svg :if={!@url && @alt == ""} viewBox="0 0 64 48" aria-hidden="true" focusable="false">
        <path :for={d <- @shape} d={d} />
      </svg>
      <svg
        :if={!@url && @alt != ""}
        viewBox="0 0 64 48"
        role="img"
        aria-label={gettext("Brak zdjęcia")}
      >
        <path :for={d <- @shape} d={d} />
      </svg>
    </div>
    """
  end

  defp srcset(%{photo: photo, page_photo: page_photo} = assigns)
       when is_binary(photo) and is_binary(page_photo) do
    [{assigns.small_photo, 192}, {photo, 352}, {page_photo, 960}]
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map_join(", ", fn {url, width} -> "#{url} #{width}w" end)
  end

  defp srcset(_assigns), do: nil

  @doc "Line drawings (64×48, stroked) of the packaging, so a product without a photo still reads by shape."
  @spec placeholder_shape(atom()) :: [String.t()]
  def placeholder_shape(:booster),
    do: ["M24 6h16l2 4-2 4v20l2 4-2 4H24l-2-4 2-4V14l-2-4z", "M24 14h16M24 34h16"]

  def placeholder_shape(:blister),
    do: ["M14 6h36v36H14z", "M20 14h10v22H20zM34 14h10v22H34z", "M28 9h8"]

  def placeholder_shape(:tin),
    do: ["M16 12c0-4 32-4 32 0v24c0 4-32 4-32 0z", "M16 12c0 4 32 4 32 0"]

  def placeholder_shape(:deck), do: ["M18 8h24v32H18z", "M22 12h16v24H22z"]

  def placeholder_shape(:card_set),
    do: ["M14 10h20v28H14z", "M22 8h20v28H22z", "M30 6h20v28H30z"]

  def placeholder_shape(:case), do: ["M8 12h48v28H8z", "M8 20h48M24 12v28M40 12v28"]
  def placeholder_shape(:booster_box), do: ["M10 16h44v24H10z", "M10 16l6-8h44l-6 8M54 40l6-8V8"]
  def placeholder_shape(_kind), do: ["M8 10h48v30H8z", "M8 18h48M24 10v8M40 10v8"]

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
              days: Polish.plural(elem(@chart.few_days, 0), "dnia", "dni", "dni"),
              date: Polish.date(elem(@chart.few_days, 1)),
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
                {gettext("zwykle %{price}", price: Polish.zloty(@typical))}
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
            <span :if={@typical}>{gettext("Linia przerywana: zwykle najtaniej %{price}.",
              price: Polish.zloty(@typical)
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

  @doc """
  A Cardmarket price in złoty behind the Cardmarket logo, the one mark for a
  Cardmarket reference price, linking to the product there.
  """
  attr :price, :any, required: true
  attr :href, :string, required: true
  attr :id, :string, default: nil
  attr :class, :any, default: nil

  def cardmarket_price(assigns) do
    ~H"""
    <a
      id={@id}
      href={@href}
      target="_blank"
      rel="noopener nofollow"
      class={["cardmarket-price", @class]}
      title={gettext("Cena na Cardmarket (bez wysyłki)")}
    >
      <img src={~p"/images/cardmarket.png"} alt="Cardmarket" width="16" height="16" />{Polish.zloty(
        @price
      )}
    </a>
    """
  end

  @doc "A product's page on Cardmarket, by its Cardmarket product id."
  @spec cardmarket_url(integer()) :: String.t()
  def cardmarket_url(id), do: "https://www.cardmarket.com/en/Pokemon/Products?idProduct=#{id}"

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

  @doc ~S'The list tag of a pre-order: "przedsprzedaż · za 4 dni", or plain without a coming premiere.'
  @spec preorder_tag(non_neg_integer() | nil) :: String.t()
  def preorder_tag(nil), do: gettext("przedsprzedaż")

  def preorder_tag(days),
    do: gettext("przedsprzedaż · %{when}", when: Polish.days_until(days))

  @doc ~S'The localized label of a verdict: "Dobra cena", "Za mało sklepów", …'
  @spec verdict_label(map()) :: String.t()
  def verdict_label(%{status: :good}), do: gettext("Dobra cena")
  def verdict_label(%{status: :normal}), do: gettext("Normalna cena")
  def verdict_label(%{status: :expensive}), do: gettext("Drogo")

  def verdict_label(%{status: status}) when status in [:cardmarket, :insufficient_data],
    do: gettext("Za mało sklepów")

  def verdict_label(%{status: :out_of_stock}), do: gettext("Brak w sklepach")
end
