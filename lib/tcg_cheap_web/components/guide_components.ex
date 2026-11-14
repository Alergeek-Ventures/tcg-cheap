defmodule TcgCheapWeb.GuideComponents do
  @moduledoc "Shared pieces of the public buying-guide pages."

  use TcgCheapWeb, :html

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.{CardGuide, Kinds, Market, Regions, RetailDeal, Shops}
  alias TcgCheapWeb.{Paths, Polish, Region, SEO, VisitorLocation}

  def card_variant_label(:normal), do: gettext("Zwykła / holo")
  def card_variant_label(:reverse), do: gettext("Reverse holo")
  def card_variant_label(:special), do: gettext("Wzór specjalny")

  def single_verdict_status(:cheaper), do: :good
  def single_verdict_status(:expensive), do: :expensive
  def single_verdict_status(v) when v in [:similar, :pennies], do: :normal
  def single_verdict_status(:unavailable), do: :out_of_stock
  def single_verdict_status(_), do: :insufficient_data

  # The same short words as a sealed product's verdict; how the price was
  # judged is told under "Jak liczymy?".
  def single_verdict_label(:unknown), do: gettext("Brak ceny Cardmarket")

  def single_verdict_label(verdict),
    do: verdict_label(%{status: single_verdict_status(verdict)})

  @doc """
  The public masthead: the wordmark, linking to the region's guide, the
  region and language control and optional controls; under it, the region
  hint (`TcgCheapWeb.Locale`) when there is one.
  """
  attr :id, :string, default: "site-header"
  attr :region, Region, default: nil
  attr :locale, :string, default: nil
  attr :current_path, :string, default: "/"
  attr :region_hint, :string, default: nil
  slot :inner_block

  def site_header(assigns) do
    ~H"""
    <header id={@id} class="site-header">
      <.link id="site-wordmark" class="site-wordmark" navigate={Paths.home()}>
        <img src={~p"/images/tcg-cheap.webp"} alt="TCG Cheap" width="135" height="32" />
      </.link>
      <.locale_control
        :if={@region && @locale}
        region={@region}
        locale={@locale}
        current_path={@current_path}
      />
      {render_slot(@inner_block)}
    </header>
    <.region_hint
      :if={@region && @region_hint}
      region={@region}
      suggested={Region.fetch!(@region_hint)}
      current_path={@current_path}
    />
    """
  end

  attr :region, Region, required: true
  attr :locale, :string, required: true
  attr :current_path, :string, required: true

  # The region (which shops, prices and delivery) and the language (only the
  # text) are chosen apart. Each option is a link, so both work without
  # JavaScript; preferences.js also keeps the language in localStorage.
  defp locale_control(assigns) do
    ~H"""
    <details
      id="guide-locale"
      class="guide-locale"
      phx-mounted={JS.ignore_attributes(["open"])}
    >
      <summary
        id="guide-locale-summary"
        class="guide-locale-summary"
        aria-label={
          gettext("Kraj i język: %{region}, %{language}",
            region: country_name(@region.code),
            language: language_name(@locale)
          )
        }
      >
        <img src={flag(@region.code)} alt="" width="21" height="14" />{String.upcase(@locale)}
      </summary>
      <div class="guide-locale-panel">
        <nav id="guide-region" aria-labelledby="guide-region-title">
          <h2 id="guide-region-title">{gettext("Kraj")}</h2>
          <p class="guide-note">{gettext("Sklepy, ceny i dostawa")}</p>
          <ul>
            <li :for={region <- Region.all()}>
              <a
                id={"region-#{region.code}"}
                href={~p"/region/#{region.code}?#{[path: @current_path]}"}
                rel="nofollow"
                aria-current={if(region.code == @region.code, do: "true")}
                data-track="region_changed"
                data-track-to={region.code}
              >
                <img src={flag(region.code)} alt="" width="21" height="14" />
                <span class="guide-locale-name">
                  {country_name(region.code)}
                  <span class="guide-locale-currency">
                    · {Polish.currency_symbol(region.market.currency)}
                  </span>
                </span>
                <.fluent_icon
                  :if={region.code == @region.code}
                  name={:checkmark_circle}
                  class="guide-locale-check"
                />
              </a>
            </li>
          </ul>
        </nav>
        <nav id="guide-language" aria-labelledby="guide-language-title">
          <h2 id="guide-language-title">{gettext("Język strony")}</h2>
          <ul>
            <li :for={language <- Region.languages()}>
              <a
                id={"language-#{language}"}
                href={~p"/lang/#{language}?#{[return_to: @current_path]}"}
                rel="nofollow"
                lang={language}
                hreflang={language}
                aria-current={if(language == @locale, do: "true")}
                data-language={language}
                data-track="language_changed"
                data-track-to={language}
              >
                <span class="guide-locale-name">{language_name(language)}</span>
                <.fluent_icon
                  :if={language == @locale}
                  name={:checkmark_circle}
                  class="guide-locale-check"
                />
              </a>
            </li>
          </ul>
        </nav>
      </div>
    </details>
    """
  end

  attr :region, Region, required: true
  attr :suggested, Region, required: true
  attr :current_path, :string, required: true

  # In the suggested region's language: the visitor may not read this one.
  # Staying chooses the current region, which ends the hint.
  defp region_hint(assigns) do
    assigns =
      Gettext.with_locale(TcgCheapWeb.Gettext, assigns.suggested.language, fn ->
        assign(assigns,
          text: region_hint_text(assigns.suggested.code),
          switch: region_hint_switch(assigns.suggested.code),
          stay: gettext("Zostań tutaj"),
          country: country_name(assigns.suggested.code)
        )
      end)

    ~H"""
    <aside
      id="region-hint"
      class="region-hint"
      lang={@suggested.language}
      aria-label={@country}
    >
      <p>
        <img src={flag(@suggested.code)} alt="" width="21" height="14" />{@text}
      </p>
      <a
        id="region-hint-switch"
        class="region-hint-switch"
        href={~p"/region/#{@suggested.code}?#{[path: @current_path]}"}
        rel="nofollow"
        data-track="region_hint_followed"
        data-track-to={@suggested.code}
      >{@switch}</a>
      <a
        id="region-hint-stay"
        class="region-hint-stay"
        href={~p"/region/#{@region.code}?#{[path: @current_path]}"}
        rel="nofollow"
        data-track="region_hint_dismissed"
      >{@stay}</a>
    </aside>
    """
  end

  defp region_hint_text("hu"), do: gettext("Wygląda na to, że jesteś na Węgrzech.")
  defp region_hint_text("pl"), do: gettext("Wygląda na to, że jesteś w Polsce.")
  defp region_hint_switch("hu"), do: gettext("Przejdź do wersji węgierskiej")
  defp region_hint_switch("pl"), do: gettext("Przejdź do wersji polskiej")

  # Countries in the page language ("Węgry", "Hungary"); languages under
  # their own names.
  defp country_name("pl"), do: gettext("Polska")
  defp country_name("hu"), do: gettext("Węgry")

  # Each language under its own name.
  defp language_name("pl"), do: "Polski"
  defp language_name("en"), do: "English"
  defp language_name("hu"), do: "Magyar"

  defp flag(code), do: ~p"/images/flags/#{code <> ".svg"}"

  attr :sets, :list, required: true, doc: "the newest sets (`TcgCheapWeb.SiteFooter`)"

  @doc """
  The public footer: the newest sets and the guide's own pages, so every page
  leads to them, then who built it.
  """
  def site_footer(assigns) do
    ~H"""
    <footer id="site-footer" class="site-footer">
      <div class="site-footer-columns">
        <nav :if={@sets != []} id="site-footer-sets" aria-labelledby="site-footer-sets-title">
          <h2 id="site-footer-sets-title">{gettext("Najnowsze sety")}</h2>
          <ul class="site-footer-links site-footer-sets">
            <li :for={set <- @sets}>
              <.link navigate={SEO.expansion_path(set.id, set.name)}>{set.name}</.link>
            </li>
          </ul>
        </nav>
        <nav id="site-footer-pages" aria-labelledby="site-footer-pages-title">
          <h2 id="site-footer-pages-title">{gettext("Ważne linki")}</h2>
          <ul class="site-footer-links">
            <li><.link navigate={Paths.home()}>{gettext("Ceny produktów")}</.link></li>
            <li><.link navigate={Paths.cards()}>{gettext("Ceny kart")}</.link></li>
            <%!-- The articles and the bot page are Polish only. --%>
            <li :if={Paths.page(:booster_prices)}>
              <.link navigate={Paths.page(:booster_prices)}>
                {gettext("Ile kosztuje booster Pokémon?")}
              </.link>
            </li>
            <li :if={Paths.page(:expensive_cards)}>
              <.link navigate={Paths.page(:expensive_cards)}>
                {gettext("Najdroższe karty Pokémon")}
              </.link>
            </li>
            <li :if={Paths.page(:card_value)}>
              <.link navigate={Paths.page(:card_value)}>
                {gettext("Ile jest warta twoja karta?")}
              </.link>
            </li>
            <li :if={Paths.page(:bot)}>
              <.link navigate={Paths.page(:bot)}>{gettext("Dla sklepów: nasz bot")}</.link>
            </li>
          </ul>
        </nav>
      </div>
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

  @doc "A card's row in a list: image, name, number and set, cheapest shop, verdict and price."
  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :placement, :string, default: "list", doc: "where the click came from, for analytics"
  attr :rarity?, :boolean, default: false, doc: "name the rarity, for printings of one card"

  attr :verdict?, :boolean,
    default: true,
    doc: "judge the shop's price; a guide for sellers shows the price alone"

  def card_row(assigns) do
    # With an offer in stock, the row answers as the card's page does: its
    # cheapest shop, the verdict and that shop's price. Without one, the
    # lower known price.
    polish? = Region.poland?(Region.current())

    assigns =
      assign(assigns,
        status: single_verdict_status(assigns.row.verdict),
        # Elsewhere than in Poland, only Cardmarket's price: no shop there sells singles yet.
        offer: if(polish?, do: assigns.row.offer),
        price:
          card_price(%{
            polish_price: assigns.row.price,
            cardmarket_trend_pln: assigns.row.cardmarket_trend_pln
          })
      )

    ~H"""
    <li
      id={@id}
      class="guide-product guide-card"
    >
      <.link
        navigate={Paths.localize(@row.path)}
        class="guide-product-link"
        data-track="card_clicked"
        data-track-placement={@placement}
        data-track-card={@row.card.id}
        data-track-card-name={@row.card.name}
        data-track-verdict={@row.verdict}
      >
        <div class="guide-product-image guide-card-image">
          <img
            :if={@row.image}
            src={@row.image}
            alt=""
            loading="lazy"
            width="88"
            height="88"
          />
          <span :if={!@row.image} class="guide-card-placeholder" aria-hidden="true"></span>
        </div>
        <div class="guide-product-copy">
          <h3 class="guide-product-name">{@row.card.name}</h3>
          <p class="guide-product-meta">
            <span :if={@rarity? && @row.card.rarity}>{@row.card.rarity} ·</span>
            {@row.card.number} · {@row.expansion_name}
          </p>
        </div>
        <div class="guide-product-deal">
          <%= if @offer do %>
            <span class="guide-product-shop">{priced_shop_name(@offer)}</span>
            <%!-- Without a Cardmarket price there is nothing to judge; the card's page says why. --%>
            <.verdict_badge
              :if={@verdict? and @status != :insufficient_data}
              verdict={%{status: @status}}
              id={"card-verdict-#{@row.card.id}"}
              class="guide-product-verdict"
            />
            <p class="guide-product-price"><strong>{Polish.price(@offer.price)}</strong></p>
          <% else %>
            <p class="guide-product-price">
              <strong :if={@price}>{Polish.price(@price)}</strong>
              <span :if={!@price}>{gettext("Cena nieznana")}</span>
            </p>
          <% end %>
        </div>
      </.link>
    </li>
    """
  end

  @doc """
  A card's price in the current region: in Poland the lower of its Polish
  shop price and its Cardmarket trend (`CardGuide.price/1`); elsewhere its
  Cardmarket trend in the region's currency, as singles have no shops there.
  """
  @spec card_price(map()) :: Decimal.t() | nil
  def card_price(card) do
    if Region.poland?(Region.current()),
      do: CardGuide.price(card),
      else: card |> Map.get(:cardmarket_trend_pln) |> Region.from_pln()
  end

  @doc "A product's row in a list: photo, name, kind, cheapest shop, verdict and price."
  attr :summary, :map, required: true
  attr :priority, :boolean, default: false, doc: "the list's first photo, loaded eagerly"

  def product_row(assigns) do
    ~H"""
    <.link
      navigate={Paths.product(@summary.product.slug)}
      class="guide-product-link"
      data-track="product_clicked"
      data-track-product-slug={@summary.product.slug}
      data-track-verdict={@summary.verdict.status}
      data-track-preorder={to_string(@summary.preorder?)}
    >
      <.product_image
        small_photo={@summary.product.stored_photo_small_url}
        photo={@summary.product.stored_photo_card_url}
        page_photo={@summary.product.stored_photo_page_url}
        blur={@summary.product.photo_placeholder}
        sizes="(max-width: 42rem) 4.5rem, 5.5rem"
        loading={if(@priority, do: "eager", else: "lazy")}
        fetchpriority={if(@priority, do: "high")}
        kind={@summary.product.kind}
        alt=""
        class="guide-product-image"
      />
      <div class="guide-product-copy">
        <h3 class="guide-product-name">{@summary.product.name}</h3>
        <p class="guide-product-meta">
          {product_meta(@summary.product)}
        </p>
      </div>
      <div class="guide-product-deal">
        <span :if={@summary.verdict.cheapest} class="guide-product-shop">
          {priced_shop_name(@summary.verdict.cheapest)}
        </span>
        <%!-- Too few shops for a verdict: the row shows only the price; the product page says why. --%>
        <.verdict_badge
          :if={@summary.verdict.status not in [:cardmarket, :insufficient_data]}
          verdict={@summary.verdict}
          id={"verdict-#{@summary.product.slug}"}
          class="guide-product-verdict"
        />
        <p :if={@summary.verdict.cheapest} class="guide-product-price">
          <span
            :if={@summary.preorder?}
            id={"preorder-#{@summary.product.slug}"}
            class="guide-product-preorder"
          >
            <.verdict_icon status={:preorder} />{preorder_tag(@summary.premiere_in)}
          </span>
          <strong>{Polish.price(@summary.verdict.cheapest.price)}</strong>
        </p>
      </div>
    </.link>
    """
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
  The shop of a compared price (`Shops.compared/1`), saying when the price
  includes delivery from abroad: "Bangerpack, z wysyłką ze Szwecji".
  """
  @spec priced_shop_name(map()) :: String.t()
  def priced_shop_name(offer) do
    case delivered_term(offer) do
      nil -> shop_name(offer)
      term -> shop_name(offer) <> ", " <> term
    end
  end

  @doc """
  "z wysyłką ze Szwecji" for a compared price from a shop abroad (its
  delivery is known), else nil.
  """
  @spec delivered_term(map()) :: String.t() | nil
  def delivered_term(%{shop: key}) do
    market = Region.current().market
    shop = Shops.fetch(key)

    case {shop, Market.terms(shop, market)} do
      {{:ok, %{country: country}}, {:delivered, _delivery}} ->
        country |> delivered_from() |> glue_short_words()

      _domestic_or_listed ->
        nil
    end
  end

  @generic_photos ~w(binder booster card_dividers code_card coin condition_markers damage_counters
                     deck_box dice energy_cards player_guide playmat sleeves sticker storage_box)a

  @doc """
  A picture of what a contents item usually looks like (sleeves, dice…),
  from another product; nil for items without one and for a named booster,
  whose example would show another set's logo.
  """
  def generic_contents_photo(%{type: :booster, name: set}) when is_binary(set), do: nil

  def generic_contents_photo(%{type: type}) when type in @generic_photos,
    do: ~p"/images/contents/#{"#{type}.webp"}"

  def generic_contents_photo(_item), do: nil

  @doc "What a sealed product's contents item is called, in a sentence."
  def contents_item_label(%{type: :booster, name: nil}), do: gettext("booster")
  def contents_item_label(%{type: :booster, name: set}), do: gettext("booster %{set}", set: set)
  def contents_item_label(%{type: :promo_card, name: nil}), do: gettext("karta promo")

  def contents_item_label(%{type: :promo_card, name: card}),
    do: gettext("karta promo %{card}", card: card)

  def contents_item_label(%{type: :oversize_card, name: nil}), do: gettext("duża karta")

  def contents_item_label(%{type: :oversize_card, name: card}),
    do: gettext("duża karta %{card}", card: card)

  def contents_item_label(%{type: :card, name: nil}), do: gettext("karta")
  def contents_item_label(%{type: :card, name: card}), do: gettext("karta %{card}", card: card)

  def contents_item_label(%{type: :deck, variants: [_ | _] = variants}),
    do: gettext("talia losowa (1 z %{count})", count: length(variants))

  def contents_item_label(%{type: :deck, name: nil}), do: gettext("talia gotowa do gry")
  def contents_item_label(%{type: :deck, name: deck}), do: gettext("talia %{deck}", deck: deck)
  def contents_item_label(%{type: :sleeves}), do: gettext("koszulki na karty")
  # A booster's single energy slot can hold something else, as its name says.
  def contents_item_label(%{type: :energy_cards, quantity: 1, name: name}) when is_binary(name),
    do: name

  def contents_item_label(%{type: :energy_cards, quantity: 1}), do: gettext("karta energii")
  def contents_item_label(%{type: :energy_cards}), do: gettext("karty energii")
  def contents_item_label(%{type: :dice}), do: gettext("kość do gry")
  # Dice in elite trainer boxes, tokens in decks.
  def contents_item_label(%{type: :damage_counters}), do: gettext("znaczniki obrażeń")
  def contents_item_label(%{type: :coin}), do: gettext("moneta")
  def contents_item_label(%{type: :condition_markers}), do: gettext("znaczniki stanów")
  def contents_item_label(%{type: :deck_box}), do: gettext("pudełko na talię")
  def contents_item_label(%{type: :storage_box}), do: gettext("pudełko na karty")
  def contents_item_label(%{type: :card_dividers}), do: gettext("przekładki")
  def contents_item_label(%{type: :player_guide}), do: gettext("przewodnik gracza")
  def contents_item_label(%{type: :rule_sheet}), do: gettext("zasady gry")
  def contents_item_label(%{type: :code_card}), do: gettext("karta z kodem do Pokémon TCG Live")
  def contents_item_label(%{type: :sticker}), do: gettext("naklejki")
  def contents_item_label(%{type: :pin}), do: gettext("przypinka")
  def contents_item_label(%{type: :figure}), do: gettext("figurka")
  def contents_item_label(%{type: :binder}), do: gettext("album")
  def contents_item_label(%{type: :playmat}), do: gettext("mata do gry")
  def contents_item_label(%{type: :other, name: name}), do: name

  @doc """
  Binds one- and two-letter prepositions ("z", "ze", "w", "we") to the next
  word with a no-break space, so a line never ends with one, and a dash to
  the word before it, so a line never starts with one.
  """
  @spec glue_short_words(String.t() | nil) :: String.t() | nil
  def glue_short_words(nil), do: nil

  def glue_short_words(text) do
    text
    |> then(&Regex.replace(~r/(?<![\p{L}\p{N}])([zwZW]|[zwZW]e) /u, &1, "\\1\u00A0"))
    |> String.replace(" –", "\u00A0–")
  end

  @doc """
  The price an offer row shows: its compared price (`Shops.compared_price/2`),
  so a shop abroad's includes its delivery to Poland like the headline.
  """
  @spec row_price(map()) :: Decimal.t()
  def row_price(offer), do: Shops.compared_price(offer.shop, offer.price) || offer.price

  defp delivered_from("PL"), do: gettext("z wysyłką z Polski")
  defp delivered_from("NL"), do: gettext("z wysyłką z Holandii")
  defp delivered_from("DE"), do: gettext("z wysyłką z Niemiec")
  defp delivered_from("BE"), do: gettext("z wysyłką z Belgii")
  defp delivered_from("GB"), do: gettext("z wysyłką z Wielkiej Brytanii")
  defp delivered_from("SE"), do: gettext("z wysyłką ze Szwecji")
  defp delivered_from("DK"), do: gettext("z wysyłką z Danii")
  defp delivered_from("CZ"), do: gettext("z wysyłką z Czech")
  defp delivered_from("PT"), do: gettext("z wysyłką z Portugalii")
  defp delivered_from("HU"), do: gettext("z wysyłką z Węgier")

  @doc """
  A Cardmarket price in złoty behind the Cardmarket logo, the one mark for a
  Cardmarket reference price, linking to the product there.
  """
  attr :price, :any, required: true
  attr :href, :string, required: true
  attr :id, :string, default: nil
  attr :class, :any, default: nil

  attr :shipping, :boolean, default: false

  def cardmarket_price(assigns) do
    ~H"""
    <a
      id={@id}
      href={@href}
      target="_blank"
      rel="noopener nofollow"
      class={["cardmarket-price", @class]}
      title={
        if(@shipping,
          do: gettext("Cena na Cardmarket z wysyłką"),
          else: gettext("Cena na Cardmarket (bez wysyłki)")
        )
      }
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
  attr :id, :string, required: true
  attr :deals, :list, required: true
  attr :title, :string, required: true
  attr :products?, :boolean, default: false, doc: "name each deal's product, for lists of many"

  @doc """
  Retail chains' prices running today (`TcgCheap.Sealed.RetailDeal`), with
  their days and source, apart from the shop offers: stock differs from shop
  to shop, so they never enter the verdict.
  """
  def retail_deals(assigns) do
    ~H"""
    <section id={@id} class="product-section retail-deals" aria-labelledby={"#{@id}-title"}>
      <div class="product-section-heading">
        <h2 id={"#{@id}-title"}>{@title}</h2>
      </div>
      <.retail_clips id={@id} deals={@deals} products?={@products?} />
      <p class="guide-note">
        {gettext("Ceny z gazetek i zgłoszeń. Dostępność różna, nie wliczamy ich do oceny.")}
      </p>
    </section>
    """
  end

  attr :id, :string, required: true, doc: "prefix of each deal's DOM id"
  attr :deals, :list, required: true
  attr :products?, :boolean, default: false, doc: "name each deal's product, for lists of many"

  @doc """
  Retail deals as clippings from a leaflet, as the chains print them: the
  chain's logo, the price on a sticker, "nowe" for a deal that started in the
  last two days, then its days and the source the price was checked in.
  """
  def retail_clips(assigns) do
    ~H"""
    <ul class="retail-clips">
      <li
        :for={deal <- @deals}
        id={"#{@id}-#{deal.id}"}
        class={["retail-clip", !@products? && "retail-clip-unnamed"]}
      >
        <span :if={fresh_deal?(deal)} class="retail-clip-fresh">{gettext("nowe")}</span>
        <%!-- Every chain's logo carries its name, so the clipping shows no name beside it. --%>
        <img
          src={~p"/images/chains/#{Atom.to_string(deal.chain) <> ".webp"}"}
          alt={RetailDeal.chain_name(deal.chain)}
          width="96"
          height="32"
          loading="lazy"
          class={[
            "retail-clip-logo",
            RetailDeal.square_logo?(deal.chain) && "retail-clip-logo-square"
          ]}
        />
        <strong class="retail-clip-sticker">{Polish.price(deal.price)}</strong>
        <p :if={@products?} class="retail-clip-name">
          <.link :if={deal.product} navigate={Paths.product(deal.product.slug)}>{deal.product.name}</.link>
          <span :if={!deal.product}>{deal.title}</span>
        </p>
        <p class="retail-clip-when">{deal_days(deal)}</p>
        <p class="retail-clip-source">
          <a
            href={deal.source_url}
            target="_blank"
            rel="noopener nofollow"
            data-track="retail_deal_source_clicked"
            data-track-chain={deal.chain}
            aria-label={
              gettext("%{chain}: źródło ceny (otwiera się w nowej karcie)",
                chain: RetailDeal.chain_name(deal.chain)
              )
            }
          >{gettext("źródło")}&nbsp;↗</a>
        </p>
      </li>
    </ul>
    """
  end

  defp fresh_deal?(deal), do: Date.diff(Date.utc_today(), deal.starts_on) <= 2

  @doc ~S(A retail deal's days and caveat: "2–8 listopada · wybrane sklepy".)
  def deal_days(deal) do
    # A no-break space keeps each "·" at the end of a line, never at the start.
    [Polish.days(deal.starts_on, deal.ends_on), deal.note]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\u00A0· ")
  end

  attr :id, :string, required: true
  attr :offer, :map, required: true
  attr :location, :map, default: nil
  attr :today, Date, required: true
  attr :tags, :list, default: []

  attr :compared, :any,
    default: :polish,
    doc:
      "the offer's compared price in the region's market (`Guide.product/3`'s `compared`), nil when its shop is only listed; Polish by default"

  # One shop's offer. In stock is the default, so a row only says when it is
  # not (or that it is a pre-order), and when it was checked if that was not
  # today.
  def offer(assigns) do
    assigns =
      assigns
      |> assign(:checked_on, DateTime.to_date(assigns.offer.last_seen_at))
      |> assign(:compared, compared_price(assigns.compared, assigns.offer))
      |> then(&assign(&1, :price, &1.compared || &1.offer.price))

    ~H"""
    <li
      id={@id}
      class={["offer", !@offer.in_stock && !Map.get(@offer, :preorder, false) && "offer-unavailable"]}
    >
      <.shop_logo shop={@offer.shop} />
      <div class="offer-shop">
        <strong>{shop_name(@offer)}</strong>
        <span :if={@tags != []} class="offer-delivery single-offer-tags">{Enum.join(@tags, " · ")}</span>
        <.offer_delivery offer={@offer} compared={@compared} location={@location} />
      </div>
      <p class="offer-price">
        <span :if={Map.get(@offer, :preorder, false)} class="offer-preorder-label">{gettext(
          "przedsprzedaż"
        )}</span>
        <strong>{Polish.price(@price)}</strong>
        <span
          :if={(!@offer.in_stock and !Map.get(@offer, :preorder, false)) or @checked_on != @today}
          class="offer-checked"
        >
          {offer_note(@offer.in_stock or Map.get(@offer, :preorder, false), @checked_on, @today)}
        </span>
      </p>
      <a
        href={@offer.url}
        target="_blank"
        rel="noopener nofollow"
        class="offer-link"
        data-track="shop_link_clicked"
        data-track-placement="offers"
        data-track-shop={@offer.shop}
        data-track-price={@price}
        data-track-in-stock={to_string(@offer.in_stock)}
        data-track-preorder={to_string(Map.get(@offer, :preorder, false))}
        data-track-card={Map.get(@offer, :card_id)}
        aria-label={
          gettext("%{shop}: przejdź do sklepu (otwiera się w nowej karcie)", shop: shop_name(@offer))
        }
      >{gettext("Do sklepu")}</a>
    </li>
    """
  end

  defp compared_price(:polish, offer), do: Shops.compared_price(offer.shop, offer.price)
  defp compared_price(compared, _offer), do: compared

  defp offer_note(true, checked_on, today),
    do: gettext("sprawdzono %{when}", when: Polish.days_ago(checked_on, today))

  defp offer_note(false, today, today), do: gettext("brak na stanie")

  defp offer_note(false, checked_on, today),
    do: gettext("brak na stanie, sprawdzono %{when}", when: Polish.days_ago(checked_on, today))

  attr :offer, :map, required: true
  attr :compared, :any, default: nil, doc: "the offer's compared price, nil when only listed"
  attr :location, :map, default: nil

  # What delivery adds to an offer, from the shop's published terms:
  # "dostawa od 14,99 zł · darmowa od 400 zł · odbiór osobisty: Kraków (491 km)".
  # Pickup within the radius stands out on a line of its own.
  def offer_delivery(assigns) do
    {shop, km} =
      case Shops.fetch(assigns.offer.shop) do
        {:ok, shop} -> {shop, VisitorLocation.pickup_km(shop.key, assigns.location)}
        :error -> {nil, nil}
      end

    near? = km != nil and km <= VisitorLocation.radius_km()

    assigns =
      assign(assigns,
        shop: shop,
        km: km,
        near?: near?,
        terms:
          if(shop,
            do: delivery_terms(shop, assigns.offer.price, assigns.compared, km, near?),
            else: []
          )
      )

    # A no-break space keeps each "·" at the end of a line, never at the start.
    ~H"""
    <span :if={@terms != []} class="offer-delivery">{@terms
    |> Enum.join("\u00A0· ")
    |> glue_short_words()}</span>
    <span :if={@near?} class="offer-pickup-near">
      <.fluent_icon name={:location} />{gettext("odbiór: %{city}, %{distance}",
        city: @shop.pickup_city,
        distance: VisitorLocation.km(@km)
      )}
    </span>
    """
  end

  # Poland's terms come from the shops' published delivery to Poland; another
  # market's from how its prices were compared (`Market.terms/2`).
  defp delivery_terms(shop, price, compared, km, near?) do
    market = Region.current().market

    if market == Market.poland(),
      do: polish_delivery_terms(shop, price, km, near?),
      else:
        market_delivery_terms(Market.terms({:ok, shop}, market), shop, price, compared, km, near?)
  end

  # Delivered from abroad: the row's price includes it; say how much.
  defp market_delivery_terms(
         {:delivered, _delivery},
         shop,
         price,
         %Decimal{} = compared,
         _km,
         _near?
       ) do
    included =
      case Decimal.sub(compared, price) do
        %Decimal{coef: 0} -> gettext("w tym darmowa dostawa")
        shipping -> gettext("w tym dostawa %{amount}", amount: amount(shipping))
      end

    [origin_term(shop.country), included]
  end

  defp market_delivery_terms(:domestic, shop, price, _compared, km, near?),
    do: domestic_delivery_terms(shop, nil, price, km, near?, shop)

  # Only listed: its delivery here has no known price.
  defp market_delivery_terms(_listed, shop, _price, _compared, _km, _near?),
    do: [origin_term(shop.country), gettext("koszt dostawy w koszyku")]

  defp origin_term("PL"), do: gettext("wysyłka z Polski")
  defp origin_term(country), do: abroad_term(country)

  # A shop abroad's row shows its price with delivery: say what that includes.
  defp polish_delivery_terms(
         %{country: country, deliveries: %{"PL" => %{shipping_from: %Decimal{}} = delivery}},
         price,
         _km,
         _near?
       )
       when country != "PL" do
    included =
      case shipping(delivery, price) do
        :free -> gettext("w tym darmowa dostawa")
        {:from, from} -> gettext("w tym dostawa %{amount}", amount: amount(from))
      end

    [abroad_term(country), included]
  end

  defp polish_delivery_terms(shop, price, km, near?),
    do:
      domestic_delivery_terms(to_poland(shop), abroad_term(shop.country), price, km, near?, shop)

  # The shop's own delivery terms (a shop abroad only listed: none known).
  defp domestic_delivery_terms(delivery, origin, price, km, near?, shop) do
    threshold = delivery.free_shipping_from
    shipping = shipping(delivery, price)

    # The threshold stays visible: shops often grant it for some carriers only.
    cost =
      case shipping do
        :free -> gettext("darmowa dostawa od %{amount}", amount: amount(threshold))
        {:from, from} -> gettext("dostawa od %{amount}", amount: amount(from))
        :unknown -> gettext("koszt dostawy w koszyku")
      end

    [
      origin,
      cost,
      threshold && shipping != :free && gettext("darmowa od %{amount}", amount: amount(threshold)),
      pickup_term(shop.pickup_city, km, near?)
    ]
    |> Enum.filter(&is_binary/1)
  end

  # A Polish shop's own delivery, or a shop abroad's to Poland (none known
  # when it has no entry).
  defp to_poland(%{country: "PL"} = shop), do: shop

  defp to_poland(shop),
    do: Map.get(shop.deliveries, "PL", %{shipping_from: nil, free_shipping_from: nil})

  # Shops abroad (`Shop.country`): their prices are converted to złoty.
  defp abroad_term("PL"), do: nil
  defp abroad_term("NL"), do: gettext("wysyłka z Holandii")
  defp abroad_term("DE"), do: gettext("wysyłka z Niemiec")
  defp abroad_term("BE"), do: gettext("wysyłka z Belgii")
  defp abroad_term("GB"), do: gettext("wysyłka z Wielkiej Brytanii")
  defp abroad_term("SE"), do: gettext("wysyłka ze Szwecji")
  defp abroad_term("DK"), do: gettext("wysyłka z Danii")
  defp abroad_term("CZ"), do: gettext("wysyłka z Czech")
  defp abroad_term("PT"), do: gettext("wysyłka z Portugalii")
  defp abroad_term("HU"), do: gettext("wysyłka z Węgier")

  # Pickup within the radius is shown on its own line instead.
  defp pickup_term(nil, _km, _near?), do: nil
  defp pickup_term(_city, _km, true), do: nil
  defp pickup_term(city, nil, false), do: gettext("odbiór osobisty: %{city}", city: city)

  defp pickup_term(city, km, false),
    do:
      gettext("odbiór osobisty: %{city} (%{distance})",
        city: city,
        distance: VisitorLocation.km(km)
      )

  defp shipping(shop, price) do
    threshold = shop.free_shipping_from

    cond do
      threshold != nil and not Decimal.lt?(price, threshold) -> :free
      shop.shipping_from -> {:from, shop.shipping_from}
      true -> :unknown
    end
  end

  defp amount(value),
    do: if(Decimal.integer?(value), do: Polish.zloty(value), else: Polish.price(value))

  attr :id, :string, default: "offer-disclaimer"

  def offer_disclaimer(assigns) do
    ~H"""
    <p id={@id} class="guide-note offer-disclaimer">
      <.fluent_icon name={:shield_error} />
      {gettext(
        "Jesteśmy niezależnym agregatorem: nie sprzedajemy produktów i nie weryfikujemy sklepów. Zanim zapłacisz, sprawdź sklep – opinie, dane firmy i regulamin."
      )}
    </p>
    """
  end

  attr :offer, :map, required: true
  attr :preorder?, :boolean, default: false
  attr :prefix, :string, default: "verdict"

  def verdict_now(assigns) do
    ~H"""
    <div :if={@offer} class="verdict-now">
      <div>
        <p id={"#{@prefix}-price"} class="verdict-price">{Polish.price(@offer.price)}</p>
        <p id={"#{@prefix}-shop"} class="verdict-shop">
          {if(@preorder?,
            do: gettext("najtaniej w przedsprzedaży w"),
            else: gettext("najtaniej teraz w")
          )}&nbsp;<strong>{shop_name(@offer)}</strong><span :if={delivered_term(@offer)}>, {delivered_term(
            @offer
          )}</span>
        </p>
      </div>
      <a
        id={"#{@prefix}-go"}
        href={@offer.url}
        target="_blank"
        rel="noopener nofollow"
        class="verdict-go"
        data-track="shop_link_clicked"
        data-track-placement="verdict"
        data-track-shop={@offer.shop}
        data-track-price={@offer.price}
        data-track-in-stock={to_string(@offer.in_stock)}
        data-track-preorder={to_string(Map.get(@offer, :preorder, false))}
      >
        {gettext("Do sklepu")}<span class="sr-only">{gettext("(otwiera się w nowej karcie)")}</span>
      </a>
    </div>
    """
  end

  attr :product, :map, required: true
  attr :cardmarket_pln, :any, required: true
  attr :eur_pln, :map, default: nil

  attr :id, :string, default: "product-cardmarket"
  attr :reverse, :any, default: nil
  attr :reverse_pln, :any, default: nil

  def cardmarket_reference(assigns) do
    ~H"""
    <section
      id={@id}
      class="product-section cardmarket-reference"
      aria-labelledby={"#{@id}-title"}
    >
      <div class="product-section-heading">
        <h2 id={"#{@id}-title"} class="cardmarket-title">
          <img src={~p"/images/cardmarket.png"} alt="" width="24" height="24" />{gettext(
            "Cena na Cardmarket"
          )}
        </h2>
        <p :if={@product.cardmarket_price_updated_on}>
          {gettext("stan na %{date}", date: Polish.date(@product.cardmarket_price_updated_on))}
        </p>
      </div>
      <%= if @product.cardmarket_trend || @reverse do %>
        <p :if={@product.cardmarket_trend} id="cardmarket-trend" class="cardmarket-trend">
          {gettext("Trend:")} <strong>{Polish.eur(@product.cardmarket_trend)}</strong>
          <span :if={@cardmarket_pln}>≈ {Polish.rough_zloty(@cardmarket_pln)}</span>
        </p>
        <p :if={@reverse} class="cardmarket-trend">
          {gettext("Reverse holo:")}
          <strong>{Polish.eur(@reverse)}</strong><span :if={@reverse_pln}>≈ {Polish.rough_zloty(
            @reverse_pln
          )}</span>
        </p>
        <p class="guide-note">
          {gettext("Europejska giełda.")}
          <span :if={@eur_pln}>
            {euro_rate_note(@eur_pln)}
          </span>
          <span :if={@product.cardmarket_added_on} id="product-added">
            {gettext("Na Cardmarket od %{date}.", date: Polish.date(@product.cardmarket_added_on))}
          </span>
        </p>
        <p class="reference-link">
          <a href={cardmarket_url(@product.cardmarket_id)} target="_blank" rel="noopener nofollow">
            {gettext("Zobacz na Cardmarket")} →
          </a>
        </p>
      <% else %>
        <p id="cardmarket-none" class="guide-note">
          {gettext("Cardmarket nie podaje jeszcze ceny tego produktu.")}
        </p>
      <% end %>
    </section>
    """
  end

  @doc """
  The euro's rate behind a Cardmarket price in the region's currency: NBP's
  own for złoty; another currency's goes through złoty at NBP's rates.
  """
  @spec euro_rate_note(%{rate: Decimal.t(), date: Date.t()}) :: String.t()
  def euro_rate_note(rate) do
    case Polish.currency_symbol() do
      "zł" ->
        gettext("Kurs NBP %{rate} zł z %{date}.",
          rate: Polish.rate(rate.rate),
          date: Polish.date(rate.date)
        )

      currency ->
        gettext("Kurs %{rate} %{currency} za euro z kursów NBP z %{date}.",
          rate: Polish.rate(rate.rate),
          currency: currency,
          date: Polish.date(rate.date)
        )
    end
  end

  attr :id, :string, required: true
  attr :count, :integer, required: true

  def offers_heading(assigns) do
    ~H"""
    <div class="product-section-heading">
      <h2 id={@id}>{gettext("Oferty w sklepach")}</h2>
      <p :if={@count > 0}>
        {gettext("%{offers} na stanie", offers: Polish.plural(@count, "oferta", "oferty", "ofert"))}
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  attr :open, :boolean, default: false

  def offers_disclosure(assigns) do
    ~H"""
    <details id={@id} class="verdict-method offers-out" open={@open}>
      <summary data-track="product_section_opened" data-track-section="out_of_stock_offers">
        {@label}<.fluent_icon name={:chevron_down} class="verdict-method-chevron" />
      </summary>
      {render_slot(@inner_block)}
    </details>
    """
  end

  attr :id, :string, required: true
  attr :status, :atom, required: true
  slot :header, required: true
  slot :inner_block, required: true

  def verdict_panel(assigns) do
    ~H"""
    <section
      id={@id}
      class={["verdict-block", "verdict-block-#{@status}"]}
      aria-labelledby={"#{@id}-title"}
    >
      <h2 id={"#{@id}-title"} class="sr-only">{gettext("Ocena ceny")}</h2>
      {render_slot(@header)}
      <div class="verdict-body">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :id, :string, required: true
  slot :inner_block, required: true

  def verdict_method(assigns) do
    ~H"""
    <details id={@id} class="verdict-method">
      <summary data-track="product_section_opened" data-track-section="verdict_method">
        {gettext("Jak liczymy?")}<.fluent_icon name={:chevron_down} class="verdict-method-chevron" />
      </summary>
      {render_slot(@inner_block)}
    </details>
    """
  end
end
