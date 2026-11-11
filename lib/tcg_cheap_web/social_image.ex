defmodule TcgCheapWeb.SocialImage do
  @moduledoc """
  Link-preview cards (Open Graph, 1200×630 JPEG) for the buying guide: the
  home page, each product, each card, each expansion and the expensive
  cards article, drawn as SVG in the guide's look, rendered with resvg and
  the bundled fonts (`priv/social_fonts`, OFL; full Latin Extended, unlike
  the subset web fonts) and encoded with libvips.

  Text beside card scans is aligned towards them; text alone is centred.

  A product card shows the same answer as its page: the verdict, the
  cheapest in-stock price and shop, the typical and suggested prices. Its
  photo comes only from our mirrored storage variant, shrunk before it is drawn.
  At most two cards render at once;
  `TcgCheapWeb.SocialImageController` keeps rendered cards in storage.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed.{CardImage, Guide, Shops}
  alias TcgCheap.Storage
  alias TcgCheap.Storage.ImageDownload
  alias TcgCheapWeb.{CardRecords, GuideComponents, Polish}
  alias Vix.Vips.Operation

  # Bump when the layout changes, so stored and cached cards are replaced.
  @design 4

  @width 1200
  @height 630
  @margin 56

  @bench "#f1eadc"
  @paper "#fffdf8"
  @ink "#171614"
  @muted "#6d6256"
  @rise "#27714b"
  @fall "#a6402f"

  @display "Barlow Condensed"
  @mono "Azeret Mono"

  # The logo is 405×96; a card scan is 245×342.
  @logo_ratio 405 / 96
  @scan_ratio 342 / 245
  @max_renders 2
  # A render waits this long for a free slot before giving up.
  @slot_wait_ms 3_000
  @min_title 40
  @title_sizes [72, 64, 56, 50, 44, @min_title]
  @xml_forbidden ~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/u
  @spaces ~r/\s+/u

  def width, do: @width
  def height, do: @height

  @doc "A version of what the home card shows, for its storage key and URL."
  @spec home_version() :: String.t()
  def home_version, do: version(home_promise())

  @doc "A version of what a product's card shows, for its storage key and URL."
  @spec product_version(map()) :: String.t()
  def product_version(%{product: product, verdict: verdict} = page) do
    version(
      {product.name, product.stored_photo_page_url, product.kind, product.set_name,
       product.region, verdict.status,
       verdict.cheapest && {verdict.cheapest.price, verdict.cheapest.shop}, verdict.typical,
       length(verdict.shop_prices), page.past.last_known,
       page.suggested_price && page.suggested_price.price}
    )
  end

  # Versions hash what a preview draws, as drawn: a price to the złoty or
  # grosz it shows, not the day's exact conversion, so a preview is drawn
  # again only when it would look different.

  @doc "A version of what a card's preview shows (`CardGuide.page/3`)."
  @spec card_version(map()) :: String.t()
  def card_version(page) do
    %{cheapest: cheapest, verdict: verdict} = card_answer_row(page)

    price =
      if cheapest,
        do: {Polish.price(cheapest.price), cheapest.shop},
        else: (value = cardmarket_pln(page)) && Polish.zloty(value)

    version(
      {page.card.name, page.card.number, page.expansion_name, page.image,
       GuideComponents.single_verdict_status(verdict), price}
    )
  end

  @doc "A version of what an expansion's preview shows (`Guide.expansion/3`)."
  @spec expansion_version(String.t(), map()) :: String.t()
  def expansion_version(name, set_page) do
    top = top_card(set_page)

    version(
      {name, Enum.map(expansion_scans(set_page), &{&1.card.id, &1.image}),
       top && {top.card.name, Polish.zloty(top.price), top.source},
       (booster = booster_price(set_page)) && Polish.price(booster)}
    )
  end

  @doc "A version of what the card list's preview shows (`Guide.singles_market/0`)."
  @spec cards_version(map()) :: String.t()
  def cards_version(market) do
    deal = market.deal

    version(
      {market.in_stock, market.shops,
       deal && {deal.card.name, Polish.price(deal.price), deal.shop, deal.image}}
    )
  end

  @doc "A version of what the booster price page's preview shows."
  @spec boosters_version(map()) :: String.t()
  def boosters_version(page) do
    version(
      Enum.map(
        [page.cheapest, List.first(page.boosters)]
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.product.id),
        fn booster ->
          {booster.product.id, booster.product.set_name, booster.product.stored_photo_card_url,
           Polish.price(booster.verdict.cheapest.price), booster.verdict.cheapest.shop}
        end
      )
    )
  end

  @doc "A version of what the expensive cards article's preview shows."
  @spec expensive_cards_version(map()) :: String.t()
  def expensive_cards_version(overview) do
    record = hd(CardRecords.all())

    version(
      {{record.id, record.name, record.usd, record.image},
       Enum.map(
         Enum.take(overview.highlights, 2),
         &{&1.card.name, Polish.zloty(&1.value), &1.image_large}
       )}
    )
  end

  defp version(content),
    do: {@design, content} |> :erlang.phash2() |> Integer.to_string(36) |> String.downcase()

  @doc "The promise under the home card's headline."
  @spec home_promise() :: String.t()
  def home_promise,
    do: gettext("Ceny Pokémon TCG ze sklepów wysyłających do Polski, sprawdzane codziennie.")

  @doc "The home card: the promise and the verdict scale."
  @spec home() :: {:ok, binary()} | {:error, term()}
  def home do
    x = @margin + 16
    width = 600

    headline = balanced(gettext("Sprawdź, czy cena jest dobra"), 96, :display, width, 2)

    promise = balanced(home_promise(), 27, :mono, width, 3)

    logo_height = 64
    headline_line = 92
    promise_line = 40

    left_height =
      logo_height + 46 + length(headline) * headline_line + 26 + length(promise) * promise_line

    top = div(@height - left_height, 2)
    headline_top = top + logo_height + 46
    promise_top = headline_top + length(headline) * headline_line + 26

    {card, card_height} = scale_card(728, @width - x - 728)

    with_slot(fn ->
      render([
        background(),
        logo(x, top, logo_height),
        text_lines(headline, x, headline_top, 96, headline_line, :display, @ink),
        text_lines(promise, x, promise_top, 27, promise_line, :mono, @ink),
        card.(div(@height - card_height, 2))
      ])
    end)
  end

  @doc """
  A product's card from its guide page (`TcgCheap.Sealed.Guide.product/2`).
  `{:partial, jpeg}` is a card drawn without a photo the product has but
  that could not be fetched: worth serving, not worth keeping.
  """
  @spec product(map()) :: {:ok, binary()} | {:partial, binary()} | {:error, term()}
  def product(%{product: product} = page) do
    with_slot(fn ->
      photo = photo(product.stored_photo_page_url)

      {column, tile} =
        case photo do
          {:ok, png} -> {630, photo_tile(png, @margin, @margin, @height - 2 * @margin)}
          _none -> {@margin + 16, nil}
        end

      width = @width - @margin - 16 - column
      {answer, answer_height} = answer_block(page, column, width)

      logo_height = 48
      title_top = @margin + logo_height + 40
      # The room between the title's top and the answer, less the gap above it.
      room = @height - @margin - answer_height - 32 - title_top
      max_lines = if tile, do: 3, else: 2
      name = normalize(product.name)

      # The facts line gives way when the name would not fit in one line.
      {facts, room} =
        case GuideComponents.product_meta(product) |> normalize() |> wrap(22, :mono, width, 1) do
          facts when room - 44 >= @min_title * 0.96 -> {facts, room - 44}
          _facts -> {[], room}
        end

      {size, title} = fit_title(name, width, room, max_lines)
      line = round(size * 0.96)

      card =
        render([
          background(),
          tile,
          logo(column, @margin, logo_height),
          text_lines(title, column, title_top, size, line, :display, @ink),
          text_lines(facts, column, title_top + length(title) * line + 14, 22, 30, :mono, @muted),
          answer
        ])

      case {card, photo} do
        {{:ok, jpeg}, :error} -> {:partial, jpeg}
        {card, _photo} -> card
      end
    end)
  end

  @doc """
  A card's preview from its guide page (`TcgCheap.Sealed.CardGuide.page/3`):
  the scan on the left, the name and the answer beside it. `{:partial, jpeg}`
  is a preview drawn without a scan that could not be fetched.
  """
  @spec card(map()) :: {:ok, binary()} | {:partial, binary()} | {:error, term()}
  def card(page) do
    with_slot(fn ->
      scan = scan(page.image)
      scan_width = round((@height - 2 * @margin) / @scan_ratio)

      {column, art} =
        case scan do
          {:ok, png} -> {72 + scan_width + 56, card_scan(png, 72, @margin, scan_width, 0)}
          _none -> {@margin + 16, nil}
        end

      width = @width - @margin - column
      {answer, answer_height} = card_answer(page, column, width)

      logo_height = 48
      title_top = @margin + logo_height + 40
      facts = wrap("#{page.card.number} · #{page.expansion_name}", 22, :mono, width, 1)
      room = @height - @margin - answer_height - 32 - title_top - 44

      {size, title} =
        fit_title(normalize(page.card.name), width, room, 2, [96, 84 | @title_sizes])

      line = round(size * 0.96)

      preview =
        render([
          background(),
          art,
          logo(column, @margin, logo_height),
          text_lines(title, column, title_top, size, line, :display, @ink),
          text_lines(facts, column, title_top + length(title) * line + 14, 22, 30, :mono, @muted),
          answer
        ])

      partial(preview, [scan])
    end)
  end

  # The normal print's answer, or the first print a shop has in stock.
  defp card_answer_row(page),
    do: Enum.find(page.answers, & &1.cheapest) || hd(page.answers)

  defp card_answer(page, x, width) do
    %{cheapest: cheapest, verdict: verdict} = card_answer_row(page)
    status = GuideComponents.single_verdict_status(verdict)
    # Only a judged price or a missing one has a badge; "too few shops" means
    # nothing on a card.
    badge = if status in [:good, :normal, :expensive, :out_of_stock], do: %{status: status}

    {price, line} =
      case {cheapest, cardmarket_pln(page)} do
        {%{price: price}, _cardmarket} ->
          {{Polish.price(price), 104, @ink},
           gettext("najtaniej teraz w %{shop}", shop: GuideComponents.priced_shop_name(cheapest))}

        {nil, %Decimal{} = value} ->
          {{Polish.zloty(value), 68, @muted}, gettext("cena na Cardmarket")}

        {nil, nil} ->
          {nil, gettext("Teraz żaden sklep nie ma tej karty na stanie.")}
      end

    answer_stack(badge, price, line, [], x, width)
  end

  defp cardmarket_pln(%{price: %{trend: trend}, rate: rate}), do: Guide.to_pln(trend, rate)
  defp cardmarket_pln(_page), do: nil

  @doc """
  An expansion's preview from its set page (`TcgCheap.Sealed.Guide.expansion/3`):
  its three most valuable cards fanned out, its name, its top card and its
  booster beside them; without any scan, the name alone, centred.
  """
  @spec expansion(String.t(), map()) :: {:ok, binary()} | {:partial, binary()} | {:error, term()}
  def expansion(name, set_page) do
    with_slot(fn ->
      tops = expansion_scans(set_page)
      scans = Enum.map(tops, &scan(&1.image))
      pngs = for {:ok, png} <- scans, do: png

      figures =
        Enum.filter(
          [
            (booster = booster_price(set_page)) &&
              %{text: gettext("Booster od %{price}", price: Polish.price(booster)), size: 64},
            (top = top_card(set_page)) &&
              %{
                text: "#{top.card.name} ≈ #{Polish.zloty(top.price)}",
                size: 48,
                caption: top_card_caption(top)
              }
          ],
          & &1
        )

      preview =
        case pngs do
          [] ->
            render(centred_page(name, figures))

          [png] ->
            width = round((@height - 2 * @margin) / @scan_ratio)

            render([
              background(),
              card_scan(png, 72, @margin, width, 0)
              | titled_figures(name, figures, 72 + width + 56, "start")
            ])

          pngs ->
            render([
              background(),
              fan(pngs, 300, 315) | titled_figures(name, figures, 600, "start")
            ])
        end

      partial(preview, scans)
    end)
  end

  # The set's most valuable card, with a scan or not.
  defp top_card(%{set: %{top_cards: [top | _]}}), do: top
  defp top_card(_set_page), do: nil

  # The cards on a set page's "most valuable" list that have a scan.
  defp expansion_scans(%{set: %{top_cards: tops}}),
    do: tops |> Enum.filter(& &1.image) |> Enum.take(3)

  defp expansion_scans(_set_page), do: []

  defp booster_price(%{booster: %{preorder?: false, verdict: %{cheapest: %{price: price}}}}),
    do: price

  defp booster_price(_set_page), do: nil

  # Where the set's top card price comes from, as the set page says it.
  defp top_card_caption(%{source: {:shop, shop}}),
    do: gettext("najcenniejsza karta · najtaniej w %{shop}", shop: Shops.name(shop))

  defp top_card_caption(_top), do: gettext("najcenniejsza karta · Cardmarket")

  @doc """
  The expensive cards article's preview: the record card between today's two
  most expensive, and the record and today's top price beside them.
  """
  @spec expensive_cards(map()) :: {:ok, binary()} | {:partial, binary()} | {:error, term()}
  def expensive_cards(overview) do
    record = hd(CardRecords.all())

    with_slot(fn ->
      today = Enum.take(overview.highlights, 2)
      # The last scan is drawn in front: the record.
      scans = Enum.map(today, &stored_scan(&1.image_large)) ++ [record_scan(record)]
      pngs = for {:ok, png} <- scans, do: png

      figures =
        Enum.filter(
          [
            %{
              text: CardRecords.usd(record.usd),
              size: 64,
              caption: gettext("rekord: %{card}", card: record.name)
            },
            today != [] &&
              %{
                text: "#{hd(today).card.name} ≈ #{Polish.zloty(hd(today).value)}",
                size: 48,
                caption: gettext("najdroższa z ostatnich lat")
              }
          ],
          & &1
        )

      headline = gettext("Najdroższe karty Pokémon")

      preview =
        case pngs do
          [] ->
            render(centred_page(headline, figures))

          pngs ->
            render([
              background(),
              fan(pngs, 930, 315, 250, 200) | titled_figures(headline, figures, 600, "end")
            ])
        end

      partial(preview, scans)
    end)
  end

  @doc """
  The card list's preview from its market figures (`Guide.singles_market/0`):
  the best deal's scan, the count in stock and the deal beside it.
  """
  @spec cards(map()) :: {:ok, binary()} | {:partial, binary()} | {:error, term()}
  def cards(market) do
    with_slot(fn ->
      deal = market.deal
      scan = scan(deal && deal.image)
      title = gettext("Ceny kart Pokémon")

      figures =
        Enum.filter(
          [
            %{
              text:
                gettext("%{cards} na stanie",
                  cards: Polish.plural(market.in_stock, "karta", "karty", "kart")
                ),
              size: 64,
              caption:
                gettext("w %{shops}",
                  shops: Polish.plural(market.shops, "sklepie", "sklepach", "sklepach")
                )
            },
            deal &&
              %{
                text:
                  gettext("%{card} za %{price}",
                    card: deal.card.name,
                    price: Polish.price(deal.price)
                  ),
                size: 48,
                caption:
                  gettext("najlepsza okazja teraz · %{shop}",
                    shop: Shops.name(deal.shop)
                  )
              }
          ],
          & &1
        )

      preview =
        case scan do
          {:ok, png} ->
            width = round((@height - 2 * @margin) / @scan_ratio)

            render([
              background(),
              card_scan(png, 72, @margin, width, 0)
              | titled_figures(title, figures, 72 + width + 56, "start")
            ])

          _none ->
            render(centred_page(title, figures))
        end

      partial(preview, [scan])
    end)
  end

  @doc """
  The booster price page's preview (`Guide.booster_prices/1`): the newest
  set's booster on a paper tile, the cheapest booster and the newest one's
  price beside it.
  """
  @spec boosters(map()) :: {:ok, binary()} | {:partial, binary()} | {:error, term()}
  def boosters(page) do
    with_slot(fn ->
      newest = List.first(page.boosters)
      cheapest = page.cheapest
      photo = photo(newest && newest.product.stored_photo_card_url)
      title = gettext("Ile kosztuje booster Pokémon?")

      figures =
        Enum.filter(
          [
            cheapest &&
              %{
                text:
                  gettext("od %{price}", price: Polish.price(cheapest.verdict.cheapest.price)),
                size: 64,
                caption: gettext("najtańszy: %{set}", set: cheapest.product.set_name)
              },
            newest && (is_nil(cheapest) or newest.product.id != cheapest.product.id) &&
              %{
                text:
                  "#{newest.product.set_name}: #{Polish.price(newest.verdict.cheapest.price)}",
                size: 48,
                caption:
                  gettext("najnowszy set · %{shop}",
                    shop: GuideComponents.priced_shop_name(newest.verdict.cheapest)
                  )
              }
          ],
          & &1
        )

      preview =
        case photo do
          {:ok, png} ->
            render([
              background(),
              photo_tile(png, @margin, @margin, @height - 2 * @margin)
              | titled_figures(title, figures, 630, "start")
            ])

          _none ->
            render(centred_page(title, figures))
        end

      partial(preview, [photo])
    end)
  end

  # A title and figures (a big line and an optional caption under it),
  # centred vertically and aligned at `x` towards the scans beside them:
  # "end" when they are on the right, "start" when on the left.
  defp titled_figures(title, figures, x, anchor) do
    width = if anchor == "end", do: x - @margin - 16, else: @width - @margin - x
    logo_height = 48
    logo_x = if anchor == "end", do: x - round(logo_height * @logo_ratio), else: x
    {size, lines} = fit_lines(normalize(title), width, [84, 72, 64, 56], 2)
    line = round(size * 0.98)

    laid =
      Enum.map(figures, fn figure ->
        figure_size = fit_size(figure.text, Map.get(figure, :size, 64), width)

        captions =
          case Map.get(figure, :caption) do
            nil -> []
            caption -> wrap(caption, 26, :mono, width, 2)
          end

        {figure.text, figure_size, captions,
         round(figure_size * 0.95) + length(captions) * 34 + 26}
      end)

    height =
      logo_height + 36 + length(lines) * line + 30 +
        Enum.sum(Enum.map(laid, &elem(&1, 3)))

    top = div(@height - height, 2)
    title_top = top + logo_height + 36

    {figure_svg, _end} =
      Enum.map_reduce(laid, title_top + length(lines) * line + 30, fn {text, figure_size,
                                                                       captions, figure_height},
                                                                      figure_top ->
        baseline = figure_top + round(figure_size * 0.78)

        {[
           text_line(text, x, baseline, figure_size, :display, @ink, anchor),
           text_lines(captions, x, baseline + 10, 26, 34, :mono, @muted, anchor)
         ], figure_top + figure_height}
      end)

    [
      logo(logo_x, top, logo_height),
      text_lines(lines, x, title_top, size, line, :display, @ink, anchor),
      figure_svg
    ]
  end

  # The largest size, from `size` down to 36, at which a line fits `width`.
  defp fit_size(text, size, width) do
    Enum.find(size..36//-4, 36, &(text_width(text, &1, :display) <= width))
  end

  # The largest size at which the text fits `max_lines` balanced lines; the
  # smallest, ellipsized, otherwise.
  defp fit_lines(text, width, sizes, max_lines) do
    Enum.find_value(sizes, fn size ->
      if length(greedy(text, size, :display, width)) <= max_lines,
        do: {size, balanced(text, size, :display, width, max_lines)}
    end) || {List.last(sizes), wrap(text, List.last(sizes), :display, width, max_lines)}
  end

  # A title and figures alone, centred, for a preview without a picture.
  defp centred_page(title, figures) do
    centre = div(@width, 2)
    width = @width - 2 * (@margin + 64)
    logo_height = 56
    logo_width = round(logo_height * @logo_ratio)
    {size, lines} = fit_lines(normalize(title), width, [88, 76, 64], 2)
    line = round(size * 0.98)

    laid =
      Enum.map(figures, fn figure ->
        figure_size = fit_size(figure.text, min(Map.get(figure, :size, 64), 56), width)

        captions =
          if caption = Map.get(figure, :caption), do: wrap(caption, 26, :mono, width, 1), else: []

        {figure.text, figure_size, captions,
         round(figure_size * 0.95) + length(captions) * 34 + 22}
      end)

    height =
      logo_height + 40 + length(lines) * line + 30 + Enum.sum(Enum.map(laid, &elem(&1, 3)))

    top = div(@height - height, 2)
    title_top = top + logo_height + 40

    {figure_svg, _end} =
      Enum.map_reduce(laid, title_top + length(lines) * line + 30, fn {text, figure_size,
                                                                       captions, figure_height},
                                                                      figure_top ->
        baseline = figure_top + round(figure_size * 0.78)

        {[
           text_line(text, centre, baseline, figure_size, :display, @ink, "middle"),
           text_lines(captions, centre, baseline + 10, 26, 34, :mono, @muted, "middle")
         ], figure_top + figure_height}
      end)

    [
      background(),
      logo(centre - div(logo_width, 2), top, logo_height),
      text_lines(lines, centre, title_top, size, line, :display, @ink, "middle"),
      figure_svg
    ]
  end

  # Up to three scans fanned out around (cx, cy): the last one in front,
  # straight and `front` wide; the others `side` wide, turned out to its sides.
  defp fan(pngs, cx, cy, front \\ 220, side \\ 220) do
    placed =
      case pngs do
        [only] ->
          [{only, front, 0, 0, 0}]

        [left, last] ->
          [{left, side, -70, 16, -8}, {last, front, 70, 0, 4}]

        [left, right, last] ->
          [{left, side, -122, 20, -10}, {right, side, 122, 20, 10}, {last, front, 0, 0, 0}]
      end

    for {png, width, dx, dy, angle} <- placed do
      height = round(width * @scan_ratio)
      card_scan(png, cx + dx - div(width, 2), cy + dy - div(height, 2), width, angle)
    end
  end

  # A card scan standing on the bench with a soft shadow, turned `angle`
  # degrees about its centre.
  defp card_scan(png, x, y, width, angle) do
    height = round(width * @scan_ratio)
    cx = x + width / 2
    cy = y + height / 2

    [
      ~s|<g transform="rotate(#{angle} #{cx} #{cy})" filter="url(#lift)">|,
      ~s(<image href="data:image/png;base64,#{Base.encode64(png)}" x="#{x}" y="#{y}" width="#{width}" height="#{height}" preserveAspectRatio="xMidYMid meet"/>),
      "</g>"
    ]
  end

  # A card's scan from our mirrored storage (its detail variant) by source.
  defp scan(nil), do: :none

  defp scan(source) do
    hash = CardImage.source_hash(source)

    case Storage.mirrored_image_urls([hash], :detail) do
      %{^hash => url} -> stored_scan(url)
      _missing -> :error
    end
  end

  defp stored_scan(nil), do: :none
  defp stored_scan(url), do: photo(url)

  # A record's own picture, kept with the app (`priv/static/images/records`).
  defp record_scan(%{image: nil}), do: :none

  defp record_scan(%{image: file}) do
    path = Application.app_dir(:tcg_cheap, "priv/static/images/records/" <> file)

    with {:ok, body} <- File.read(path),
         {:ok, image} <- Operation.thumbnail_buffer(body, 600, size: :VIPS_SIZE_DOWN),
         {:ok, png} <- Image.write(image, :memory, suffix: ".png") do
      {:ok, png}
    else
      _unusable -> :error
    end
  end

  # A preview missing a picture it should have is served, not kept.
  defp partial({:ok, jpeg}, pictures) do
    if Enum.any?(pictures, &(&1 == :error)), do: {:partial, jpeg}, else: {:ok, jpeg}
  end

  defp partial(error, _pictures), do: error

  # The product's verdict, cheapest price and shop, then its typical and
  # suggested prices.
  defp answer_block(page, x, width) do
    %{verdict: verdict, past: past} = page

    {price, shop_line} =
      case {verdict, past} do
        {%{cheapest: %{price: price} = cheapest}, _past} ->
          {{Polish.price(price), 104, @ink},
           gettext("najtaniej teraz w %{shop}", shop: GuideComponents.priced_shop_name(cheapest))}

        {_verdict, %{last_known: %{price: price, date: date}}} ->
          {{Polish.price(price), 68, @muted},
           gettext("ostatnio najtaniej · %{date}", date: Calendar.strftime(date, "%d.%m.%Y"))}

        _none ->
          {nil, gettext("Teraz żaden sklep nie ma tego produktu na stanie.")}
      end

    notes =
      Enum.filter(
        [
          typical_note(verdict),
          page.suggested_price &&
            gettext("Cena sugerowana (REBEL): %{price}",
              price: Polish.price(page.suggested_price.price)
            )
        ],
        &is_binary/1
      )

    answer_stack(verdict, price, shop_line, notes, x, width)
  end

  # Badge, price and shop line, then notes, stacked up from the bottom edge;
  # returns the SVG and its height. A nil verdict draws no badge.
  defp answer_stack(verdict, price, shop_line, notes, x, width) do
    shop_lines = wrap(shop_line, 23, :mono, width, 2)
    badge_height = if verdict, do: 72 + 26, else: 0
    price_height = price_height(price)
    shop_height = length(shop_lines) * 34
    notes_height = if notes == [], do: 0, else: 12 + length(notes) * 30
    height = badge_height + price_height + shop_height + notes_height
    top = @height - @margin - height
    price_top = top + badge_height
    shop_top = price_top + price_height

    svg = [
      verdict && badge(verdict, x, top, 72, 40),
      price_line(price, x, price_top),
      text_lines(shop_lines, x, shop_top, 23, 34, :mono, @ink),
      text_lines(notes, x, shop_top + shop_height + 12, 20, 30, :mono, @muted)
    ]

    {svg, height}
  end

  defp price_height(nil), do: 0
  defp price_height({_text, size, _color}), do: round(size * 0.9)

  defp price_line(nil, _x, _top), do: nil

  defp price_line({text, size, color}, x, top),
    do: text_line(text, x, top + round(size * 0.76), size, :display, color)

  # The Cardmarket comparison is already in the badge.
  defp typical_note(%{typical: %Decimal{} = typical, typical_source: :shops} = verdict),
    do:
      gettext("Typowa cena dziś w %{shops}: %{price}",
        shops: Polish.plural(length(verdict.shop_prices), "sklepie", "sklepach", "sklepach"),
        price: Polish.zloty(typical)
      )

  defp typical_note(_verdict), do: nil

  # The guide's large verdict badge: filled for good, normal and expensive,
  # a paper slip with a drawn bottom edge otherwise; text and mark carry the
  # meaning, never colour alone.
  defp badge(verdict, x, y, height, size, width \\ nil) do
    {fill, color, edge} = badge_colors(verdict)
    label = verdict |> GuideComponents.verdict_label() |> String.upcase()
    mark = round(size * 0.7)
    text_x = x + 24 + mark + 14
    width = width || text_x - x + text_width(label, size, :display, 1.6) + 24

    [
      ~s(<rect x="#{x}" y="#{y}" width="#{round(width)}" height="#{height}" fill="#{fill}"/>),
      edge && edge_line(edge, x, y + height - 2, width),
      ~s|<g transform="translate(#{x + 24} #{y + (height - mark) / 2}) scale(#{mark / 16})" fill="none" stroke="#{color}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">| <>
        Enum.map_join(GuideComponents.verdict_paths(verdict.status), &~s(<path d="#{&1}"/>)) <>
        "</g>",
      ~s(<text x="#{text_x}" y="#{y + height / 2 + size * 0.36}" font-family="#{@display}" font-weight="700" font-size="#{size}" letter-spacing="1.6" fill="#{color}">#{escape(label)}</text>)
    ]
  end

  defp badge_colors(%{status: :good}), do: {@rise, @paper, nil}
  defp badge_colors(%{status: :expensive}), do: {@fall, @paper, nil}
  defp badge_colors(%{status: :normal}), do: {@ink, @paper, nil}

  defp badge_colors(%{status: status}) when status in [:cardmarket, :insufficient_data],
    do: {@paper, @ink, {@muted, "12 8"}}

  defp badge_colors(%{status: :out_of_stock}), do: {@paper, @ink, {@muted, "4 8"}}

  defp edge_line({color, dash}, x, y, width) do
    dash = if dash, do: ~s( stroke-dasharray="#{dash}"), else: ""

    ~s(<line x1="#{x}" y1="#{y}" x2="#{x + width}" y2="#{y}" stroke="#{color}" stroke-width="4"#{dash}/>)
  end

  # The packaging photo on a paper tile.
  defp photo_tile(png, x, y, size) do
    inset = 34

    [
      ~s(<rect x="#{x}" y="#{y}" width="#{size}" height="#{size}" fill="#{@paper}"/>),
      ~s(<image href="data:image/png;base64,#{Base.encode64(png)}" x="#{x + inset}" y="#{y + inset}" width="#{size - 2 * inset}" height="#{size - 2 * inset}" preserveAspectRatio="xMidYMid meet"/>)
    ]
  end

  defp photo(nil), do: :none

  defp photo(url) do
    with {:ok, body, _type} <- ImageDownload.fetch_stored(url),
         {:ok, image} <- Operation.thumbnail_buffer(body, 600, size: :VIPS_SIZE_DOWN),
         {:ok, png} <- Image.write(image, :memory, suffix: ".png") do
      {:ok, png}
    else
      _unusable -> :error
    end
  end

  # The verdict scale of the guide, as on a product page, without prices;
  # returns a function of its top edge and its height.
  defp scale_card(x, width) do
    inner = width - 64

    rows = [
      {%{status: :good}, gettext("do 95% typowej ceny")},
      {%{status: :normal}, gettext("do 110% typowej ceny")},
      {%{status: :expensive}, gettext("powyżej 110% typowej ceny")}
    ]

    heading = wrap(gettext("Widzisz cenę w sklepie?"), 34, :display, inner, 2)
    heading_height = 34 + length(heading) * 36
    row_height = 64 + 46
    height = heading_height + 20 + length(rows) * row_height + 10

    card = fn y ->
      rows_top = y + heading_height + 20

      [
        ~s(<rect x="#{x}" y="#{y}" width="#{width}" height="#{height}" fill="#{@paper}"/>),
        text_lines(heading, x + 32, y + 34, 34, 36, :display, @ink),
        rows
        |> Enum.with_index()
        |> Enum.map(fn {{verdict, note}, index} ->
          row_y = rows_top + index * row_height

          [
            badge(verdict, x + 32, row_y, 64, 36, inner),
            text_line(note, x + 32, row_y + 64 + 30, 20, :mono, @muted)
          ]
        end)
      ]
    end

    {card, height}
  end

  defp background, do: ~s(<rect width="#{@width}" height="#{@height}" fill="#{@bench}"/>)

  defp logo(x, y, height) do
    %{logo: logo} = assets()

    ~s(<image href="data:image/webp;base64,#{logo}" x="#{x}" y="#{y}" width="#{round(height * @logo_ratio)}" height="#{height}"/>)
  end

  # The largest size at which the whole name fits the room in balanced
  # lines; otherwise the smallest size, in as many lines as the room holds,
  # ellipsized.
  defp fit_title(name, width, room, max_lines, sizes \\ @title_sizes) do
    Enum.find_value(sizes, fn size ->
      lines = greedy(name, size, :display, width)
      fits? = length(lines) <= max_lines and length(lines) * round(size * 0.96) <= room
      if fits?, do: {size, balanced(name, size, :display, width, max_lines)}
    end) ||
      {@min_title,
       wrap(
         name,
         @min_title,
         :display,
         width,
         room |> div(round(@min_title * 0.96)) |> max(1) |> min(max_lines)
       )}
  end

  defp text_lines(lines, x, top, size, line_height, font, color, anchor \\ "start") do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      text_line(line, x, top + index * line_height + round(size * 0.8), size, font, color, anchor)
    end)
  end

  defp text_line(text, x, baseline, size, font, color, anchor \\ "start") do
    {family, weight} = font_face(font)

    ~s(<text x="#{x}" y="#{baseline}" text-anchor="#{anchor}" font-family="#{family}" font-weight="#{weight}" font-size="#{size}" fill="#{color}">#{escape(text)}</text>)
  end

  defp font_face(:display), do: {@display, 700}
  defp font_face(:mono), do: {@mono, 400}

  # Single spaces, and none of the control characters XML forbids.
  defp normalize(text),
    do:
      text
      |> String.replace(@xml_forbidden, "")
      |> String.split(@spaces, trim: true)
      |> Enum.join(" ")

  # The fewest lines greedy wrapping needs, then the split with the most
  # even line widths, so no word is left alone on the last line.
  defp balanced(text, size, font, width, max_lines) do
    words = String.split(text, " ", trim: true)
    count = length(greedy(text, size, font, width))

    if count <= 1 or count > max_lines or length(words) > 24 do
      wrap(text, size, font, width, max_lines)
    else
      words
      |> splits(count)
      |> Enum.map(fn lines -> Enum.map(lines, &Enum.join(&1, " ")) end)
      |> Enum.filter(fn lines -> Enum.all?(lines, &(text_width(&1, size, font) <= width)) end)
      |> Enum.min_by(
        fn lines -> lines |> Enum.map(&text_width(&1, size, font)) |> Enum.max() end,
        fn -> wrap(text, size, font, width, max_lines) end
      )
    end
  end

  # Every way to cut `words` into `count` non-empty lines.
  defp splits(words, 1), do: [[words]]

  defp splits(words, count) do
    for cut <- 1..(length(words) - count + 1)//1,
        {line, rest} = Enum.split(words, cut),
        tail <- splits(rest, count - 1),
        do: [line | tail]
  end

  defp greedy(text, size, font, width) do
    {lines, current} =
      text
      |> String.split(" ", trim: true)
      |> Enum.reduce({[], nil}, fn
        word, {lines, nil} ->
          {lines, word}

        word, {lines, current} ->
          candidate = current <> " " <> word

          if text_width(candidate, size, font) <= width,
            do: {lines, candidate},
            else: {[current | lines], word}
      end)

    Enum.reverse(if current, do: [current | lines], else: lines)
  end

  # Greedy lines, at most `max_lines`; a line that does not fit, or the last
  # one when text is left over, ends in an ellipsis.
  defp wrap(text, size, font, width, max_lines) do
    lines = greedy(normalize(text), size, font, width)

    if length(lines) > max_lines do
      {kept, [last | _rest]} = Enum.split(lines, max_lines - 1)

      Enum.map(kept, &ellipsize(&1, size, font, width, false)) ++
        [ellipsize(last, size, font, width)]
    else
      Enum.map(lines, &ellipsize(&1, size, font, width, false))
    end
  end

  # The longest start of the line that fits with an ellipsis; a line that
  # fits as it is stays unless the ellipsis is forced.
  defp ellipsize(line, size, font, width, forced? \\ true)

  defp ellipsize(line, size, font, width, false) do
    if text_width(line, size, font) <= width,
      do: line,
      else: ellipsize(line, size, font, width, true)
  end

  defp ellipsize(line, size, font, width, true) do
    line
    |> String.graphemes()
    |> Enum.scan(&(&2 <> &1))
    |> Enum.take_while(&(text_width(&1 <> "…", size, font) <= width))
    |> List.last("")
    |> String.trim_trailing()
    |> Kernel.<>("…")
  end

  # Advance widths in em: Azeret Mono is monospaced; Barlow Condensed Bold
  # by character class, from the font's metrics, slightly generous.
  defp text_width(text, size, font, letter_spacing \\ 0)

  defp text_width(text, size, :mono, letter_spacing),
    do: String.length(text) * (0.65 * size + letter_spacing)

  defp text_width(text, size, :display, letter_spacing) do
    text
    |> String.graphemes()
    |> Enum.reduce(0, fn grapheme, sum -> sum + display_em(grapheme) * size + letter_spacing end)
  end

  defp display_em(grapheme) do
    cond do
      grapheme in [" ", " "] -> 0.2
      String.contains?("iljI|!.,:;'`·", grapheme) -> 0.23
      String.contains?("frt1()-[]{}\"*", grapheme) -> 0.33
      String.contains?("mwMW%@&#", grapheme) -> 0.69
      true -> 0.47
    end
  end

  defp escape(text),
    do: text |> normalize() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  # An SVG to a JPEG: resvg draws it, libvips encodes it far smaller than
  # the PNG, which matters to messengers that drop large previews.
  defp render(parts) do
    %{fontdb: fontdb} = assets()

    svg = [
      ~s(<svg xmlns="http://www.w3.org/2000/svg" width="#{@width}" height="#{@height}" viewBox="0 0 #{@width} #{@height}">),
      ~s(<defs><filter id="lift" x="-25%" y="-25%" width="150%" height="150%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#{@ink}" flood-opacity="0.28"/></filter></defs>),
      parts |> List.flatten() |> Enum.filter(&is_binary/1),
      "</svg>"
    ]

    with {:ok, png} <-
           svg
           |> IO.iodata_to_binary()
           |> Resvg.svg_string_to_png_binary(fontdb: fontdb, resources_dir: System.tmp_dir!()),
         {:ok, image} <- Image.from_binary(png) do
      Image.write(image, :memory, suffix: ".jpg", quality: 90, strip_metadata: true)
    end
  end

  # Renders block a normal scheduler (the resvg NIF is not dirty) and need
  # memory for the photo, so at most @max_renders run at once; others wait
  # a few seconds for a slot.
  defp with_slot(fun, waited \\ 0) do
    %{slots: slots} = assets()

    cond do
      :atomics.add_get(slots, 1, 1) <= @max_renders ->
        try do
          fun.()
        after
          :atomics.sub(slots, 1, 1)
        end

      waited < @slot_wait_ms ->
        :atomics.sub(slots, 1, 1)
        Process.sleep(100)
        with_slot(fun, waited + 100)

      true ->
        :atomics.sub(slots, 1, 1)
        {:error, :busy}
    end
  end

  # The font database, the logo and the render slots, loaded once per node.
  defp assets do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        {:ok, fontdb} =
          Resvg.init_fontdb(
            font_dirs: [Application.app_dir(:tcg_cheap, "priv/social_fonts")],
            skip_system_fonts: true
          )

        logo =
          :tcg_cheap
          |> Application.app_dir("priv/static/images/tcg-cheap.webp")
          |> File.read!()
          |> Base.encode64()

        assets = %{fontdb: fontdb, logo: logo, slots: :atomics.new(1, signed: true)}
        :persistent_term.put(__MODULE__, assets)
        assets

      assets ->
        assets
    end
  end
end
