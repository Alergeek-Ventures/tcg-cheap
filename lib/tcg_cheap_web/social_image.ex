defmodule TcgCheapWeb.SocialImage do
  @moduledoc """
  Link-preview cards (Open Graph, 1200×630 JPEG) for the buying guide: the
  home page and each product, drawn as SVG in the guide's look, rendered
  with resvg and the bundled fonts (`priv/social_fonts`, OFL; full Latin
  Extended, unlike the subset web fonts) and encoded with libvips.

  A product card shows the same answer as its page: the verdict, the
  cheapest in-stock price and shop, the typical and suggested prices. Its
  photo comes only from the allowlisted image hosts, at most 15 MB and 40
  megapixels, shrunk before it is drawn. At most two cards render at once;
  `TcgCheapWeb.SocialImageController` keeps rendered cards in storage.
  """

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Catalogue.ExternalImage
  alias TcgCheap.Sealed.{PriceGuide, Shops}
  alias TcgCheapWeb.{GuideComponents, Polish}
  alias Vix.Vips.Operation

  # Bump when the layout changes, so stored and cached cards are replaced.
  @design 2

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

  # The logo is 405×96.
  @logo_ratio 405 / 96
  @max_photo_bytes 15_000_000
  @max_photo_pixels 40_000_000
  @photo_download_ms 8_000
  @max_renders 2
  # A render waits this long for a free slot before giving up.
  @slot_wait_ms 3_000
  @min_title 40

  def width, do: @width
  def height, do: @height

  @doc "A version of what the home card shows, for its storage key and URL."
  @spec home_version() :: String.t()
  def home_version, do: version(length(Shops.all()))

  @doc "A version of what a product's card shows, for its storage key and URL."
  @spec product_version(map()) :: String.t()
  def product_version(%{product: product, verdict: verdict} = page) do
    version(
      {product.name, product.image_url, product.kind, product.set_name, product.region,
       verdict.status, verdict.cheapest && {verdict.cheapest.price, verdict.cheapest.shop},
       verdict.typical, verdict.last_known, page.suggested_price && page.suggested_price.price}
    )
  end

  defp version(content),
    do: {@design, content} |> :erlang.phash2() |> Integer.to_string(36) |> String.downcase()

  @doc "The promise under the home card's headline."
  @spec home_promise() :: String.t()
  def home_promise,
    do:
      gettext("Ceny Pokémon TCG z %{count} polskich sklepów, sprawdzane codziennie.",
        count: length(Shops.all())
      )

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
      photo = photo(product.image_url)

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

  # Badge, price and shop, then the typical and suggested prices, stacked
  # up from the bottom edge; returns the SVG and its height.
  defp answer_block(page, x, width) do
    %{verdict: verdict} = page

    {price, shop_line} =
      case verdict do
        %{cheapest: %{price: price} = cheapest} ->
          {{Polish.price(price), 104, @ink},
           gettext("najtaniej teraz w %{shop}", shop: GuideComponents.shop_name(cheapest))}

        %{last_known: %{price: price, date: date}} ->
          {{Polish.price(price), 68, @muted},
           gettext("ostatnio najtaniej · %{date}", date: Calendar.strftime(date, "%d.%m.%Y"))}

        _verdict ->
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

    shop_lines = wrap(shop_line, 23, :mono, width, 2)
    badge_height = 72
    price_height = price_height(price)
    shop_height = length(shop_lines) * 34
    notes_height = if notes == [], do: 0, else: 12 + length(notes) * 30
    height = badge_height + 26 + price_height + shop_height + notes_height
    top = @height - @margin - height
    price_top = top + badge_height + 26
    shop_top = price_top + price_height

    svg = [
      badge(verdict, x, top, badge_height, 40),
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
  defp typical_note(%{typical: %Decimal{} = typical, typical_source: :shops}),
    do:
      gettext("Typowa cena z %{days} dni: %{price}",
        days: PriceGuide.window_days(),
        price: Polish.zloty(typical)
      )

  defp typical_note(_verdict), do: nil

  # The guide's large verdict badge: filled for good, normal and expensive
  # (and a clear Cardmarket difference), a paper slip with a drawn bottom
  # edge otherwise; text and mark carry the meaning, never colour alone.
  defp badge(verdict, x, y, height, size, width \\ nil) do
    {fill, color, edge} = badge_colors(verdict)
    label = verdict |> GuideComponents.verdict_label() |> String.upcase()
    mark? = verdict.status != :cardmarket
    mark = round(size * 0.7)
    text_x = x + 24 + if(mark?, do: mark + 14, else: 0)
    width = width || text_x - x + text_width(label, size, :display, 1.6) + 24

    [
      ~s(<rect x="#{x}" y="#{y}" width="#{round(width)}" height="#{height}" fill="#{fill}"/>),
      edge && edge_line(edge, x, y + height - 2, width),
      mark? &&
        ~s|<g transform="translate(#{x + 24} #{y + (height - mark) / 2}) scale(#{mark / 16})" fill="none" stroke="#{color}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">| <>
          Enum.map_join(GuideComponents.verdict_paths(verdict.status), &~s(<path d="#{&1}"/>)) <>
          "</g>",
      ~s(<text x="#{text_x}" y="#{y + height / 2 + size * 0.36}" font-family="#{@display}" font-weight="700" font-size="#{size}" letter-spacing="1.6" fill="#{color}">#{escape(label)}</text>)
    ]
  end

  defp badge_colors(%{status: :good}), do: {@rise, @paper, nil}
  defp badge_colors(%{status: :expensive}), do: {@fall, @paper, nil}
  defp badge_colors(%{status: :normal}), do: {@ink, @paper, nil}
  defp badge_colors(%{status: :insufficient_data}), do: {@paper, @ink, {@muted, "12 8"}}
  defp badge_colors(%{status: :out_of_stock}), do: {@paper, @ink, {@muted, "4 8"}}

  defp badge_colors(%{status: :cardmarket} = verdict) do
    case GuideComponents.cardmarket_tone(verdict) do
      :below -> {@rise, @paper, nil}
      :above -> {@fall, @paper, nil}
      nil -> {@paper, @ink, {@ink, nil}}
    end
  end

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

  # The shop photo shrunk to the tile (libvips reads the header first, so an
  # oversized image is refused before it is decoded).
  defp photo(url) do
    if ExternalImage.valid?(url), do: fetch_photo(url), else: :none
  end

  defp fetch_photo(url) do
    with {:ok, body} <- download(url),
         {:ok, header} <- Image.from_binary(body),
         true <- Image.width(header) * Image.height(header) <= @max_photo_pixels,
         {:ok, image} <- Operation.thumbnail_buffer(body, 600, size: :VIPS_SIZE_DOWN),
         {:ok, png} <- Image.write(image, :memory, suffix: ".png") do
      {:ok, png}
    else
      _unusable -> :error
    end
  end

  # The whole download, connecting included, within the deadline.
  defp download(url) do
    deadline = System.monotonic_time(:millisecond) + @photo_download_ms

    task =
      Task.async(fn ->
        Req.get(url,
          headers: [{"user-agent", "TcgCheap/1.0 (buying guide)"}],
          decode_body: false,
          into: &bounded_body(&1, &2, deadline),
          connect_options: [timeout: 3_000],
          receive_timeout: 5_000,
          redirect: false,
          retry: false
        )
      end)

    case Task.yield(task, @photo_download_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %Req.Response{status: 200, body: body}}} when is_binary(body) -> {:ok, body}
      _failed -> :error
    end
  end

  # Stops a body that is too large or still trickling in after the deadline.
  defp bounded_body({:data, data}, {request, response}, deadline) do
    body = if is_binary(response.body), do: response.body, else: ""

    cond do
      byte_size(body) + byte_size(data) > @max_photo_bytes ->
        {:halt, {request, %{response | body: :too_large}}}

      System.monotonic_time(:millisecond) > deadline ->
        {:halt, {request, %{response | body: :too_slow}}}

      true ->
        {:cont, {request, %{response | body: body <> data}}}
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
  defp fit_title(name, width, room, max_lines) do
    sizes = [72, 64, 56, 50, 44, @min_title]

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

  defp text_lines(lines, x, top, size, line_height, font, color) do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      text_line(line, x, top + index * line_height + round(size * 0.8), size, font, color)
    end)
  end

  defp text_line(text, x, baseline, size, font, color) do
    {family, weight} = font_face(font)

    ~s(<text x="#{x}" y="#{baseline}" font-family="#{family}" font-weight="#{weight}" font-size="#{size}" fill="#{color}">#{escape(text)}</text>)
  end

  defp font_face(:display), do: {@display, 700}
  defp font_face(:mono), do: {@mono, 400}

  # Single spaces, and none of the control characters XML forbids.
  defp normalize(text),
    do:
      text
      |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/u, "")
      |> String.split(~r/\s+/u, trim: true)
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
